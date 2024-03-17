# Akkoma: Magically expressive social media
# Copyright © 2024 Akkoma Authors <https://akkoma.dev/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Mix.Tasks.Pleroma.Security do
  use Mix.Task
  import Mix.Pleroma

  alias Pleroma.Config

  require Logger

  @shortdoc """
  Security-related tasks, like e.g. checking for signs past exploits were abused.
  """

  # Constants etc
  defp local_id_prefix(), do: Pleroma.Web.Endpoint.url() <> "/"

  defp local_id_pattern(), do: local_id_prefix() <> "%"

  @activity_exts ["activity+json", "activity%2Bjson"]

  defp activity_ext_url_patterns() do
    for e <- @activity_exts do
      for suf <- ["", "?%"] do
        # Escape literal % for use in SQL patterns
        ee = String.replace(e, "%", "\\%")
        "%.#{ee}#{suf}"
      end
    end
    |> List.flatten()
  end

  # Search for malicious uploads exploiting the lack of Content-Type sanitisation from before 2024-03
  def run(["spoof-uploaded"]) do
    Logger.put_process_level(self(), :notice)
    start_pleroma()

    IO.puts("""
    +------------------------+
    |  SPOOF SEARCH UPLOADS  |
    +------------------------+
    Checking if any uploads are using privileged types.
    NOTE if attachment deletion is enabled, payloads used
         in the past may no longer exist.
    """)

    do_spoof_uploaded()
  end

  # +-----------------------------+
  # | S P O O F - U P L O A D E D |
  # +-----------------------------+
  defp do_spoof_uploaded() do
    files =
      case Config.get!([Pleroma.Upload, :uploader]) do
        Pleroma.Uploaders.Local ->
          uploads_search_spoofs_local_dir(Config.get!([Pleroma.Uploaders.Local, :uploads]))

        _ ->
          IO.puts("""
          NOTE:
            Not using local uploader; thus not affected by this exploit.
            It's impossible to check for files, but in case local uploader was used before
            or to check if anyone futilely attempted a spoof, notes will still be scanned.
          """)

          []
      end

    emoji = uploads_search_spoofs_local_dir(Config.get!([:instance, :static_dir]))

    post_attachs = uploads_search_spoofs_notes()

    not_orphaned_urls =
      post_attachs
      |> Enum.map(fn {_u, _a, url} -> url end)
      |> MapSet.new()

    orphaned_attachs = upload_search_orphaned_attachments(not_orphaned_urls)

    IO.puts("\nSearch concluded; here are the results:")
    pretty_print_list_with_title(emoji, "Emoji")
    pretty_print_list_with_title(files, "Uploaded Files")
    pretty_print_list_with_title(post_attachs, "(Not Deleted) Post Attachments")
    pretty_print_list_with_title(orphaned_attachs, "Orphaned Uploads")

    IO.puts("""
    In total found
      #{length(emoji)} emoji
      #{length(files)} uploads
      #{length(post_attachs)} not deleted posts
      #{length(orphaned_attachs)} orphaned attachments
    """)
  end

  defp uploads_search_spoofs_local_dir(dir) do
    local_dir = String.replace_suffix(dir, "/", "")

    IO.puts("Searching for suspicious files in #{local_dir}...")

    glob_ext = "{" <> Enum.join(@activity_exts, ",") <> "}"

    Path.wildcard(local_dir <> "/**/*." <> glob_ext, match_dot: true)
    |> Enum.map(fn path ->
      String.replace_prefix(path, local_dir <> "/", "")
    end)
    |> Enum.sort()
  end

  defp uploads_search_spoofs_notes() do
    IO.puts("Now querying DB for posts with spoofing attachments. This might take a while...")

    patterns = [local_id_pattern() | activity_ext_url_patterns()]

    # if jsonb_array_elemsts in FROM can be used with normal Ecto functions, idk how
    """
    SELECT DISTINCT a.data->>'actor', a.id, url->>'href'
    FROM public.objects AS o JOIN public.activities AS a
         ON o.data->>'id' = a.data->>'object',
       jsonb_array_elements(o.data->'attachment') AS attachs,
       jsonb_array_elements(attachs->'url') AS url
    WHERE o.data->>'type' = 'Note' AND
          o.data->>'id' LIKE $1::text AND (
            url->>'href' LIKE $2::text OR
            url->>'href' LIKE $3::text OR
            url->>'href' LIKE $4::text OR
            url->>'href' LIKE $5::text
          )
    ORDER BY a.data->>'actor', a.id, url->>'href';
    """
    |> Pleroma.Repo.query!(patterns, timeout: :infinity)
    |> map_raw_id_apid_tuple()
  end

  defp upload_search_orphaned_attachments(not_orphaned_urls) do
    IO.puts("""
    Now querying DB for orphaned spoofing attachment (i.e. their post was deleted,
    but if :cleanup_attachments was not enabled traces remain in the database)
    This might take a bit...
    """)

    patterns = activity_ext_url_patterns()

    """
    SELECT DISTINCT attach.id, url->>'href'
    FROM public.objects AS attach,
         jsonb_array_elements(attach.data->'url') AS url
    WHERE (attach.data->>'type' = 'Image' OR
           attach.data->>'type' = 'Document')
          AND (
            url->>'href' LIKE $1::text OR
            url->>'href' LIKE $2::text OR
            url->>'href' LIKE $3::text OR
            url->>'href' LIKE $4::text
          )
    ORDER BY attach.id, url->>'href';
    """
    |> Pleroma.Repo.query!(patterns, timeout: :infinity)
    |> then(fn res -> Enum.map(res.rows, fn [id, url] -> {id, url} end) end)
    |> Enum.filter(fn {_, url} -> !(url in not_orphaned_urls) end)
  end

  # +-----------------------------------+
  # | module-specific utility functions |
  # +-----------------------------------+
  defp pretty_print_list_with_title(list, title) do
    title_len = String.length(title)
    title_underline = String.duplicate("=", title_len)
    IO.puts(title)
    IO.puts(title_underline)
    pretty_print_list(list)
  end

  defp pretty_print_list([]), do: IO.puts("")

  defp pretty_print_list([{a, o} | rest])
       when (is_binary(a) or is_number(a)) and is_binary(o) do
    IO.puts("  {#{a}, #{o}}")
    pretty_print_list(rest)
  end

  defp pretty_print_list([{u, a, o} | rest])
       when is_binary(a) and is_binary(u) and is_binary(o) do
    IO.puts("  {#{u}, #{a}, #{o}}")
    pretty_print_list(rest)
  end

  defp pretty_print_list([e | rest]) when is_binary(e) do
    IO.puts("  #{e}")
    pretty_print_list(rest)
  end

  defp pretty_print_list([e | rest]), do: pretty_print_list([inspect(e) | rest])

  defp map_raw_id_apid_tuple(res) do
    user_prefix = local_id_prefix() <> "users/"

    Enum.map(res.rows, fn
      [uid, aid, oid] ->
        {
          String.replace_prefix(uid, user_prefix, ""),
          FlakeId.to_string(aid),
          oid
        }
    end)
  end
end
