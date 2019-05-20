# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier do
  @moduledoc """
  A module to handle coding from internal to wire ActivityPub and back.
  """
  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.ActivityPub.Visibility

  import Ecto.Query

  require Logger

  @doc """
  Modifies an incoming AP object (mastodon format) to our internal format.
  """
  def fix_object(object) do
    object
    |> fix_actor
    |> fix_url
    |> fix_attachments
    |> fix_context
    |> fix_in_reply_to
    |> fix_emoji
    |> fix_tag
    |> fix_content_map
    |> fix_likes
    |> fix_addressing
    |> fix_summary
  end

  def fix_summary(%{"summary" => nil} = object) do
    object
    |> Map.put("summary", "")
  end

  def fix_summary(%{"summary" => _} = object) do
    # summary is present, nothing to do
    object
  end

  def fix_summary(object) do
    object
    |> Map.put("summary", "")
  end

  def fix_addressing_list(map, field) do
    cond do
      is_binary(map[field]) ->
        Map.put(map, field, [map[field]])

      is_nil(map[field]) ->
        Map.put(map, field, [])

      true ->
        map
    end
  end

  def fix_explicit_addressing(%{"to" => to, "cc" => cc} = object, explicit_mentions) do
    explicit_to =
      to
      |> Enum.filter(fn x -> x in explicit_mentions end)

    explicit_cc =
      to
      |> Enum.filter(fn x -> x not in explicit_mentions end)

    final_cc =
      (cc ++ explicit_cc)
      |> Enum.uniq()

    object
    |> Map.put("to", explicit_to)
    |> Map.put("cc", final_cc)
  end

  def fix_explicit_addressing(object, _explicit_mentions), do: object

  # if directMessage flag is set to true, leave the addressing alone
  def fix_explicit_addressing(%{"directMessage" => true} = object), do: object

  def fix_explicit_addressing(object) do
    explicit_mentions =
      object
      |> Utils.determine_explicit_mentions()

    explicit_mentions = explicit_mentions ++ ["https://www.w3.org/ns/activitystreams#Public"]

    object
    |> fix_explicit_addressing(explicit_mentions)
  end

  # if as:Public is addressed, then make sure the followers collection is also addressed
  # so that the activities will be delivered to local users.
  def fix_implicit_addressing(%{"to" => to, "cc" => cc} = object, followers_collection) do
    recipients = to ++ cc

    if followers_collection not in recipients do
      cond do
        "https://www.w3.org/ns/activitystreams#Public" in cc ->
          to = to ++ [followers_collection]
          Map.put(object, "to", to)

        "https://www.w3.org/ns/activitystreams#Public" in to ->
          cc = cc ++ [followers_collection]
          Map.put(object, "cc", cc)

        true ->
          object
      end
    else
      object
    end
  end

  def fix_implicit_addressing(object, _), do: object

  def fix_addressing(object) do
    {:ok, %User{} = user} = User.get_or_fetch_by_ap_id(object["actor"])
    followers_collection = User.ap_followers(user)

    object
    |> fix_addressing_list("to")
    |> fix_addressing_list("cc")
    |> fix_addressing_list("bto")
    |> fix_addressing_list("bcc")
    |> fix_explicit_addressing
    |> fix_implicit_addressing(followers_collection)
  end

  def fix_actor(%{"attributedTo" => actor} = object) do
    object
    |> Map.put("actor", Containment.get_actor(%{"actor" => actor}))
  end

  # Check for standardisation
  # This is what Peertube does
  # curl -H 'Accept: application/activity+json' $likes | jq .totalItems
  # Prismo returns only an integer (count) as "likes"
  def fix_likes(%{"likes" => likes} = object) when not is_map(likes) do
    object
    |> Map.put("likes", [])
    |> Map.put("like_count", 0)
  end

  def fix_likes(object) do
    object
  end

  def fix_in_reply_to(%{"inReplyTo" => in_reply_to} = object)
      when not is_nil(in_reply_to) do
    in_reply_to_id =
      cond do
        is_bitstring(in_reply_to) ->
          in_reply_to

        is_map(in_reply_to) && is_bitstring(in_reply_to["id"]) ->
          in_reply_to["id"]

        is_list(in_reply_to) && is_bitstring(Enum.at(in_reply_to, 0)) ->
          Enum.at(in_reply_to, 0)

        # Maybe I should output an error too?
        true ->
          ""
      end

    case get_obj_helper(in_reply_to_id) do
      {:ok, replied_object} ->
        with %Activity{} = _activity <-
               Activity.get_create_by_object_ap_id(replied_object.data["id"]) do
          object
          |> Map.put("inReplyTo", replied_object.data["id"])
          |> Map.put("inReplyToAtomUri", object["inReplyToAtomUri"] || in_reply_to_id)
          |> Map.put("conversation", replied_object.data["context"] || object["conversation"])
          |> Map.put("context", replied_object.data["context"] || object["conversation"])
        else
          e ->
            Logger.error("Couldn't fetch \"#{inspect(in_reply_to_id)}\", error: #{inspect(e)}")
            object
        end

      e ->
        Logger.error("Couldn't fetch \"#{inspect(in_reply_to_id)}\", error: #{inspect(e)}")
        object
    end
  end

  def fix_in_reply_to(object), do: object

  def fix_context(object) do
    context = object["context"] || object["conversation"] || Utils.generate_context_id()

    object
    |> Map.put("context", context)
    |> Map.put("conversation", context)
  end

  def fix_attachments(%{"attachment" => attachment} = object) when is_list(attachment) do
    attachments =
      attachment
      |> Enum.map(fn data ->
        media_type = data["mediaType"] || data["mimeType"]
        href = data["url"] || data["href"]

        url = [%{"type" => "Link", "mediaType" => media_type, "href" => href}]

        data
        |> Map.put("mediaType", media_type)
        |> Map.put("url", url)
      end)

    object
    |> Map.put("attachment", attachments)
  end

  def fix_attachments(%{"attachment" => attachment} = object) when is_map(attachment) do
    Map.put(object, "attachment", [attachment])
    |> fix_attachments()
  end

  def fix_attachments(object), do: object

  def fix_url(%{"url" => url} = object) when is_map(url) do
    object
    |> Map.put("url", url["href"])
  end

  def fix_url(%{"type" => "Video", "url" => url} = object) when is_list(url) do
    first_element = Enum.at(url, 0)

    link_element =
      url
      |> Enum.filter(fn x -> is_map(x) end)
      |> Enum.filter(fn x -> x["mimeType"] == "text/html" end)
      |> Enum.at(0)

    object
    |> Map.put("attachment", [first_element])
    |> Map.put("url", link_element["href"])
  end

  def fix_url(%{"type" => object_type, "url" => url} = object)
      when object_type != "Video" and is_list(url) do
    first_element = Enum.at(url, 0)

    url_string =
      cond do
        is_bitstring(first_element) -> first_element
        is_map(first_element) -> first_element["href"] || ""
        true -> ""
      end

    object
    |> Map.put("url", url_string)
  end

  def fix_url(object), do: object

  def fix_emoji(%{"tag" => tags} = object) when is_list(tags) do
    emoji = tags |> Enum.filter(fn data -> data["type"] == "Emoji" and data["icon"] end)

    emoji =
      emoji
      |> Enum.reduce(%{}, fn data, mapping ->
        name = String.trim(data["name"], ":")

        mapping |> Map.put(name, data["icon"]["url"])
      end)

    # we merge mastodon and pleroma emoji into a single mapping, to allow for both wire formats
    emoji = Map.merge(object["emoji"] || %{}, emoji)

    object
    |> Map.put("emoji", emoji)
  end

  def fix_emoji(%{"tag" => %{"type" => "Emoji"} = tag} = object) do
    name = String.trim(tag["name"], ":")
    emoji = %{name => tag["icon"]["url"]}

    object
    |> Map.put("emoji", emoji)
  end

  def fix_emoji(object), do: object

  def fix_tag(%{"tag" => tag} = object) when is_list(tag) do
    tags =
      tag
      |> Enum.filter(fn data -> data["type"] == "Hashtag" and data["name"] end)
      |> Enum.map(fn data -> String.slice(data["name"], 1..-1) end)

    combined = tag ++ tags

    object
    |> Map.put("tag", combined)
  end

  def fix_tag(%{"tag" => %{"type" => "Hashtag", "name" => hashtag} = tag} = object) do
    combined = [tag, String.slice(hashtag, 1..-1)]

    object
    |> Map.put("tag", combined)
  end

  def fix_tag(%{"tag" => %{} = tag} = object), do: Map.put(object, "tag", [tag])

  def fix_tag(object), do: object

  # content map usually only has one language so this will do for now.
  def fix_content_map(%{"contentMap" => content_map} = object) do
    content_groups = Map.to_list(content_map)
    {_, content} = Enum.at(content_groups, 0)

    object
    |> Map.put("content", content)
  end

  def fix_content_map(object), do: object

  defp mastodon_follow_hack(%{"id" => id, "actor" => follower_id}, followed) do
    with true <- id =~ "follows",
         %User{local: true} = follower <- User.get_cached_by_ap_id(follower_id),
         %Activity{} = activity <- Utils.fetch_latest_follow(follower, followed) do
      {:ok, activity}
    else
      _ -> {:error, nil}
    end
  end

  defp mastodon_follow_hack(_, _), do: {:error, nil}

  defp get_follow_activity(follow_object, followed) do
    with object_id when not is_nil(object_id) <- Utils.get_ap_id(follow_object),
         {_, %Activity{} = activity} <- {:activity, Activity.get_by_ap_id(object_id)} do
      {:ok, activity}
    else
      # Can't find the activity. This might a Mastodon 2.3 "Accept"
      {:activity, nil} ->
        mastodon_follow_hack(follow_object, followed)

      _ ->
        {:error, nil}
    end
  end

  # Flag objects are placed ahead of the ID check because Mastodon 2.8 and earlier send them
  # with nil ID.
  def handle_incoming(%{"type" => "Flag", "object" => objects, "actor" => actor} = data) do
    with context <- data["context"] || Utils.generate_context_id(),
         content <- data["content"] || "",
         %User{} = actor <- User.get_cached_by_ap_id(actor),

         # Reduce the object list to find the reported user.
         %User{} = account <-
           Enum.reduce_while(objects, nil, fn ap_id, _ ->
             with %User{} = user <- User.get_cached_by_ap_id(ap_id) do
               {:halt, user}
             else
               _ -> {:cont, nil}
             end
           end),

         # Remove the reported user from the object list.
         statuses <- Enum.filter(objects, fn ap_id -> ap_id != account.ap_id end) do
      params = %{
        actor: actor,
        context: context,
        account: account,
        statuses: statuses,
        content: content,
        additional: %{
          "cc" => [account.ap_id]
        }
      }

      ActivityPub.flag(params)
    end
  end

  # disallow objects with bogus IDs
  def handle_incoming(%{"id" => nil}), do: :error
  def handle_incoming(%{"id" => ""}), do: :error
  # length of https:// = 8, should validate better, but good enough for now.
  def handle_incoming(%{"id" => id}) when not (is_binary(id) and length(id) > 8), do: :error

  # TODO: validate those with a Ecto scheme
  # - tags
  # - emoji
  def handle_incoming(%{"type" => "Create", "object" => %{"type" => objtype} = object} = data)
      when objtype in ["Article", "Note", "Video", "Page"] do
    actor = Containment.get_actor(data)

    data =
      Map.put(data, "actor", actor)
      |> fix_addressing

    with nil <- Activity.get_create_by_object_ap_id(object["id"]),
         {:ok, %User{} = user} <- User.get_or_fetch_by_ap_id(data["actor"]) do
      object = fix_object(data["object"])

      params = %{
        to: data["to"],
        object: object,
        actor: user,
        context: object["conversation"],
        local: false,
        published: data["published"],
        additional:
          Map.take(data, [
            "cc",
            "directMessage",
            "id"
          ])
      }

      ActivityPub.create(params)
    else
      %Activity{} = activity -> {:ok, activity}
      _e -> :error
    end
  end

  def handle_incoming(
        %{"type" => "Follow", "object" => followed, "actor" => follower, "id" => id} = data
      ) do
    with %User{local: true} = followed <- User.get_cached_by_ap_id(followed),
         {:ok, %User{} = follower} <- User.get_or_fetch_by_ap_id(follower),
         {:ok, activity} <- ActivityPub.follow(follower, followed, id, false) do
      with deny_follow_blocked <- Pleroma.Config.get([:user, :deny_follow_blocked]),
           {:user_blocked, false} <-
             {:user_blocked, User.blocks?(followed, follower) && deny_follow_blocked},
           {:user_locked, false} <- {:user_locked, User.locked?(followed)},
           {:follow, {:ok, follower}} <- {:follow, User.follow(follower, followed)} do
        ActivityPub.accept(%{
          to: [follower.ap_id],
          actor: followed,
          object: data,
          local: true
        })
      else
        {:user_blocked, true} ->
          {:ok, _} = Utils.update_follow_state(activity, "reject")

          ActivityPub.reject(%{
            to: [follower.ap_id],
            actor: followed,
            object: data,
            local: true
          })

        {:follow, {:error, _}} ->
          {:ok, _} = Utils.update_follow_state(activity, "reject")

          ActivityPub.reject(%{
            to: [follower.ap_id],
            actor: followed,
            object: data,
            local: true
          })

        {:user_locked, true} ->
          :noop
      end

      {:ok, activity}
    else
      _e ->
        :error
    end
  end

  def handle_incoming(
        %{"type" => "Accept", "object" => follow_object, "actor" => _actor, "id" => _id} = data
      ) do
    with actor <- Containment.get_actor(data),
         {:ok, %User{} = followed} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, follow_activity} <- get_follow_activity(follow_object, followed),
         {:ok, follow_activity} <- Utils.update_follow_state(follow_activity, "accept"),
         %User{local: true} = follower <- User.get_cached_by_ap_id(follow_activity.data["actor"]),
         {:ok, activity} <-
           ActivityPub.accept(%{
             to: follow_activity.data["to"],
             type: "Accept",
             actor: followed,
             object: follow_activity.data["id"],
             local: false
           }) do
      if not User.following?(follower, followed) do
        {:ok, _follower} = User.follow(follower, followed)
      end

      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{"type" => "Reject", "object" => follow_object, "actor" => _actor, "id" => _id} = data
      ) do
    with actor <- Containment.get_actor(data),
         {:ok, %User{} = followed} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, follow_activity} <- get_follow_activity(follow_object, followed),
         {:ok, follow_activity} <- Utils.update_follow_state(follow_activity, "reject"),
         %User{local: true} = follower <- User.get_cached_by_ap_id(follow_activity.data["actor"]),
         {:ok, activity} <-
           ActivityPub.reject(%{
             to: follow_activity.data["to"],
             type: "Reject",
             actor: followed,
             object: follow_activity.data["id"],
             local: false
           }) do
      User.unfollow(follower, followed)

      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{"type" => "Like", "object" => object_id, "actor" => _actor, "id" => id} = data
      ) do
    with actor <- Containment.get_actor(data),
         {:ok, %User{} = actor} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, object} <- get_obj_helper(object_id),
         {:ok, activity, _object} <- ActivityPub.like(actor, object, id, false) do
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{"type" => "Announce", "object" => object_id, "actor" => _actor, "id" => id} = data
      ) do
    with actor <- Containment.get_actor(data),
         {:ok, %User{} = actor} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, object} <- get_obj_helper(object_id),
         public <- Visibility.is_public?(data),
         {:ok, activity, _object} <- ActivityPub.announce(actor, object, id, false, public) do
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{"type" => "Update", "object" => %{"type" => object_type} = object, "actor" => actor_id} =
          data
      )
      when object_type in ["Person", "Application", "Service", "Organization"] do
    with %User{ap_id: ^actor_id} = actor <- User.get_cached_by_ap_id(object["id"]) do
      {:ok, new_user_data} = ActivityPub.user_data_from_user_object(object)

      banner = new_user_data[:info]["banner"]
      locked = new_user_data[:info]["locked"] || false

      update_data =
        new_user_data
        |> Map.take([:name, :bio, :avatar])
        |> Map.put(:info, %{"banner" => banner, "locked" => locked})

      actor
      |> User.upgrade_changeset(update_data)
      |> User.update_and_set_cache()

      ActivityPub.update(%{
        local: false,
        to: data["to"] || [],
        cc: data["cc"] || [],
        object: object,
        actor: actor_id
      })
    else
      e ->
        Logger.error(e)
        :error
    end
  end

  # TODO: We presently assume that any actor on the same origin domain as the object being
  # deleted has the rights to delete that object.  A better way to validate whether or not
  # the object should be deleted is to refetch the object URI, which should return either
  # an error or a tombstone.  This would allow us to verify that a deletion actually took
  # place.
  def handle_incoming(
        %{"type" => "Delete", "object" => object_id, "actor" => _actor, "id" => _id} = data
      ) do
    object_id = Utils.get_ap_id(object_id)

    with actor <- Containment.get_actor(data),
         {:ok, %User{} = actor} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, object} <- get_obj_helper(object_id),
         :ok <- Containment.contain_origin(actor.ap_id, object.data),
         {:ok, activity} <- ActivityPub.delete(object, false) do
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{
          "type" => "Undo",
          "object" => %{"type" => "Announce", "object" => object_id},
          "actor" => _actor,
          "id" => id
        } = data
      ) do
    with actor <- Containment.get_actor(data),
         {:ok, %User{} = actor} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, object} <- get_obj_helper(object_id),
         {:ok, activity, _} <- ActivityPub.unannounce(actor, object, id, false) do
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{
          "type" => "Undo",
          "object" => %{"type" => "Follow", "object" => followed},
          "actor" => follower,
          "id" => id
        } = _data
      ) do
    with %User{local: true} = followed <- User.get_cached_by_ap_id(followed),
         {:ok, %User{} = follower} <- User.get_or_fetch_by_ap_id(follower),
         {:ok, activity} <- ActivityPub.unfollow(follower, followed, id, false) do
      User.unfollow(follower, followed)
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{
          "type" => "Undo",
          "object" => %{"type" => "Block", "object" => blocked},
          "actor" => blocker,
          "id" => id
        } = _data
      ) do
    with true <- Pleroma.Config.get([:activitypub, :accept_blocks]),
         %User{local: true} = blocked <- User.get_cached_by_ap_id(blocked),
         {:ok, %User{} = blocker} <- User.get_or_fetch_by_ap_id(blocker),
         {:ok, activity} <- ActivityPub.unblock(blocker, blocked, id, false) do
      User.unblock(blocker, blocked)
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{"type" => "Block", "object" => blocked, "actor" => blocker, "id" => id} = _data
      ) do
    with true <- Pleroma.Config.get([:activitypub, :accept_blocks]),
         %User{local: true} = blocked = User.get_cached_by_ap_id(blocked),
         {:ok, %User{} = blocker} = User.get_or_fetch_by_ap_id(blocker),
         {:ok, activity} <- ActivityPub.block(blocker, blocked, id, false) do
      User.unfollow(blocker, blocked)
      User.block(blocker, blocked)
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(
        %{
          "type" => "Undo",
          "object" => %{"type" => "Like", "object" => object_id},
          "actor" => _actor,
          "id" => id
        } = data
      ) do
    with actor <- Containment.get_actor(data),
         {:ok, %User{} = actor} <- User.get_or_fetch_by_ap_id(actor),
         {:ok, object} <- get_obj_helper(object_id),
         {:ok, activity, _, _} <- ActivityPub.unlike(actor, object, id, false) do
      {:ok, activity}
    else
      _e -> :error
    end
  end

  def handle_incoming(_), do: :error

  def get_obj_helper(id) do
    if object = Object.normalize(id), do: {:ok, object}, else: nil
  end

  def set_reply_to_uri(%{"inReplyTo" => in_reply_to} = object) when is_binary(in_reply_to) do
    with false <- String.starts_with?(in_reply_to, "http"),
         {:ok, %{data: replied_to_object}} <- get_obj_helper(in_reply_to) do
      Map.put(object, "inReplyTo", replied_to_object["external_url"] || in_reply_to)
    else
      _e -> object
    end
  end

  def set_reply_to_uri(obj), do: obj

  # Prepares the object of an outgoing create activity.
  def prepare_object(object) do
    object
    |> set_sensitive
    |> add_hashtags
    |> add_mention_tags
    |> add_emoji_tags
    |> add_attributed_to
    |> add_likes
    |> prepare_attachments
    |> set_conversation
    |> set_reply_to_uri
    |> strip_internal_fields
    |> strip_internal_tags
  end

  #  @doc
  #  """
  #  internal -> Mastodon
  #  """

  def prepare_outgoing(%{"type" => "Create", "object" => object_id} = data) do
    object =
      Object.normalize(object_id).data
      |> prepare_object

    data =
      data
      |> Map.put("object", object)
      |> Map.merge(Utils.make_json_ld_header())

    {:ok, data}
  end

  # Mastodon Accept/Reject requires a non-normalized object containing the actor URIs,
  # because of course it does.
  def prepare_outgoing(%{"type" => "Accept"} = data) do
    with follow_activity <- Activity.normalize(data["object"]) do
      object = %{
        "actor" => follow_activity.actor,
        "object" => follow_activity.data["object"],
        "id" => follow_activity.data["id"],
        "type" => "Follow"
      }

      data =
        data
        |> Map.put("object", object)
        |> Map.merge(Utils.make_json_ld_header())

      {:ok, data}
    end
  end

  def prepare_outgoing(%{"type" => "Reject"} = data) do
    with follow_activity <- Activity.normalize(data["object"]) do
      object = %{
        "actor" => follow_activity.actor,
        "object" => follow_activity.data["object"],
        "id" => follow_activity.data["id"],
        "type" => "Follow"
      }

      data =
        data
        |> Map.put("object", object)
        |> Map.merge(Utils.make_json_ld_header())

      {:ok, data}
    end
  end

  def prepare_outgoing(%{"type" => _type} = data) do
    data =
      data
      |> strip_internal_fields
      |> maybe_fix_object_url
      |> Map.merge(Utils.make_json_ld_header())

    {:ok, data}
  end

  def maybe_fix_object_url(data) do
    if is_binary(data["object"]) and not String.starts_with?(data["object"], "http") do
      case get_obj_helper(data["object"]) do
        {:ok, relative_object} ->
          if relative_object.data["external_url"] do
            _data =
              data
              |> Map.put("object", relative_object.data["external_url"])
          else
            data
          end

        e ->
          Logger.error("Couldn't fetch #{data["object"]} #{inspect(e)}")
          data
      end
    else
      data
    end
  end

  def add_hashtags(object) do
    tags =
      (object["tag"] || [])
      |> Enum.map(fn
        # Expand internal representation tags into AS2 tags.
        tag when is_binary(tag) ->
          %{
            "href" => Pleroma.Web.Endpoint.url() <> "/tags/#{tag}",
            "name" => "##{tag}",
            "type" => "Hashtag"
          }

        # Do not process tags which are already AS2 tag objects.
        tag when is_map(tag) ->
          tag
      end)

    object
    |> Map.put("tag", tags)
  end

  def add_mention_tags(object) do
    mentions =
      object
      |> Utils.get_notified_from_object()
      |> Enum.map(fn user ->
        %{"type" => "Mention", "href" => user.ap_id, "name" => "@#{user.nickname}"}
      end)

    tags = object["tag"] || []

    object
    |> Map.put("tag", tags ++ mentions)
  end

  def add_emoji_tags(%User{info: %{"emoji" => _emoji} = user_info} = object) do
    user_info = add_emoji_tags(user_info)

    object
    |> Map.put(:info, user_info)
  end

  # TODO: we should probably send mtime instead of unix epoch time for updated
  def add_emoji_tags(%{"emoji" => emoji} = object) do
    tags = object["tag"] || []

    out =
      emoji
      |> Enum.map(fn {name, url} ->
        %{
          "icon" => %{"url" => url, "type" => "Image"},
          "name" => ":" <> name <> ":",
          "type" => "Emoji",
          "updated" => "1970-01-01T00:00:00Z",
          "id" => url
        }
      end)

    object
    |> Map.put("tag", tags ++ out)
  end

  def add_emoji_tags(object) do
    object
  end

  def set_conversation(object) do
    Map.put(object, "conversation", object["context"])
  end

  def set_sensitive(object) do
    tags = object["tag"] || []
    Map.put(object, "sensitive", "nsfw" in tags)
  end

  def add_attributed_to(object) do
    attributed_to = object["attributedTo"] || object["actor"]

    object
    |> Map.put("attributedTo", attributed_to)
  end

  def add_likes(%{"id" => id, "like_count" => likes} = object) do
    likes = %{
      "id" => "#{id}/likes",
      "first" => "#{id}/likes?page=1",
      "type" => "OrderedCollection",
      "totalItems" => likes
    }

    object
    |> Map.put("likes", likes)
  end

  def add_likes(object) do
    object
  end

  def prepare_attachments(object) do
    attachments =
      (object["attachment"] || [])
      |> Enum.map(fn data ->
        [%{"mediaType" => media_type, "href" => href} | _] = data["url"]
        %{"url" => href, "mediaType" => media_type, "name" => data["name"], "type" => "Document"}
      end)

    object
    |> Map.put("attachment", attachments)
  end

  defp strip_internal_fields(object) do
    object
    |> Map.drop([
      "like_count",
      "announcements",
      "announcement_count",
      "emoji",
      "context_id",
      "deleted_activity_id"
    ])
  end

  defp strip_internal_tags(%{"tag" => tags} = object) do
    tags =
      tags
      |> Enum.filter(fn x -> is_map(x) end)

    object
    |> Map.put("tag", tags)
  end

  defp strip_internal_tags(object), do: object

  def perform(:user_upgrade, user) do
    # we pass a fake user so that the followers collection is stripped away
    old_follower_address = User.ap_followers(%User{nickname: user.nickname})

    q =
      from(
        u in User,
        where: ^old_follower_address in u.following,
        update: [
          set: [
            following:
              fragment(
                "array_replace(?,?,?)",
                u.following,
                ^old_follower_address,
                ^user.follower_address
              )
          ]
        ]
      )

    Repo.update_all(q, [])

    maybe_retire_websub(user.ap_id)

    q =
      from(
        a in Activity,
        where: ^old_follower_address in a.recipients,
        update: [
          set: [
            recipients:
              fragment(
                "array_replace(?,?,?)",
                a.recipients,
                ^old_follower_address,
                ^user.follower_address
              )
          ]
        ]
      )

    Repo.update_all(q, [])
  end

  def upgrade_user_from_ap_id(ap_id) do
    with %User{local: false} = user <- User.get_cached_by_ap_id(ap_id),
         {:ok, data} <- ActivityPub.fetch_and_prepare_user_from_ap_id(ap_id),
         already_ap <- User.ap_enabled?(user),
         {:ok, user} <- user |> User.upgrade_changeset(data) |> User.update_and_set_cache() do
      unless already_ap do
        PleromaJobQueue.enqueue(:transmogrifier, __MODULE__, [:user_upgrade, user])
      end

      {:ok, user}
    else
      %User{} = user -> {:ok, user}
      e -> e
    end
  end

  def maybe_retire_websub(ap_id) do
    # some sanity checks
    if is_binary(ap_id) && String.length(ap_id) > 8 do
      q =
        from(
          ws in Pleroma.Web.Websub.WebsubClientSubscription,
          where: fragment("? like ?", ws.topic, ^"#{ap_id}%")
        )

      Repo.delete_all(q)
    end
  end

  def maybe_fix_user_url(data) do
    if is_map(data["url"]) do
      Map.put(data, "url", data["url"]["href"])
    else
      data
    end
  end

  def maybe_fix_user_object(data) do
    data
    |> maybe_fix_user_url
  end
end
