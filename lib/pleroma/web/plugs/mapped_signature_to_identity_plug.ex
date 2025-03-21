# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Plugs.MappedSignatureToIdentityPlug do
  alias Pleroma.Helpers.AuthHelper
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Utils

  import Plug.Conn
  require Logger

  def init(options), do: options

  def call(%{assigns: %{user: %User{}}} = conn, _opts), do: conn

  # if this has payload make sure it is signed by the same actor that made it
  def call(%{assigns: %{valid_signature: true}, params: %{"actor" => actor}} = conn, _opts) do
    with actor_id <- Utils.get_ap_id(actor),
         {:user, %User{} = user} <- {:user, user_from_key_id(conn)},
         {:federate, true} <- {:federate, should_federate?(user)},
         {:user_match, true} <- {:user_match, user.ap_id == actor_id} do
      conn
      |> assign(:user, user)
      |> AuthHelper.skip_oauth()
    else
      {:user_match, false} ->
        Logger.debug("Failed to map identity from signature (payload actor mismatch)")
        Logger.debug("key_id=#{inspect(key_id_from_conn(conn))}, actor=#{inspect(actor)}")

        conn
        |> assign(:valid_signature, false)

      # remove me once testsuite uses mapped capabilities instead of what we do now
      {:user, _} ->
        Logger.debug("Failed to map identity from signature (lookup failure)")
        Logger.debug("key_id=#{inspect(key_id_from_conn(conn))}, actor=#{actor}")

        conn
        |> assign(:valid_signature, false)

      {:federate, false} ->
        Logger.debug("Identity from signature is instance blocked")
        Logger.debug("key_id=#{inspect(key_id_from_conn(conn))}, actor=#{actor}")

        conn
        |> assign(:valid_signature, false)
    end
  end

  # no payload, probably a signed fetch
  def call(%{assigns: %{valid_signature: true}} = conn, _opts) do
    with %User{} = user <- user_from_key_id(conn),
         {:federate, true} <- {:federate, should_federate?(user)} do
      conn
      |> assign(:user, user)
      |> AuthHelper.skip_oauth()
    else
      {:federate, false} ->
        Logger.debug("Identity from signature is instance blocked")
        Logger.debug("key_id=#{inspect(key_id_from_conn(conn))}")

        conn
        |> assign(:valid_signature, false)

      nil ->
        Logger.debug("Failed to map identity from signature (lookup failure)")
        Logger.debug("key_id=#{inspect(key_id_from_conn(conn))}")

        conn
        |> assign(:valid_signature, false)

      _ ->
        Logger.debug("Failed to map identity from signature (no payload actor mismatch)")
        Logger.debug("key_id=#{inspect(key_id_from_conn(conn))}")

        conn
        |> assign(:valid_signature, false)
    end
  end

  # no signature at all
  def call(conn, _opts), do: conn

  defp key_id_from_conn(conn) do
    case HTTPSignatures.signature_for_conn(conn) do
      %{"keyId" => key_id} when is_binary(key_id) ->
        key_id

      _ ->
        nil
    end
  end

  defp user_from_key_id(conn) do
    with {:key_id, key_id} when is_binary(key_id) <- {:key_id, key_id_from_conn(conn)},
         {:mapped_ap_id, ap_id} when is_binary(ap_id) <-
           {:mapped_ap_id, User.SigningKey.key_id_to_ap_id(key_id)},
         {:user_fetch, {:ok, %User{} = user}} <- {:user_fetch, User.get_or_fetch_by_ap_id(ap_id)} do
      user
    else
      {:key_id, nil} ->
        Logger.debug("Failed to map identity from signature (no key ID)")
        {:key_id, nil}

      {:mapped_ap_id, nil} ->
        Logger.debug("Failed to map identity from signature (could not map key ID to AP ID)")
        {:mapped_ap_id, nil}

      {:user_fetch, {:error, _}} ->
        Logger.debug("Failed to map identity from signature (lookup failure)")
        {:user_fetch, nil}
    end
  end

  defp should_federate?(%User{ap_id: ap_id}), do: should_federate?(ap_id)

  defp should_federate?(ap_id) do
    if Pleroma.Config.get([:activitypub, :authorized_fetch_mode], false) do
      Pleroma.Web.ActivityPub.Publisher.should_federate?(ap_id)
    else
      true
    end
  end
end
