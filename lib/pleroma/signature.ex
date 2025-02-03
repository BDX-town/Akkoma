# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Signature do
  @behaviour HTTPSignatures.Adapter

  alias HTTPSignatures.HTTPKey
  alias Pleroma.User
  alias Pleroma.User.SigningKey
  require Logger

  def fetch_public_key(kid, _) do
    with {_, {:ok, %SigningKey{} = sk}} <- {:fetch, SigningKey.get_or_fetch_by_key_id(kid)},
         {_, {%User{} = key_user, _}} <- {:user, {User.get_by_id(sk.user_id), sk.user_id}},
         {_, {:ok, decoded_key}} <- {:decode, SigningKey.public_key_decoded(sk)} do
      {:ok, %HTTPKey{key: decoded_key, user_data: %{"key_user" => key_user}}}
    else
      e ->
        handle_common_errors(e, kid, "acquire")
    end
  end

  def refetch_public_key(kid, _) do
    with {_, {:ok, %SigningKey{} = sk}} <- {:fetch, SigningKey.refresh_by_key_id(kid)},
         {_, {%User{} = key_user, _}} <- {:user, {User.get_by_id(sk.user_id), sk.user_id}},
         {_, {:ok, decoded_key}} <- {:decode, SigningKey.public_key_decoded(sk)} do
      {:ok, %HTTPKey{key: decoded_key, user_data: %{"key_user" => key_user}}}
    else
      {:fetch, {:error, :too_young}} ->
        Logger.debug("Refusing to refetch recently updated key: #{kid}")
        {:error, {:too_young, kid}}

      {:fetch, {:error, :unknown}} ->
        Logger.warning("Attempted to refresh unknown key; this should not happen: #{kid}")
        {:error, {:unknown, kid}}

      e ->
        handle_common_errors(e, kid, "refresh stale")
    end
  end

  defp handle_common_errors(error, kid, action_name) do
    case error do
      {:fetch, {:error, :not_found}} ->
        {:halt, {:error, :gone}}

      {:fetch, {:reject, reason}} ->
        {:halt, {:error, {:reject, reason}}}

      {:fetch, error} ->
        Logger.error("Failed to #{action_name} key from signature: #{kid} #{inspect(error)}")
        {:error, {:fetch, error}}

      {:user, {_, uid}} ->
        Logger.warning(
          "Failed to resolve user (id=#{uid}) for retrieved signing key. Race condition?"
        )

      e ->
        {:error, e}
    end
  end

  def sign(%User{} = user, headers) do
    with {:ok, private_key} <- SigningKey.private_key(user) do
      HTTPSignatures.sign(
        %HTTPKey{key: private_key},
        SigningKey.local_key_id(user.ap_id),
        headers
      )
    end
  end

  def signed_date, do: signed_date(NaiveDateTime.utc_now())

  def signed_date(%NaiveDateTime{} = date) do
    Timex.lformat!(date, "{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} GMT", "en")
  end
end
