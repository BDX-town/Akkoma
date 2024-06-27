# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Signature do
  @behaviour HTTPSignatures.Adapter

  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.User.SigningKey

  def key_id_to_actor_id(key_id) do
    # Given the key ID, first attempt to look it up in the signing keys table.
    # If it's not found, then attempt to look it up via request to the remote instance.
    case SigningKey.key_id_to_ap_id(key_id) do
      nil ->
        # this requires us to look up the url!
        request_key_id_from_remote_instance(key_id)

      key ->
        {:ok, key}
    end
  end

  def request_key_id_from_remote_instance(key_id) do
    case SigningKey.fetch_remote_key(key_id) do
      {:ok, key_id} ->
        {:ok, key_id}

      {:error, _} ->
        {:error, "Key ID not found"}
    end
  end

  def fetch_public_key(conn) do
    with %{"keyId" => kid} <- HTTPSignatures.signature_for_conn(conn),
         {:ok, actor_id} <- key_id_to_actor_id(kid),
         {:ok, public_key} <- User.get_public_key_for_ap_id(actor_id) do
      {:ok, public_key}
    else
      e ->
        {:error, e}
    end
  end

  def refetch_public_key(conn) do
    with %{"keyId" => kid} <- HTTPSignatures.signature_for_conn(conn),
         {:ok, actor_id} <- key_id_to_actor_id(kid),
         {:ok, _user} <- ActivityPub.make_user_from_ap_id(actor_id),
         {:ok, public_key} <- User.get_public_key_for_ap_id(actor_id) do
      {:ok, public_key}
    else
      e ->
        {:error, e}
    end
  end

  def sign(%User{} = user, headers) do
    with {:ok, private_key} <- SigningKey.private_key(user) do
      HTTPSignatures.sign(private_key, user.ap_id <> "#main-key", headers)
    end
  end

  def signed_date, do: signed_date(NaiveDateTime.utc_now())

  def signed_date(%NaiveDateTime{} = date) do
    Timex.lformat!(date, "{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} GMT", "en")
  end
end
