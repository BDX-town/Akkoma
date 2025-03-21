# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.UploadedMedia do
  @moduledoc """
  """

  import Plug.Conn
  import Pleroma.Web.Gettext
  require Logger

  alias Pleroma.Web.MediaProxy
  alias Pleroma.Web.Plugs.Utils

  @behaviour Plug
  # no slashes
  @path "media"

  @default_cache_control_header "public, max-age=1209600"

  def init(_opts) do
    static_plug_opts =
      [
        headers: %{"cache-control" => @default_cache_control_header},
        cache_control_for_etags: @default_cache_control_header
      ]
      |> Keyword.put(:from, "__unconfigured_media_plug")
      |> Keyword.put(:at, "/__unconfigured_media_plug")
      |> Plug.Static.init()

    config = Pleroma.Config.get(Pleroma.Upload)
    allowed_mime_types = Keyword.fetch!(config, :allowed_mime_types)
    uploader = Keyword.fetch!(config, :uploader)

    %{
      static_plug_opts: static_plug_opts,
      allowed_mime_types: allowed_mime_types,
      uploader: uploader
    }
  end

  def call(
        %{request_path: <<"/", @path, "/", file::binary>>} = conn,
        %{uploader: uploader} = opts
      ) do
    conn =
      case fetch_query_params(conn) do
        %{query_params: %{"name" => name}} = conn ->
          name = escape_header_value(name)

          put_resp_header(conn, "content-disposition", ~s[inline; filename="#{name}"])

        conn ->
          conn
      end
      |> merge_resp_headers([{"content-security-policy", "sandbox"}])

    with {:ok, get_method} <- uploader.get_file(file),
         false <- media_is_banned(conn, get_method) do
      get_media(conn, get_method, opts)
    else
      _ ->
        conn
        |> send_resp(:internal_server_error, dgettext("errors", "Failed"))
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp media_is_banned(%{request_path: path} = _conn, {:static_dir, _}) do
    MediaProxy.in_banned_urls(Pleroma.Upload.base_url() <> path)
  end

  defp media_is_banned(_, {:url, url}), do: MediaProxy.in_banned_urls(url)

  defp media_is_banned(_, _), do: false

  defp set_content_type(conn, opts, filepath) do
    real_mime = MIME.from_path(filepath)
    clean_mime = Utils.get_safe_mime_type(opts, real_mime)
    put_resp_header(conn, "content-type", clean_mime)
  end

  defp get_media(conn, {:static_dir, directory}, opts) do
    static_opts =
      Map.get(opts, :static_plug_opts)
      |> Map.put(:at, [@path])
      |> Map.put(:from, directory)
      |> Map.put(:content_types, false)

    conn =
      conn
      |> set_content_type(opts, conn.request_path)
      |> Plug.Static.call(static_opts)

    if conn.halted do
      conn
    else
      conn
      |> send_resp(:not_found, dgettext("errors", "Not found"))
      |> halt()
    end
  end

  defp get_media(conn, {:url, url}, _) do
    conn
    |> Phoenix.Controller.redirect(external: url)
    |> halt()
  end

  defp get_media(conn, unknown, _) do
    Logger.error("#{__MODULE__}: Unknown get startegy: #{inspect(unknown)}")

    conn
    |> send_resp(:internal_server_error, dgettext("errors", "Internal Error"))
    |> halt()
  end

  defp escape_header_value(value) do
    value
    |> String.replace("\"", "\\\"")
    |> String.replace("\\r", "")
    |> String.replace("\\n", "")
  end
end
