# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.HTTPSignaturePlug do
  import Plug.Conn
  import Phoenix.Controller, only: [get_format: 1]

  alias HTTPSignatures.HTTPKey

  use Pleroma.Web, :verified_routes
  alias Pleroma.Activity
  alias Pleroma.Instances
  require Logger

  @cachex Pleroma.Config.get([:cachex, :provider], Cachex)

  def init(options) do
    options
  end

  def call(%{assigns: %{valid_signature: true}} = conn, _opts) do
    conn
  end

  def call(conn, _opts) do
    if get_format(conn) in ["json", "activity+json"] do
      conn
      |> maybe_assign_valid_signature()
      |> maybe_record_signature_success()
    else
      conn
    end
  end

  def route_aliases(%{path_info: ["objects", id], query_string: query_string}) do
    ap_id = url(~p[/objects/#{id}])

    with %Activity{} = activity <- Activity.get_by_object_ap_id_with_object(ap_id) do
      [~p"/notice/#{activity.id}", "/notice/#{activity.id}?#{query_string}"]
    else
      _ -> []
    end
  end

  def route_aliases(_), do: []

  defp maybe_log_error_and_try_aliases(conn, verification_error, remaining_aliases) do
    case verification_error do
      {:gone, key_id} ->
        # We can't verify the data since the actor was deleted and not previously known.
        # Likely we just received the actor’s Delete activity, so just silently drop.
        Logger.debug("Unable to verify request signature of deleted actor; dropping (#{key_id})")
        conn

      :wrong_signature ->
        assign_valid_signature_on_route_aliases(conn, remaining_aliases)

      error ->
        Logger.error("Failed to verify request signature due to fatal error: #{inspect(error)}")
        conn
    end
  end

  defp assign_valid_signature_on_route_aliases(%{assigns: %{valid_signature: true}} = conn, _),
    do: conn

  defp assign_valid_signature_on_route_aliases(conn, []) do
    Logger.warning("Received request with invalid signature!\n#{inspect(conn)}")
    conn
  end

  defp assign_valid_signature_on_route_aliases(conn, [path | rest]) do
    request_target = String.downcase("#{conn.method}") <> " #{path}"

    case HTTPSignatures.validate_conn(conn, request_target) do
      {:ok, %HTTPKey{user_data: ud}} ->
        conn
        |> assign(:valid_signature, true)
        |> assign(:signature_user, ud["key_user"])

      {:error, e} ->
        conn
        |> assign(:valid_signature, false)
        |> assign(:signature_user, nil)
        |> maybe_log_error_and_try_aliases(e, rest)
    end
  end

  defp maybe_assign_valid_signature(conn) do
    if has_signature_header?(conn) do
      # set (request-target) header to the appropriate value
      # we also replace the digest header with the one we computed
      possible_paths =
        [conn.request_path, conn.request_path <> "?#{conn.query_string}" | route_aliases(conn)]

      conn =
        case conn do
          %{assigns: %{digest: digest}} = conn -> put_req_header(conn, "digest", digest)
          conn -> conn
        end

      assign_valid_signature_on_route_aliases(conn, possible_paths)
    else
      Logger.debug("No signature header!")
      conn
    end
  end

  defp has_signature_header?(conn) do
    conn |> get_req_header("signature") |> Enum.at(0, false)
  end

  defp maybe_record_signature_success(
         %{assigns: %{valid_signature: true, signature_user: signature_user}} = conn
       ) do
    # inboxes implicitly need http signatures for authentication
    # so we don't really know if the instance will have broken federation after
    # we turn on authorized_fetch_mode.
    #
    # to "check" this is a signed fetch, verify if method is GET
    if conn.method == "GET" do
      actor_host = URI.parse(signature_user.ap_id).host

      case @cachex.get(:request_signatures_cache, actor_host) do
        {:ok, nil} ->
          Logger.debug("Successful signature from #{actor_host}")
          Instances.set_request_signatures(actor_host)
          @cachex.put(:request_signatures_cache, actor_host, true)

        {:ok, true} ->
          :noop

        any ->
          Logger.warning(
            "expected request signature cache to return a boolean, instead got #{inspect(any)}"
          )
      end
    end

    conn
  end

  defp maybe_record_signature_success(conn), do: conn
end
