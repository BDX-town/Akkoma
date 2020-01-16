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

  @type t() :: %__MODULE__{}

  schema "objects" do
    field(:data, :map)

    timestamps()
  end

  def with_joined_activity(query, activity_type \\ "Create", join_type \\ :inner) do
    object_position = Map.get(query.aliases, :object, 0)

    join(query, join_type, [{object, object_position}], a in Activity,
      on:
        fragment(
          "COALESCE(?->'object'->>'id', ?->>'object') = (? ->> 'id') AND (?->>'type' = ?) ",
          a.data,
          a.data,
          object.data,
          a.data,
          ^activity_type
        ),
      as: :object_activity
    )
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

  def get_by_id_and_maybe_refetch(id, opts \\ []) do
    %{updated_at: updated_at} = object = get_by_id(id)

    if opts[:interval] &&
         NaiveDateTime.diff(NaiveDateTime.utc_now(), updated_at) > opts[:interval] do
      case Fetcher.refetch_object(object) do
        {:ok, %Object{} = object} ->
          object

        e ->
          Logger.error("Couldn't refresh #{object.data["id"]}:\n#{inspect(e)}")
          object
      end
    else
      object
    end
  end

  def get_by_ap_id(nil), do: nil

  def get_by_ap_id(ap_id) do
    Repo.one(from(object in Object, where: fragment("(?)->>'id' = ?", object.data, ^ap_id)))
  end

  @doc """
  Get a single attachment by it's name and href
  """
  @spec get_attachment_by_name_and_href(String.t(), String.t()) :: Object.t() | nil
  def get_attachment_by_name_and_href(name, href) do
    query =
      from(o in Object,
        where: fragment("(?)->>'name' = ?", o.data, ^name),
        where: fragment("(?)->>'href' = ?", o.data, ^href)
      )

    Repo.one(query)
  end

  defp warn_on_no_object_preloaded(ap_id) do
    "Object.normalize() called without preloaded object (#{inspect(ap_id)}). Consider preloading the object"
    |> Logger.debug()

    Logger.debug("Backtrace: #{inspect(Process.info(:erlang.self(), :current_stacktrace))}")
  end

  def normalize(_, fetch_remote \\ true, options \\ [])

  # If we pass an Activity to Object.normalize(), we can try to use the preloaded object.
  # Use this whenever possible, especially when walking graphs in an O(N) loop!
  def normalize(%Object{} = object, _, _), do: object
  def normalize(%Activity{object: %Object{} = object}, _, _), do: object

  # A hack for fake activities
  def normalize(%Activity{data: %{"object" => %{"fake" => true} = data}}, _, _) do
    %Object{id: "pleroma:fake_object_id", data: data}
  end

  # No preloaded object
  def normalize(%Activity{data: %{"object" => %{"id" => ap_id}}}, fetch_remote, _) do
    warn_on_no_object_preloaded(ap_id)
    normalize(ap_id, fetch_remote)
  end

  # No preloaded object
  def normalize(%Activity{data: %{"object" => ap_id}}, fetch_remote, _) do
    warn_on_no_object_preloaded(ap_id)
    normalize(ap_id, fetch_remote)
  end

  # Old way, try fetching the object through cache.
  def normalize(%{"id" => ap_id}, fetch_remote, _), do: normalize(ap_id, fetch_remote)
  def normalize(ap_id, false, _) when is_binary(ap_id), do: get_cached_by_ap_id(ap_id)

  def normalize(ap_id, true, options) when is_binary(ap_id) do
    Fetcher.fetch_object_from_id!(ap_id, options)
  end

  def normalize(_, _, _), do: nil

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
         :ok <- delete_attachments(object),
         deleted_activity = Activity.delete_all_by_object_ap_id(id),
         {:ok, true} <- Cachex.del(:object_cache, "object:#{id}"),
         {:ok, _} <- Cachex.del(:web_resp_cache, URI.parse(id).path) do
      {:ok, object, deleted_activity}
    end
  end

  defp delete_attachments(%{data: %{"attachment" => [_ | _] = attachments, "actor" => actor}}) do
    hrefs =
      Enum.flat_map(attachments, fn attachment ->
        Enum.map(attachment["url"], & &1["href"])
      end)

    names = Enum.map(attachments, & &1["name"])

    uploader = Pleroma.Config.get([Pleroma.Upload, :uploader])

    # find all objects for copies of the attachments, name and actor doesn't matter here
    delete_ids =
      from(o in Object,
        where:
          fragment(
            "to_jsonb(array(select jsonb_array_elements((?)#>'{url}') ->> 'href'))::jsonb \\?| (?)",
            o.data,
            ^hrefs
          )
      )
      |> Repo.all()
      # we should delete 1 object for any given attachment, but don't delete files if
      # there are more than 1 object for it
      |> Enum.reduce(%{}, fn %{
                               id: id,
                               data: %{
                                 "url" => [%{"href" => href}],
                                 "actor" => obj_actor,
                                 "name" => name
                               }
                             },
                             acc ->
        Map.update(acc, href, %{id: id, count: 1}, fn val ->
          case obj_actor == actor and name in names do
            true ->
              # set id of the actor's object that will be deleted
              %{val | id: id, count: val.count + 1}

            false ->
              # another actor's object, just increase count to not delete file
              %{val | count: val.count + 1}
          end
        end)
      end)
      |> Enum.map(fn {href, %{id: id, count: count}} ->
        # only delete files that have single instance
        with 1 <- count do
          prefix =
            case Pleroma.Config.get([Pleroma.Upload, :base_url]) do
              nil -> "media"
              _ -> ""
            end

          base_url = Pleroma.Config.get([__MODULE__, :base_url], Pleroma.Web.base_url())

          file_path = String.trim_leading(href, "#{base_url}/#{prefix}")

          uploader.delete_file(file_path)
        end

        id
      end)

    from(o in Object, where: o.id in ^delete_ids)
    |> Repo.delete_all()

    :ok
  end

  defp delete_attachments(%{data: _data}), do: :ok

  def prune(%Object{data: %{"id" => id}} = object) do
    with {:ok, object} <- Repo.delete(object),
         {:ok, true} <- Cachex.del(:object_cache, "object:#{id}"),
         {:ok, _} <- Cachex.del(:web_resp_cache, URI.parse(id).path) do
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
            safe_jsonb_set(?, '{repliesCount}',
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
            safe_jsonb_set(?, '{repliesCount}',
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

  @doc "Updates data field of an object"
  def update_data(%Object{data: data} = object, attrs \\ %{}) do
    object
    |> Object.change(%{data: Map.merge(data || %{}, attrs)})
    |> Repo.update()
  end

  def local?(%Object{data: %{"id" => id}}) do
    String.starts_with?(id, Pleroma.Web.base_url() <> "/")
  end
end
