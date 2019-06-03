# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Object do
  use Ecto.Schema

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Object.Fetcher
  alias Pleroma.ObjectTombstone
  alias Pleroma.Repo
  alias Pleroma.User

  import Ecto.Query
  import Ecto.Changeset

  require Logger

  schema "objects" do
    field(:data, :map)

    timestamps()
  end

  def create(data) do
    Object.change(%Object{}, %{data: data})
    |> Repo.insert()
  end

  def change(struct, params \\ %{}) do
    struct
    |> cast(params, [:data])
    |> validate_required([:data])
    |> unique_constraint(:ap_id, name: :objects_unique_apid_index)
  end

  def get_by_id(nil), do: nil
  def get_by_id(id), do: Repo.get(Object, id)

  def get_by_ap_id(nil), do: nil

  def get_by_ap_id(ap_id) do
    Repo.one(from(object in Object, where: fragment("(?)->>'id' = ?", object.data, ^ap_id)))
  end

  def normalize(_, fetch_remote \\ true)
  # If we pass an Activity to Object.normalize(), we can try to use the preloaded object.
  # Use this whenever possible, especially when walking graphs in an O(N) loop!
  def normalize(%Object{} = object, _), do: object
  def normalize(%Activity{object: %Object{} = object}, _), do: object

  # A hack for fake activities
  def normalize(%Activity{data: %{"object" => %{"fake" => true} = data}}, _) do
    %Object{id: "pleroma:fake_object_id", data: data}
  end

  # Catch and log Object.normalize() calls where the Activity's child object is not
  # preloaded.
  def normalize(%Activity{data: %{"object" => %{"id" => ap_id}}}, fetch_remote) do
    Logger.debug(
      "Object.normalize() called without preloaded object (#{ap_id}).  Consider preloading the object!"
    )

    Logger.debug("Backtrace: #{inspect(Process.info(:erlang.self(), :current_stacktrace))}")

    normalize(ap_id, fetch_remote)
  end

  def normalize(%Activity{data: %{"object" => ap_id}}, fetch_remote) do
    Logger.debug(
      "Object.normalize() called without preloaded object (#{ap_id}).  Consider preloading the object!"
    )

    Logger.debug("Backtrace: #{inspect(Process.info(:erlang.self(), :current_stacktrace))}")

    normalize(ap_id, fetch_remote)
  end

  # Old way, try fetching the object through cache.
  def normalize(%{"id" => ap_id}, fetch_remote), do: normalize(ap_id, fetch_remote)
  def normalize(ap_id, false) when is_binary(ap_id), do: get_cached_by_ap_id(ap_id)
  def normalize(ap_id, true) when is_binary(ap_id), do: Fetcher.fetch_object_from_id!(ap_id)
  def normalize(_, _), do: nil

  # Owned objects can only be mutated by their owner
  def authorize_mutation(%Object{data: %{"actor" => actor}}, %User{ap_id: ap_id}),
    do: actor == ap_id

  # Legacy objects can be mutated by anybody
  def authorize_mutation(%Object{}, %User{}), do: true

  def get_cached_by_ap_id(ap_id) do
    key = "object:#{ap_id}"

    Cachex.fetch!(:object_cache, key, fn _ ->
      object = get_by_ap_id(ap_id)

      if object do
        {:commit, object}
      else
        {:ignore, object}
      end
    end)
  end

  def context_mapping(context) do
    Object.change(%Object{}, %{data: %{"id" => context}})
  end

  def make_tombstone(%Object{data: %{"id" => id, "type" => type}}, deleted \\ DateTime.utc_now()) do
    %ObjectTombstone{
      id: id,
      formerType: type,
      deleted: deleted
    }
    |> Map.from_struct()
  end

  def swap_object_with_tombstone(object) do
    tombstone = make_tombstone(object)

    object
    |> Object.change(%{data: tombstone})
    |> Repo.update()
  end

  def delete(%Object{data: %{"id" => id}} = object) do
    with {:ok, _obj} = swap_object_with_tombstone(object),
         deleted_activity = Activity.delete_by_ap_id(id),
         {:ok, true} <- Cachex.del(:object_cache, "object:#{id}") do
      {:ok, object, deleted_activity}
    end
  end

  def prune(%Object{data: %{"id" => id}} = object) do
    with {:ok, object} <- Repo.delete(object),
         {:ok, true} <- Cachex.del(:object_cache, "object:#{id}") do
      {:ok, object}
    end
  end

  def set_cache(%Object{data: %{"id" => ap_id}} = object) do
    Cachex.put(:object_cache, "object:#{ap_id}", object)
    {:ok, object}
  end

  def update_and_set_cache(changeset) do
    with {:ok, object} <- Repo.update(changeset) do
      set_cache(object)
    else
      e -> e
    end
  end

  def increase_replies_count(ap_id) do
    Object
    |> where([o], fragment("?->>'id' = ?::text", o.data, ^to_string(ap_id)))
    |> update([o],
      set: [
        data:
          fragment(
            """
            jsonb_set(?, '{repliesCount}',
              (coalesce((?->>'repliesCount')::int, 0) + 1)::varchar::jsonb, true)
            """,
            o.data,
            o.data
          )
      ]
    )
    |> Repo.update_all([])
    |> case do
      {1, [object]} -> set_cache(object)
      _ -> {:error, "Not found"}
    end
  end

  def decrease_replies_count(ap_id) do
    Object
    |> where([o], fragment("?->>'id' = ?::text", o.data, ^to_string(ap_id)))
    |> update([o],
      set: [
        data:
          fragment(
            """
            jsonb_set(?, '{repliesCount}',
              (greatest(0, (?->>'repliesCount')::int - 1))::varchar::jsonb, true)
            """,
            o.data,
            o.data
          )
      ]
    )
    |> Repo.update_all([])
    |> case do
      {1, [object]} -> set_cache(object)
      _ -> {:error, "Not found"}
    end
  end

  def increase_vote_count(ap_id, name) do
    with %Object{} = object <- Object.normalize(ap_id),
         "Question" <- object.data["type"] do
      multiple = Map.has_key?(object.data, "anyOf")

      options =
        (object.data["anyOf"] || object.data["oneOf"] || [])
        |> Enum.map(fn
          %{"name" => ^name} = option ->
            Kernel.update_in(option["replies"]["totalItems"], &(&1 + 1))

          option ->
            option
        end)

      data =
        if multiple do
          Map.put(object.data, "anyOf", options)
        else
          Map.put(object.data, "oneOf", options)
        end

      object
      |> Object.change(%{data: data})
      |> update_and_set_cache()
    else
      _ -> :noop
    end
  end
end
