defmodule Pleroma.Search.Meilisearch do
  require Logger
  require Pleroma.Constants

  alias Pleroma.Activity

  import Pleroma.Search.DatabaseSearch

  @behaviour Pleroma.Search.SearchBackend

  defp meili_headers(key) do
    key_header =
      if is_nil(key), do: [], else: [{"Authorization", "Bearer #{key}"}]

    [{"Content-Type", "application/json"} | key_header]
  end

  defp meili_headers_admin do
    private_key = Pleroma.Config.get([Pleroma.Search.Meilisearch, :private_key])
    meili_headers(private_key)
  end

  defp meili_headers_search do
    search_key =
      Pleroma.Config.get([Pleroma.Search.Meilisearch, :search_key]) ||
        Pleroma.Config.get([Pleroma.Search.Meilisearch, :private_key])

    meili_headers(search_key)
  end

  def meili_get(path) do
    endpoint = Pleroma.Config.get([Pleroma.Search.Meilisearch, :url])

    result =
      Pleroma.HTTP.get(
        Path.join(endpoint, path),
        meili_headers_admin()
      )

    with {:ok, res} <- result do
      {:ok, Jason.decode!(res.body)}
    end
  end

  defp meili_search(params) do
    endpoint = Pleroma.Config.get([Pleroma.Search.Meilisearch, :url])

    result =
      Pleroma.HTTP.post(
        Path.join(endpoint, "/indexes/objects/search"),
        Jason.encode!(params),
        meili_headers_search()
      )

    with {:ok, res} <- result do
      {:ok, Jason.decode!(res.body)}
    end
  end

  def meili_put(path, params) do
    endpoint = Pleroma.Config.get([Pleroma.Search.Meilisearch, :url])

    result =
      Pleroma.HTTP.request(
        :put,
        Path.join(endpoint, path),
        Jason.encode!(params),
        meili_headers_admin(),
        []
      )

    with {:ok, res} <- result do
      {:ok, Jason.decode!(res.body)}
    end
  end

  def meili_delete!(path) do
    endpoint = Pleroma.Config.get([Pleroma.Search.Meilisearch, :url])

    {:ok, _} =
      Pleroma.HTTP.request(
        :delete,
        Path.join(endpoint, path),
        "",
        meili_headers_admin(),
        []
      )
  end

  def search(user, query, options \\ []) do
    limit = Enum.min([Keyword.get(options, :limit), 40])
    offset = Keyword.get(options, :offset, 0)
    author = Keyword.get(options, :author)

    res =
      meili_search(%{q: query, offset: offset, limit: limit})

    with {:ok, result} <- res do
      hits = result["hits"] |> Enum.map(& &1["ap"])

      try do
        hits
        |> Activity.get_presorted_create_by_object_ap_id()
        |> Activity.with_preloaded_object()
        |> Activity.restrict_deactivated_users()
        |> maybe_restrict_local(user)
        |> maybe_restrict_author(author)
        |> maybe_restrict_blocked(user)
        |> maybe_fetch(user, query)
        |> Pleroma.Repo.all()
      rescue
        _ -> maybe_fetch([], user, query)
      end
    end
  end

  def object_to_search_data(object) do
    # Only index public or unlisted Notes
    if not is_nil(object) and object.data["type"] == "Note" and
         not is_nil(object.data["content"]) and
         (Pleroma.Constants.as_public() in object.data["to"] or
            Pleroma.Constants.as_public() in object.data["cc"]) and
         String.length(object.data["content"]) > 1 do
      data = object.data

      content_str =
        case data["content"] do
          [nil | rest] -> to_string(rest)
          str -> str
        end

      content =
        with {:ok, scrubbed} <- FastSanitize.strip_tags(content_str),
             trimmed <- String.trim(scrubbed) do
          trimmed
        end

      if String.length(content) > 1 and not is_nil(data["published"]) do
        {:ok, published, _} = DateTime.from_iso8601(data["published"])

        %{
          id: object.id,
          content: content,
          ap: data["id"],
          published: published |> DateTime.to_unix()
        }
      end
    end
  end

  @impl true
  def add_to_index(activity) do
    maybe_search_data = object_to_search_data(activity.object)

    if activity.data["type"] == "Create" and maybe_search_data do
      result =
        meili_put(
          "/indexes/objects/documents",
          [maybe_search_data]
        )

      with {:ok, res} <- result,
           true <- Map.has_key?(res, "taskUid") do
        {:ok, res}
      else
        err ->
          Logger.error("Failed to add activity #{activity.id} to index: #{inspect(result)}")
          {:error, err}
      end
    end
  end

  @impl true
  def remove_from_index(object) do
    meili_delete!("/indexes/objects/documents/#{object.id}")
  end
end
