# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Signature do
  @behaviour HTTPSignatures.Adapter

  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.User.SigningKey
  require Logger

  def key_id_to_actor_id(key_id) do
    # Given the key ID, first attempt to look it up in the signing keys table.
    case SigningKey.key_id_to_ap_id(key_id) do
      nil ->
        # hm, we SHOULD have gotten this in the pipeline before we hit here!
        Logger.error("Could not figure out who owns the key #{key_id}")
        {:error, :key_owner_not_found}

      key ->
        {:ok, key}
    end
  end

  def fetch_public_key(conn) do
    with %{"keyId" => kid} <- HTTPSignatures.signature_for_conn(conn),
         {:ok, %SigningKey{}} <- SigningKey.get_or_fetch_by_key_id(kid),
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
         {:ok, %SigningKey{}} <- SigningKey.get_or_fetch_by_key_id(kid),
         {:ok, actor_id} <- key_id_to_actor_id(kid),
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
