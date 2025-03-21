# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.MRF.ObjectAgePolicy do
  alias Pleroma.Config
  alias Pleroma.User

  require Pleroma.Constants

  @moduledoc "Filter activities depending on their age"
  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  defp check_date(%{"object" => %{"published" => published}} = message) do
    with %DateTime{} = now <- DateTime.utc_now(),
         {:ok, %DateTime{} = then, _} <- DateTime.from_iso8601(published),
         max_ttl <- Config.get([:mrf_object_age, :threshold]),
         {:ttl, false} <- {:ttl, DateTime.diff(now, then) > max_ttl} do
      {:ok, message}
    else
      {:ttl, true} ->
        {:reject, nil}

      e ->
        {:error, e}
    end
  end

  defp check_reject(message, actions) do
    if :reject in actions do
      {:reject, "[ObjectAgePolicy]"}
    else
      {:ok, message}
    end
  end

  @spec delete_and_count(list(), term()) :: {integer(), list()}
  defp delete_and_count(list, element), do: delete_and_count(list, element, {0, [], list})

  defp delete_and_count([], _element, {0, _nlist, olist}), do: {0, olist}
  defp delete_and_count([], _element, {count, nlist, _olist}), do: {count, Enum.reverse(nlist)}

  defp delete_and_count([h | r], h, {count, nlist, olist}),
    do: delete_and_count(r, h, {count + 1, nlist, olist})

  defp delete_and_count([h | r], element, {count, nlist, olist}),
    do: delete_and_count(r, element, {count, [h | nlist], olist})

  defp insert_if_needed(list, oldcount, element) do
    if oldcount <= 0 || Enum.member?(list, element) do
      list
    else
      [element | list]
    end
  end

  defp check_delist(message, actions) do
    if :delist in actions do
      with %User{} = user <- User.get_cached_by_ap_id(message["actor"]) do
        {pubcnt, to} = delete_and_count(message["to"] || [], Pleroma.Constants.as_public())
        {flwcnt, cc} = delete_and_count(message["cc"] || [], user.follower_address)

        cc = insert_if_needed(cc, pubcnt, Pleroma.Constants.as_public())
        to = insert_if_needed(to, flwcnt, user.follower_address)

        message =
          message
          |> Map.put("to", to)
          |> Map.put("cc", cc)
          |> Kernel.put_in(["object", "to"], to)
          |> Kernel.put_in(["object", "cc"], cc)

        {:ok, message}
      else
        _e ->
          {:reject, "[ObjectAgePolicy] Unhandled error"}
      end
    else
      {:ok, message}
    end
  end

  defp check_strip_followers(message, actions) do
    if :strip_followers in actions do
      with %User{} = user <- User.get_cached_by_ap_id(message["actor"]) do
        {_, to} = delete_and_count(message["to"] || [], user.follower_address)
        {_, cc} = delete_and_count(message["cc"] || [], user.follower_address)

        message =
          message
          |> Map.put("to", to)
          |> Map.put("cc", cc)
          |> Kernel.put_in(["object", "to"], to)
          |> Kernel.put_in(["object", "cc"], cc)

        {:ok, message}
      else
        _e ->
          {:reject, "[ObjectAgePolicy] Unhandled error"}
      end
    else
      {:ok, message}
    end
  end

  @impl true
  def filter(%{"type" => "Create", "object" => %{"published" => _}} = message) do
    with actions <- Config.get([:mrf_object_age, :actions]),
         {:reject, _} <- check_date(message),
         {:ok, message} <- check_reject(message, actions),
         {:ok, message} <- check_delist(message, actions),
         {:ok, message} <- check_strip_followers(message, actions) do
      {:ok, message}
    else
      # check_date() is allowed to short-circuit the pipeline
      e -> e
    end
  end

  @impl true
  def filter(message), do: {:ok, message}

  @impl true
  def describe do
    mrf_object_age =
      Config.get(:mrf_object_age)
      |> Enum.into(%{})

    {:ok, %{mrf_object_age: mrf_object_age}}
  end

  @impl true
  def config_description do
    %{
      key: :mrf_object_age,
      related_policy: "Pleroma.Web.ActivityPub.MRF.ObjectAgePolicy",
      label: "MRF Object Age",
      description:
        "Rejects or delists posts based on their timestamp deviance from your server's clock.",
      children: [
        %{
          key: :threshold,
          type: :integer,
          description: "Required age (in seconds) of a post before actions are taken.",
          suggestions: [172_800]
        },
        %{
          key: :actions,
          type: {:list, :atom},
          description:
            "A list of actions to apply to the post. `:delist` removes the post from public timelines; " <>
              "`:strip_followers` removes followers from the ActivityPub recipient list ensuring they won't be delivered to home timelines; " <>
              "`:reject` rejects the message entirely",
          suggestions: [:delist, :strip_followers, :reject]
        }
      ]
    }
  end
end
