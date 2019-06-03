# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Utils do
  alias Ecto.Changeset
  alias Ecto.UUID
  alias Pleroma.Activity
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.Router.Helpers

  import Ecto.Query

  require Logger

  @supported_object_types ["Article", "Note", "Video", "Page", "Question", "Answer"]
  @supported_report_states ~w(open closed resolved)
  @valid_visibilities ~w(public unlisted private direct)

  # Some implementations send the actor URI as the actor field, others send the entire actor object,
  # so figure out what the actor's URI is based on what we have.
  def get_ap_id(object) do
    case object do
      %{"id" => id} -> id
      id -> id
    end
  end

  def normalize_params(params) do
    Map.put(params, "actor", get_ap_id(params["actor"]))
  end

  def determine_explicit_mentions(%{"tag" => tag} = _object) when is_list(tag) do
    tag
    |> Enum.filter(fn x -> is_map(x) end)
    |> Enum.filter(fn x -> x["type"] == "Mention" end)
    |> Enum.map(fn x -> x["href"] end)
  end

  def determine_explicit_mentions(%{"tag" => tag} = object) when is_map(tag) do
    Map.put(object, "tag", [tag])
    |> determine_explicit_mentions()
  end

  def determine_explicit_mentions(_), do: []

  defp recipient_in_collection(ap_id, coll) when is_binary(coll), do: ap_id == coll
  defp recipient_in_collection(ap_id, coll) when is_list(coll), do: ap_id in coll
  defp recipient_in_collection(_, _), do: false

  def recipient_in_message(%User{ap_id: ap_id} = recipient, %User{} = actor, params) do
    cond do
      recipient_in_collection(ap_id, params["to"]) ->
        true

      recipient_in_collection(ap_id, params["cc"]) ->
        true

      recipient_in_collection(ap_id, params["bto"]) ->
        true

      recipient_in_collection(ap_id, params["bcc"]) ->
        true

      # if the message is unaddressed at all, then assume it is directly addressed
      # to the recipient
      !params["to"] && !params["cc"] && !params["bto"] && !params["bcc"] ->
        true

      # if the message is sent from somebody the user is following, then assume it
      # is addressed to the recipient
      User.following?(recipient, actor) ->
        true

      true ->
        false
    end
  end

  defp extract_list(target) when is_binary(target), do: [target]
  defp extract_list(lst) when is_list(lst), do: lst
  defp extract_list(_), do: []

  def maybe_splice_recipient(ap_id, params) do
    need_splice =
      !recipient_in_collection(ap_id, params["to"]) &&
        !recipient_in_collection(ap_id, params["cc"])

    cc_list = extract_list(params["cc"])

    if need_splice do
      params
      |> Map.put("cc", [ap_id | cc_list])
    else
      params
    end
  end

  def make_json_ld_header do
    %{
      "@context" => [
        "https://www.w3.org/ns/activitystreams",
        "#{Web.base_url()}/schemas/litepub-0.1.jsonld",
        %{
          "@language" => "und"
        }
      ]
    }
  end

  def make_date do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  def generate_activity_id do
    generate_id("activities")
  end

  def generate_context_id do
    generate_id("contexts")
  end

  def generate_object_id do
    Helpers.o_status_url(Endpoint, :object, UUID.generate())
  end

  def generate_id(type) do
    "#{Web.base_url()}/#{type}/#{UUID.generate()}"
  end

  def get_notified_from_object(%{"type" => type} = object) when type in @supported_object_types do
    fake_create_activity = %{
      "to" => object["to"],
      "cc" => object["cc"],
      "type" => "Create",
      "object" => object
    }

    Notification.get_notified_from_activity(%Activity{data: fake_create_activity}, false)
  end

  def get_notified_from_object(object) do
    Notification.get_notified_from_activity(%Activity{data: object}, false)
  end

  def create_context(context) do
    context = context || generate_id("contexts")
    changeset = Object.context_mapping(context)

    case Repo.insert(changeset) do
      {:ok, object} ->
        object

      # This should be solved by an upsert, but it seems ecto
      # has problems accessing the constraint inside the jsonb.
      {:error, _} ->
        Object.get_cached_by_ap_id(context)
    end
  end

  @doc """
  Enqueues an activity for federation if it's local
  """
  def maybe_federate(%Activity{local: true} = activity) do
    priority =
      case activity.data["type"] do
        "Delete" -> 10
        "Create" -> 1
        _ -> 5
      end

    Pleroma.Web.Federator.publish(activity, priority)
    :ok
  end

  def maybe_federate(_), do: :ok

  @doc """
  Adds an id and a published data if they aren't there,
  also adds it to an included object
  """
  def lazy_put_activity_defaults(map, fake \\ false) do
    map =
      unless fake do
        %{data: %{"id" => context}, id: context_id} = create_context(map["context"])

        map
        |> Map.put_new_lazy("id", &generate_activity_id/0)
        |> Map.put_new_lazy("published", &make_date/0)
        |> Map.put_new("context", context)
        |> Map.put_new("context_id", context_id)
      else
        map
        |> Map.put_new("id", "pleroma:fakeid")
        |> Map.put_new_lazy("published", &make_date/0)
        |> Map.put_new("context", "pleroma:fakecontext")
        |> Map.put_new("context_id", -1)
      end

    if is_map(map["object"]) do
      object = lazy_put_object_defaults(map["object"], map, fake)
      %{map | "object" => object}
    else
      map
    end
  end

  @doc """
  Adds an id and published date if they aren't there.
  """
  def lazy_put_object_defaults(map, activity \\ %{}, fake)

  def lazy_put_object_defaults(map, activity, true = _fake) do
    map
    |> Map.put_new_lazy("published", &make_date/0)
    |> Map.put_new("id", "pleroma:fake_object_id")
    |> Map.put_new("context", activity["context"])
    |> Map.put_new("fake", true)
    |> Map.put_new("context_id", activity["context_id"])
  end

  def lazy_put_object_defaults(map, activity, _fake) do
    map
    |> Map.put_new_lazy("id", &generate_object_id/0)
    |> Map.put_new_lazy("published", &make_date/0)
    |> Map.put_new("context", activity["context"])
    |> Map.put_new("context_id", activity["context_id"])
  end

  @doc """
  Inserts a full object if it is contained in an activity.
  """
  def insert_full_object(%{"object" => %{"type" => type} = object_data} = map)
      when is_map(object_data) and type in @supported_object_types do
    with {:ok, object} <- Object.create(object_data) do
      map =
        map
        |> Map.put("object", object.data["id"])

      {:ok, map, object}
    end
  end

  def insert_full_object(map), do: {:ok, map, nil}

  def update_object_in_activities(%{data: %{"id" => id}} = object) do
    # TODO
    # Update activities that already had this. Could be done in a seperate process.
    # Alternatively, just don't do this and fetch the current object each time. Most
    # could probably be taken from cache.
    relevant_activities = Activity.get_all_create_by_object_ap_id(id)

    Enum.map(relevant_activities, fn activity ->
      new_activity_data = activity.data |> Map.put("object", object.data)
      changeset = Changeset.change(activity, data: new_activity_data)
      Repo.update(changeset)
    end)
  end

  #### Like-related helpers

  @doc """
  Returns an existing like if a user already liked an object
  """
  def get_existing_like(actor, %{data: %{"id" => id}}) do
    query =
      from(
        activity in Activity,
        where: fragment("(?)->>'actor' = ?", activity.data, ^actor),
        # this is to use the index
        where:
          fragment(
            "coalesce((?)->'object'->>'id', (?)->>'object') = ?",
            activity.data,
            activity.data,
            ^id
          ),
        where: fragment("(?)->>'type' = 'Like'", activity.data)
      )

    Repo.one(query)
  end

  @doc """
  Returns like activities targeting an object
  """
  def get_object_likes(%{data: %{"id" => id}}) do
    query =
      from(
        activity in Activity,
        # this is to use the index
        where:
          fragment(
            "coalesce((?)->'object'->>'id', (?)->>'object') = ?",
            activity.data,
            activity.data,
            ^id
          ),
        where: fragment("(?)->>'type' = 'Like'", activity.data)
      )

    Repo.all(query)
  end

  def make_like_data(
        %User{ap_id: ap_id} = actor,
        %{data: %{"actor" => object_actor_id, "id" => id}} = object,
        activity_id
      ) do
    object_actor = User.get_cached_by_ap_id(object_actor_id)

    to =
      if Visibility.is_public?(object) do
        [actor.follower_address, object.data["actor"]]
      else
        [object.data["actor"]]
      end

    cc =
      (object.data["to"] ++ (object.data["cc"] || []))
      |> List.delete(actor.ap_id)
      |> List.delete(object_actor.follower_address)

    data = %{
      "type" => "Like",
      "actor" => ap_id,
      "object" => id,
      "to" => to,
      "cc" => cc,
      "context" => object.data["context"]
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  def update_element_in_object(property, element, object) do
    with new_data <-
           object.data
           |> Map.put("#{property}_count", length(element))
           |> Map.put("#{property}s", element),
         changeset <- Changeset.change(object, data: new_data),
         {:ok, object} <- Object.update_and_set_cache(changeset),
         _ <- update_object_in_activities(object) do
      {:ok, object}
    end
  end

  def update_likes_in_object(likes, object) do
    update_element_in_object("like", likes, object)
  end

  def add_like_to_object(%Activity{data: %{"actor" => actor}}, object) do
    likes = if is_list(object.data["likes"]), do: object.data["likes"], else: []

    with likes <- [actor | likes] |> Enum.uniq() do
      update_likes_in_object(likes, object)
    end
  end

  def remove_like_from_object(%Activity{data: %{"actor" => actor}}, object) do
    likes = if is_list(object.data["likes"]), do: object.data["likes"], else: []

    with likes <- likes |> List.delete(actor) do
      update_likes_in_object(likes, object)
    end
  end

  #### Follow-related helpers

  @doc """
  Updates a follow activity's state (for locked accounts).
  """
  def update_follow_state(
        %Activity{data: %{"actor" => actor, "object" => object, "state" => "pending"}} = activity,
        state
      ) do
    try do
      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE activities SET data = jsonb_set(data, '{state}', $1) WHERE data->>'type' = 'Follow' AND data->>'actor' = $2 AND data->>'object' = $3 AND data->>'state' = 'pending'",
        [state, actor, object]
      )

      activity = Activity.get_by_id(activity.id)
      {:ok, activity}
    rescue
      e ->
        {:error, e}
    end
  end

  def update_follow_state(%Activity{} = activity, state) do
    with new_data <-
           activity.data
           |> Map.put("state", state),
         changeset <- Changeset.change(activity, data: new_data),
         {:ok, activity} <- Repo.update(changeset) do
      {:ok, activity}
    end
  end

  @doc """
  Makes a follow activity data for the given follower and followed
  """
  def make_follow_data(
        %User{ap_id: follower_id},
        %User{ap_id: followed_id} = _followed,
        activity_id
      ) do
    data = %{
      "type" => "Follow",
      "actor" => follower_id,
      "to" => [followed_id],
      "cc" => ["https://www.w3.org/ns/activitystreams#Public"],
      "object" => followed_id,
      "state" => "pending"
    }

    data = if activity_id, do: Map.put(data, "id", activity_id), else: data

    data
  end

  def fetch_latest_follow(%User{ap_id: follower_id}, %User{ap_id: followed_id}) do
    query =
      from(
        activity in Activity,
        where:
          fragment(
            "? ->> 'type' = 'Follow'",
            activity.data
          ),
        where: activity.actor == ^follower_id,
        # this is to use the index
        where:
          fragment(
            "coalesce((?)->'object'->>'id', (?)->>'object') = ?",
            activity.data,
            activity.data,
            ^followed_id
          ),
        order_by: [fragment("? desc nulls last", activity.id)],
        limit: 1
      )

    Repo.one(query)
  end

  #### Announce-related helpers

  @doc """
  Retruns an existing announce activity if the notice has already been announced
  """
  def get_existing_announce(actor, %{data: %{"id" => id}}) do
    query =
      from(
        activity in Activity,
        where: activity.actor == ^actor,
        # this is to use the index
        where:
          fragment(
            "coalesce((?)->'object'->>'id', (?)->>'object') = ?",
            activity.data,
            activity.data,
            ^id
          ),
        where: fragment("(?)->>'type' = 'Announce'", activity.data)
      )

    Repo.one(query)
  end

  @doc """
  Make announce activity data for the given actor and object
  """
  # for relayed messages, we only want to send to subscribers
  def make_announce_data(
        %User{ap_id: ap_id} = user,
        %Object{data: %{"id" => id}} = object,
        activity_id,
        false
      ) do
    data = %{
      "type" => "Announce",
      "actor" => ap_id,
      "object" => id,
      "to" => [user.follower_address],
      "cc" => [],
      "context" => object.data["context"]
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  def make_announce_data(
        %User{ap_id: ap_id} = user,
        %Object{data: %{"id" => id}} = object,
        activity_id,
        true
      ) do
    data = %{
      "type" => "Announce",
      "actor" => ap_id,
      "object" => id,
      "to" => [user.follower_address, object.data["actor"]],
      "cc" => ["https://www.w3.org/ns/activitystreams#Public"],
      "context" => object.data["context"]
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  @doc """
  Make unannounce activity data for the given actor and object
  """
  def make_unannounce_data(
        %User{ap_id: ap_id} = user,
        %Activity{data: %{"context" => context}} = activity,
        activity_id
      ) do
    data = %{
      "type" => "Undo",
      "actor" => ap_id,
      "object" => activity.data,
      "to" => [user.follower_address, activity.data["actor"]],
      "cc" => ["https://www.w3.org/ns/activitystreams#Public"],
      "context" => context
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  def make_unlike_data(
        %User{ap_id: ap_id} = user,
        %Activity{data: %{"context" => context}} = activity,
        activity_id
      ) do
    data = %{
      "type" => "Undo",
      "actor" => ap_id,
      "object" => activity.data,
      "to" => [user.follower_address, activity.data["actor"]],
      "cc" => ["https://www.w3.org/ns/activitystreams#Public"],
      "context" => context
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  def add_announce_to_object(
        %Activity{
          data: %{"actor" => actor, "cc" => ["https://www.w3.org/ns/activitystreams#Public"]}
        },
        object
      ) do
    announcements =
      if is_list(object.data["announcements"]), do: object.data["announcements"], else: []

    with announcements <- [actor | announcements] |> Enum.uniq() do
      update_element_in_object("announcement", announcements, object)
    end
  end

  def add_announce_to_object(_, object), do: {:ok, object}

  def remove_announce_from_object(%Activity{data: %{"actor" => actor}}, object) do
    announcements =
      if is_list(object.data["announcements"]), do: object.data["announcements"], else: []

    with announcements <- announcements |> List.delete(actor) do
      update_element_in_object("announcement", announcements, object)
    end
  end

  #### Unfollow-related helpers

  def make_unfollow_data(follower, followed, follow_activity, activity_id) do
    data = %{
      "type" => "Undo",
      "actor" => follower.ap_id,
      "to" => [followed.ap_id],
      "object" => follow_activity.data
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  #### Block-related helpers
  def fetch_latest_block(%User{ap_id: blocker_id}, %User{ap_id: blocked_id}) do
    query =
      from(
        activity in Activity,
        where:
          fragment(
            "? ->> 'type' = 'Block'",
            activity.data
          ),
        where: activity.actor == ^blocker_id,
        # this is to use the index
        where:
          fragment(
            "coalesce((?)->'object'->>'id', (?)->>'object') = ?",
            activity.data,
            activity.data,
            ^blocked_id
          ),
        order_by: [fragment("? desc nulls last", activity.id)],
        limit: 1
      )

    Repo.one(query)
  end

  def make_block_data(blocker, blocked, activity_id) do
    data = %{
      "type" => "Block",
      "actor" => blocker.ap_id,
      "to" => [blocked.ap_id],
      "object" => blocked.ap_id
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  def make_unblock_data(blocker, blocked, block_activity, activity_id) do
    data = %{
      "type" => "Undo",
      "actor" => blocker.ap_id,
      "to" => [blocked.ap_id],
      "object" => block_activity.data
    }

    if activity_id, do: Map.put(data, "id", activity_id), else: data
  end

  #### Create-related helpers

  def make_create_data(params, additional) do
    published = params.published || make_date()

    %{
      "type" => "Create",
      "to" => params.to |> Enum.uniq(),
      "actor" => params.actor.ap_id,
      "object" => params.object,
      "published" => published,
      "context" => params.context
    }
    |> Map.merge(additional)
  end

  #### Flag-related helpers

  def make_flag_data(params, additional) do
    status_ap_ids =
      Enum.map(params.statuses || [], fn
        %Activity{} = act -> act.data["id"]
        act when is_map(act) -> act["id"]
        act when is_binary(act) -> act
      end)

    object = [params.account.ap_id] ++ status_ap_ids

    %{
      "type" => "Flag",
      "actor" => params.actor.ap_id,
      "content" => params.content,
      "object" => object,
      "context" => params.context,
      "state" => "open"
    }
    |> Map.merge(additional)
  end

  @doc """
  Fetches the OrderedCollection/OrderedCollectionPage from `from`, limiting the amount of pages fetched after
  the first one to `pages_left` pages.
  If the amount of pages is higher than the collection has, it returns whatever was there.
  """
  def fetch_ordered_collection(from, pages_left, acc \\ []) do
    with {:ok, response} <- Tesla.get(from),
         {:ok, collection} <- Jason.decode(response.body) do
      case collection["type"] do
        "OrderedCollection" ->
          # If we've encountered the OrderedCollection and not the page,
          # just call the same function on the page address
          fetch_ordered_collection(collection["first"], pages_left)

        "OrderedCollectionPage" ->
          if pages_left > 0 do
            # There are still more pages
            if Map.has_key?(collection, "next") do
              # There are still more pages, go deeper saving what we have into the accumulator
              fetch_ordered_collection(
                collection["next"],
                pages_left - 1,
                acc ++ collection["orderedItems"]
              )
            else
              # No more pages left, just return whatever we already have
              acc ++ collection["orderedItems"]
            end
          else
            # Got the amount of pages needed, add them all to the accumulator
            acc ++ collection["orderedItems"]
          end

        _ ->
          {:error, "Not an OrderedCollection or OrderedCollectionPage"}
      end
    end
  end

  #### Report-related helpers

  def update_report_state(%Activity{} = activity, state) when state in @supported_report_states do
    with new_data <- Map.put(activity.data, "state", state),
         changeset <- Changeset.change(activity, data: new_data),
         {:ok, activity} <- Repo.update(changeset) do
      {:ok, activity}
    end
  end

  def update_report_state(_, _), do: {:error, "Unsupported state"}

  def update_activity_visibility(activity, visibility) when visibility in @valid_visibilities do
    [to, cc, recipients] =
      activity
      |> get_updated_targets(visibility)
      |> Enum.map(&Enum.uniq/1)

    object_data =
      activity.object.data
      |> Map.put("to", to)
      |> Map.put("cc", cc)

    {:ok, object} =
      activity.object
      |> Object.change(%{data: object_data})
      |> Object.update_and_set_cache()

    activity_data =
      activity.data
      |> Map.put("to", to)
      |> Map.put("cc", cc)

    activity
    |> Map.put(:object, object)
    |> Activity.change(%{data: activity_data, recipients: recipients})
    |> Repo.update()
  end

  def update_activity_visibility(_, _), do: {:error, "Unsupported visibility"}

  defp get_updated_targets(
         %Activity{data: %{"to" => to} = data, recipients: recipients},
         visibility
       ) do
    cc = Map.get(data, "cc", [])
    follower_address = User.get_cached_by_ap_id(data["actor"]).follower_address
    public = "https://www.w3.org/ns/activitystreams#Public"

    case visibility do
      "public" ->
        to = [public | List.delete(to, follower_address)]
        cc = [follower_address | List.delete(cc, public)]
        recipients = [public | recipients]
        [to, cc, recipients]

      "private" ->
        to = [follower_address | List.delete(to, public)]
        cc = List.delete(cc, public)
        recipients = List.delete(recipients, public)
        [to, cc, recipients]

      "unlisted" ->
        to = [follower_address | List.delete(to, public)]
        cc = [public | List.delete(cc, follower_address)]
        recipients = recipients ++ [follower_address, public]
        [to, cc, recipients]

      _ ->
        [to, cc, recipients]
    end
  end

  def get_existing_votes(actor, %{data: %{"id" => id}}) do
    query =
      from(
        [activity, object: object] in Activity.with_preloaded_object(Activity),
        where: fragment("(?)->>'actor' = ?", activity.data, ^actor),
        where:
          fragment(
            "(?)->'inReplyTo' = ?",
            object.data,
            ^to_string(id)
          ),
        where: fragment("(?)->>'type' = 'Answer'", object.data)
      )

    Repo.all(query)
  end
end
