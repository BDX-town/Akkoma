# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Transmogrifier do
  @moduledoc """
  A module to handle coding from internal to wire ActivityPub and back.
  """
  alias Pleroma.Activity
  alias Pleroma.EctoType.ActivityPub.ObjectValidators
  alias Pleroma.Maps
  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Builder
  alias Pleroma.Web.ActivityPub.ObjectValidator
  alias Pleroma.Web.ActivityPub.Pipeline
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.ActivityPub.ObjectValidators.CommonFixes
  alias Pleroma.Web.Federator

  import Ecto.Query

  require Pleroma.Constants
  require Logger

  @doc """
  Modifies an incoming AP object (mastodon format) to our internal format.
  (This only deals with non-activity AP objects)
  """
  def fix_object(object, options \\ []) do
    object
    |> strip_internal_fields()
    |> fix_actor()
    |> fix_url()
    |> fix_attachments()
    |> fix_context()
    |> fix_in_reply_to(options)
    |> fix_quote_url(options)
    |> fix_emoji()
    |> fix_tag()
    |> fix_content_map()
    |> fix_addressing()
    |> fix_summary()
    |> fix_history(&fix_object/1)
  end

  defp maybe_fix_object(%{"attributedTo" => _} = object), do: fix_object(object)
  defp maybe_fix_object(object), do: object

  defp fix_history(%{"formerRepresentations" => %{"orderedItems" => list}} = obj, fix_fun)
       when is_list(list) do
    update_in(obj["formerRepresentations"]["orderedItems"], fn h -> Enum.map(h, fix_fun) end)
  end

  defp fix_history(obj, _), do: obj

  defp fix_recursive(obj, fun) do
    # unlike Erlang, Elixir does not support recursive inline functions
    # which would allow us to avoid reconstructing this on every recursion
    rec_fun = fn
      obj when is_map(obj) -> fix_recursive(obj, fun)
      # there may be simple AP IDs in history (or object field)
      obj -> obj
    end

    obj
    |> fun.()
    |> fix_history(rec_fun)
    |> then(fn
      %{"object" => object} = doc when is_map(object) ->
        update_in(doc["object"], rec_fun)

      apdoc ->
        apdoc
    end)
  end

  def fix_summary(%{"summary" => nil} = object) do
    Map.put(object, "summary", "")
  end

  def fix_summary(%{"summary" => _} = object) do
    # summary is present, nothing to do
    object
  end

  def fix_summary(object), do: Map.put(object, "summary", "")

  defp fix_addressing_list(addrs) do
    cond do
      is_list(addrs) -> Enum.filter(addrs, &is_binary/1)
      is_binary(addrs) -> [addrs]
      true -> []
    end
  end

  # Due to JSON-LD simply "Public" and "as:Public" are equivalent to the full URI
  # but to simplify later checks we only want to deal with one reperesentation internally
  defp normalise_addressing_public_list(map, all_fields)

  defp normalise_addressing_public_list(%{} = map, [field | fields]) do
    full_uri = Pleroma.Constants.as_public()

    map =
      if map[field] != nil do
        new_fval =
          map[field]
          |> fix_addressing_list()
          |> Enum.map(fn
            "Public" -> full_uri
            "as:Public" -> full_uri
            x -> x
          end)

        Map.put(map, field, new_fval)
      else
        map
      end

    normalise_addressing_public_list(map, fields)
  end

  defp normalise_addressing_public_list(map, _) do
    map
  end

  defp normalise_addressing_public(map) do
    normalise_addressing_public_list(map, ["to", "cc", "bto", "bcc"])
  end

  # if directMessage flag is set to true, leave the addressing alone
  def fix_explicit_addressing(%{"directMessage" => true} = object, _follower_collection),
    do: object

  def fix_explicit_addressing(%{"to" => to, "cc" => cc} = object, follower_collection) do
    explicit_mentions =
      Utils.determine_explicit_mentions(object) ++
        [Pleroma.Constants.as_public(), follower_collection]

    explicit_to = Enum.filter(to, fn x -> x in explicit_mentions end)
    explicit_cc = Enum.filter(to, fn x -> x not in explicit_mentions end)

    final_cc =
      (cc ++ explicit_cc)
      |> Enum.filter(& &1)
      |> Enum.reject(fn x -> String.ends_with?(x, "/followers") and x != follower_collection end)
      |> Enum.uniq()

    object
    |> Map.put("to", explicit_to)
    |> Map.put("cc", final_cc)
  end

  def fix_addressing_list_key(map, field) do
    Map.put(map, field, fix_addressing_list(map[field]))
  end

  def fix_addressing(object) do
    {:ok, %User{follower_address: follower_collection}} =
      object
      |> Containment.get_actor()
      |> User.get_or_fetch_by_ap_id()

    object
    |> fix_addressing_list_key("to")
    |> fix_addressing_list_key("cc")
    |> fix_addressing_list_key("bto")
    |> fix_addressing_list_key("bcc")
    |> fix_explicit_addressing(follower_collection)
    |> CommonFixes.fix_implicit_addressing(follower_collection)
  end

  def fix_actor(%{"attributedTo" => actor} = object) do
    actor = Containment.get_actor(%{"actor" => actor})

    # TODO: Remove actor field for Objects
    object
    |> Map.put("actor", actor)
    |> Map.put("attributedTo", actor)
  end

  def fix_in_reply_to(object, options \\ [])

  def fix_in_reply_to(%{"inReplyTo" => in_reply_to} = object, options)
      when not is_nil(in_reply_to) do
    in_reply_to_id = prepare_in_reply_to(in_reply_to)
    depth = (options[:depth] || 0) + 1

    if Federator.allowed_thread_distance?(depth) do
      with {:ok, replied_object} <- get_obj_helper(in_reply_to_id, options),
           %Activity{} <- Activity.get_create_by_object_ap_id(replied_object.data["id"]) do
        object
        |> Map.put("inReplyTo", replied_object.data["id"])
        |> Map.put("context", replied_object.data["context"] || object["conversation"])
        |> Map.drop(["conversation", "inReplyToAtomUri"])
      else
        _ ->
          object
      end
    else
      object
    end
  end

  def fix_in_reply_to(object, _options), do: object

  def fix_quote_url(object, options \\ [])

  def fix_quote_url(%{"quoteUri" => quote_url} = object, options)
      when not is_nil(quote_url) do
    depth = (options[:depth] || 0) + 1

    if Federator.allowed_thread_distance?(depth) do
      with {:ok, quoted_object} <- get_obj_helper(quote_url, options),
           %Activity{} <- Activity.get_create_by_object_ap_id(quoted_object.data["id"]) do
        object
        |> Map.put("quoteUri", quoted_object.data["id"])
      else
        e ->
          Logger.warning("Couldn't fetch quote@#{inspect(quote_url)}, error: #{inspect(e)}")
          object
      end
    else
      object
    end
  end

  # Soapbox
  def fix_quote_url(%{"quoteUrl" => quote_url} = object, options) do
    object
    |> Map.put("quoteUri", quote_url)
    |> Map.delete("quoteUrl")
    |> fix_quote_url(options)
  end

  # Old Fedibird (bug)
  # https://github.com/fedibird/mastodon/issues/9
  def fix_quote_url(%{"quoteURL" => quote_url} = object, options) do
    object
    |> Map.put("quoteUri", quote_url)
    |> Map.delete("quoteURL")
    |> fix_quote_url(options)
  end

  def fix_quote_url(%{"_misskey_quote" => quote_url} = object, options) do
    object
    |> Map.put("quoteUri", quote_url)
    |> Map.delete("_misskey_quote")
    |> fix_quote_url(options)
  end

  def fix_quote_url(object, _), do: object

  defp prepare_in_reply_to(in_reply_to) do
    cond do
      is_bitstring(in_reply_to) ->
        in_reply_to

      is_map(in_reply_to) && is_bitstring(in_reply_to["id"]) ->
        in_reply_to["id"]

      is_list(in_reply_to) && is_bitstring(Enum.at(in_reply_to, 0)) ->
        Enum.at(in_reply_to, 0)

      true ->
        ""
    end
  end

  def fix_context(object) do
    context = object["context"] || object["conversation"] || Utils.generate_context_id()

    object
    |> Map.put("context", context)
    |> Map.drop(["conversation"])
  end

  def fix_attachments(%{"attachment" => attachment} = object) when is_list(attachment) do
    attachments =
      Enum.map(attachment, fn data ->
        url =
          cond do
            is_list(data["url"]) -> List.first(data["url"])
            is_map(data["url"]) -> data["url"]
            true -> nil
          end

        media_type =
          cond do
            is_map(url) && MIME.extensions(url["mediaType"]) != [] ->
              url["mediaType"]

            is_bitstring(data["mediaType"]) && MIME.extensions(data["mediaType"]) != [] ->
              data["mediaType"]

            is_bitstring(data["mimeType"]) && MIME.extensions(data["mimeType"]) != [] ->
              data["mimeType"]

            true ->
              nil
          end

        href =
          cond do
            is_map(url) && is_binary(url["href"]) -> url["href"]
            is_binary(data["url"]) -> data["url"]
            is_binary(data["href"]) -> data["href"]
            true -> nil
          end

        if href do
          attachment_url =
            %{
              "href" => href,
              "type" => Map.get(url || %{}, "type", "Link")
            }
            |> Maps.put_if_present("mediaType", media_type)
            |> Maps.put_if_present("width", (url || %{})["width"] || data["width"])
            |> Maps.put_if_present("height", (url || %{})["height"] || data["height"])

          %{
            "url" => [attachment_url],
            "type" => data["type"] || "Document"
          }
          |> Maps.put_if_present("mediaType", media_type)
          |> Maps.put_if_present("name", data["name"])
          |> Maps.put_if_present("blurhash", data["blurhash"])
        else
          nil
        end
      end)
      |> Enum.filter(& &1)

    Map.put(object, "attachment", attachments)
  end

  def fix_attachments(%{"attachment" => attachment} = object) when is_map(attachment) do
    object
    |> Map.put("attachment", [attachment])
    |> fix_attachments()
  end

  def fix_attachments(object), do: object

  def fix_url(%{"url" => url} = object) when is_map(url) do
    Map.put(object, "url", url["href"])
  end

  def fix_url(%{"url" => url} = object) when is_list(url) do
    first_element = Enum.at(url, 0)

    url_string =
      cond do
        is_bitstring(first_element) -> first_element
        is_map(first_element) -> first_element["href"] || ""
        true -> ""
      end

    Map.put(object, "url", url_string)
  end

  def fix_url(object), do: object

  def fix_emoji(%{"tag" => tags} = object) when is_list(tags) do
    emoji =
      tags
      |> Enum.filter(fn data -> is_map(data) and data["type"] == "Emoji" and data["icon"] end)
      |> Enum.reduce(%{}, fn data, mapping ->
        name = String.trim(data["name"], ":")

        Map.put(mapping, name, data["icon"]["url"])
      end)

    Map.put(object, "emoji", emoji)
  end

  def fix_emoji(%{"tag" => %{"type" => "Emoji"} = tag} = object) do
    name = String.trim(tag["name"], ":")
    emoji = %{name => tag["icon"]["url"]}

    Map.put(object, "emoji", emoji)
  end

  def fix_emoji(object), do: object

  def fix_tag(%{"tag" => tag} = object) when is_list(tag) do
    tags =
      tag
      |> Enum.filter(fn data -> data["type"] == "Hashtag" and data["name"] end)
      |> Enum.map(fn
        %{"name" => "#" <> hashtag} -> String.downcase(hashtag)
        %{"name" => hashtag} -> String.downcase(hashtag)
      end)

    Map.put(object, "tag", tag ++ tags)
  end

  def fix_tag(%{"tag" => %{} = tag} = object) do
    object
    |> Map.put("tag", [tag])
    |> fix_tag
  end

  def fix_tag(object), do: object

  # content map usually only has one language so this will do for now.
  def fix_content_map(%{"contentMap" => content_map} = object) when is_map(content_map) do
    content_groups = Map.to_list(content_map)

    if Enum.empty?(content_groups) do
      object
    else
      {_, content} = Enum.at(content_groups, 0)

      Map.put(object, "content", content)
    end
  end

  def fix_content_map(object), do: object

  defp fix_type(%{"type" => "Note", "inReplyTo" => reply_id, "name" => _} = object, options)
       when is_binary(reply_id) do
    options = Keyword.put(options, :fetch, true)

    with %Object{data: %{"type" => "Question"}} <- Object.normalize(reply_id, options) do
      Map.put(object, "type", "Answer")
    else
      _ -> object
    end
  end

  defp fix_type(object, _options), do: object

  # Reduce the object list to find the reported user.
  defp get_reported(objects) do
    Enum.reduce_while(objects, nil, fn ap_id, _ ->
      with %User{} = user <- User.get_cached_by_ap_id(ap_id) do
        {:halt, user}
      else
        _ -> {:cont, nil}
      end
    end)
  end

  def handle_incoming(data, options \\ []) do
    data
    |> fix_recursive(&normalise_addressing_public/1)
    |> fix_recursive(&strip_internal_fields/1)
    |> handle_incoming_normalised(options)
  end

  defp handle_incoming_normalised(data, options)

  # Flag objects are placed ahead of the ID check because Mastodon 2.8 and earlier send them
  # with nil ID.
  defp handle_incoming_normalised(
         %{"type" => "Flag", "object" => objects, "actor" => actor} = data,
         _options
       ) do
    with context <- data["context"] || Utils.generate_context_id(),
         content <- data["content"] || "",
         %User{} = actor <- User.get_cached_by_ap_id(actor),
         # Reduce the object list to find the reported user.
         %User{} = account <- get_reported(objects),
         # Remove the reported user from the object list.
         statuses <- Enum.filter(objects, fn ap_id -> ap_id != account.ap_id end) do
      %{
        actor: actor,
        context: context,
        account: account,
        statuses: statuses,
        content: content,
        additional: %{"cc" => [account.ap_id]}
      }
      |> ActivityPub.flag()
    end
  end

  # disallow objects with bogus IDs
  defp handle_incoming_normalised(%{"id" => nil}, _options), do: :error
  defp handle_incoming_normalised(%{"id" => ""}, _options), do: :error
  # length of https:// = 8, should validate better, but good enough for now.
  defp handle_incoming_normalised(%{"id" => id}, _options)
       when is_binary(id) and byte_size(id) < 8,
       do: :error

  # Rewrite misskey likes into EmojiReacts
  defp handle_incoming_normalised(
         %{
           "type" => "Like",
           "content" => reaction
         } = data,
         options
       ) do
    if Pleroma.Emoji.is_unicode_emoji?(reaction) || Pleroma.Emoji.matches_shortcode?(reaction) do
      data
      |> Map.put("type", "EmojiReact")
      |> handle_incoming(options)
    else
      data
      |> Map.delete("content")
      |> handle_incoming(options)
    end
  end

  defp handle_incoming_normalised(
         %{"type" => "Create", "object" => %{"type" => objtype, "id" => obj_id}} = data,
         options
       )
       when objtype in ~w{Question Answer Audio Video Event Article Note Page} do
    fetch_options = Keyword.put(options, :depth, (options[:depth] || 0) + 1)

    object =
      data["object"]
      |> fix_type(fetch_options)
      |> fix_in_reply_to(fetch_options)
      |> fix_quote_url(fetch_options)

    # Only change the Create's context if the object's context has been modified.
    data =
      if data["object"]["context"] != object["context"] do
        data
        |> Map.put("object", object)
        |> Map.put("context", object["context"])
      else
        Map.put(data, "object", object)
      end

    options = Keyword.put(options, :local, false)

    with {:ok, %User{}} <- ObjectValidator.fetch_actor(data),
         nil <- Activity.get_create_by_object_ap_id(obj_id),
         {:ok, activity, _} <- Pipeline.common_pipeline(data, options) do
      {:ok, activity}
    else
      %Activity{} = activity -> {:ok, activity}
      e -> e
    end
  end

  defp handle_incoming_normalised(%{"type" => type} = data, _options)
       when type in ~w{Like EmojiReact Announce Add Remove} do
    with {_, :ok} <- {:link, ObjectValidator.fetch_actor_and_object(data)},
         {:ok, activity, _meta} <- Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    else
      {:link, {:error, :ignore}} ->
        {:error, :ignore}

      {:link, {:error, {:validate, _}} = e} ->
        e

      {:link, {:error, {:reject, _}} = e} ->
        e

      {:link, _} ->
        {:error, :link_resolve_failed}

      e ->
        {:error, e}
    end
  end

  defp handle_incoming_normalised(
         %{"type" => type} = data,
         _options
       )
       when type in ~w{Update Block Follow Accept Reject} do
    fixed_obj = maybe_fix_object(data["object"])
    data = if fixed_obj != nil, do: %{data | "object" => fixed_obj}, else: data

    with {:ok, %User{}} <- ObjectValidator.fetch_actor(data),
         {:ok, activity, _} <-
           Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    end
  end

  defp handle_incoming_normalised(
         %{"type" => "Delete"} = data,
         _options
       ) do
    oid_result = ObjectValidators.ObjectID.cast(data["object"])

    with {_, {:ok, object_id}} <- {:object_id, oid_result},
         object <- Object.get_cached_by_ap_id(object_id),
         {_, false} <- {:tombstone, Object.tombstone_object?(object) && !data["actor"]},
         {:ok, activity, _} <- Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    else
      {:object_id, _} ->
        {:error, {:validate, "Invalid object id: #{data["object"]}"}}

      {:tombstone, true} ->
        {:error, :ignore}

      {:error, {:validate, {:error, %Ecto.Changeset{errors: errors}}}} = e ->
        if errors[:object] == {"can't find object", []} do
          # Check if we have a create activity for this
          # (e.g. from a db prune without --prune-activities)
          # We'd still like to process side effects so insert a fake tombstone and retry
          # (real tombstones from Object.delete do not have an actor field)
          with {:ok, object_id} <- ObjectValidators.ObjectID.cast(data["object"]),
               {_, %Activity{data: %{"actor" => actor}}} <-
                 {:create, Activity.create_by_object_ap_id(object_id) |> Repo.one()},
               {:ok, tombstone_data, _} <- Builder.tombstone(actor, object_id),
               {:ok, _tombstone} <- Object.create(tombstone_data) do
            handle_incoming(data)
          else
            {:create, _} -> {:error, :ignore}
            _ -> e
          end
        else
          e
        end

      {:error, _} = e ->
        e

      e ->
        {:error, e}
    end
  end

  defp handle_incoming_normalised(
         %{
           "type" => "Undo",
           "object" => %{"type" => "Follow", "object" => followed},
           "actor" => follower,
           "id" => id
         } = _data,
         _options
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

  defp handle_incoming_normalised(
         %{
           "type" => "Undo",
           "object" => %{"type" => type}
         } = data,
         _options
       )
       when type in ["Like", "EmojiReact", "Announce", "Block"] do
    with {:ok, activity, _} <- Pipeline.common_pipeline(data, local: false) do
      {:ok, activity}
    else
      {:error, {:validate, {:error, %Ecto.Changeset{errors: errors}}}} = e ->
        # If we never saw the activity being undone, no need to do anything.
        # Inspectinging the validation error content is a bit akward, but looking up the Activity
        # ahead of time here would be too costly since Activity queries are not cached
        # and there's no way atm to pass the retrieved result along along
        if errors[:object] == {"can't find object", []} do
          {:error, :ignore}
        else
          e
        end

      e ->
        e
    end
  end

  # For Undos that don't have the complete object attached, try to find it in our database.
  defp handle_incoming_normalised(
         %{
           "type" => "Undo",
           "object" => object
         } = activity,
         options
       )
       when is_binary(object) do
    with %Activity{data: data} <- Activity.get_by_ap_id(object) do
      activity
      |> Map.put("object", data)
      |> handle_incoming(options)
    else
      _e -> :error
    end
  end

  defp handle_incoming_normalised(
         %{
           "type" => "Move",
           "actor" => origin_actor,
           "object" => origin_actor,
           "target" => target_actor
         },
         _options
       ) do
    with %User{} = origin_user <- User.get_cached_by_ap_id(origin_actor),
         # Use a dramatically shortened maximum age before refresh here because it is reasonable
         # for a user to
         # 1. Add the alias to their new account and then
         # 2. Press the button on their new account
         # within a very short period of time and expect it to work
         {:ok, %User{} = target_user} <- User.get_or_fetch_by_ap_id(target_actor, maximum_age: 5),
         true <- origin_actor in target_user.also_known_as do
      ActivityPub.move(origin_user, target_user, false)
    else
      _e -> :error
    end
  end

  defp handle_incoming_normalised(_, _), do: :error

  @spec get_obj_helper(String.t(), Keyword.t()) :: {:ok, Object.t()} | nil
  def get_obj_helper(id, options \\ []) do
    options = Keyword.put(options, :fetch, true)

    case Object.normalize(id, options) do
      %Object{} = object -> {:ok, object}
      _ -> nil
    end
  end

  @spec get_embedded_obj_helper(String.t() | Object.t(), User.t()) :: {:ok, Object.t()} | nil
  def get_embedded_obj_helper(%{"attributedTo" => attributed_to, "id" => object_id} = data, %User{
        ap_id: ap_id
      })
      when attributed_to == ap_id do
    with {:ok, activity} <-
           handle_incoming(%{
             "type" => "Create",
             "to" => data["to"],
             "cc" => data["cc"],
             "actor" => attributed_to,
             "object" => data
           }) do
      {:ok, Object.normalize(activity, fetch: false)}
    else
      _ -> get_obj_helper(object_id)
    end
  end

  def get_embedded_obj_helper(object_id, _) do
    get_obj_helper(object_id)
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

  def set_quote_url(%{"quoteUri" => quote} = object) when is_binary(quote) do
    Map.put(object, "quoteUrl", quote)
  end

  def set_quote_url(obj), do: obj

  @doc """
  Serialized Mastodon-compatible `replies` collection containing _self-replies_.
  Based on Mastodon's ActivityPub::NoteSerializer#replies.
  """
  def set_replies(obj_data) do
    replies_uris =
      with limit when limit > 0 <-
             Pleroma.Config.get([:activitypub, :note_replies_output_limit], 0),
           %Object{} = object <- Object.get_cached_by_ap_id(obj_data["id"]) do
        object
        |> Object.self_replies()
        |> select([o], fragment("?->>'id'", o.data))
        |> limit(^limit)
        |> Repo.all()
      else
        _ -> []
      end

    set_replies(obj_data, replies_uris)
  end

  defp set_replies(obj, []) do
    obj
  end

  defp set_replies(obj, replies_uris) do
    replies_collection = %{
      "type" => "Collection",
      "items" => replies_uris
    }

    Map.merge(obj, %{"replies" => replies_collection})
  end

  def replies(%{"replies" => %{"first" => %{"items" => items}}}) when not is_nil(items) do
    items
  end

  def replies(%{"replies" => %{"items" => items}}) when not is_nil(items) do
    items
  end

  def replies(_), do: []

  # Prepares the object of an outgoing create activity.
  def prepare_object(object) do
    object
    |> add_hashtags
    |> add_mention_tags
    |> add_emoji_tags
    |> add_attributed_to
    |> prepare_attachments
    |> set_conversation
    |> set_reply_to_uri
    |> set_quote_url()
    |> set_replies
    |> strip_internal_fields
    |> strip_internal_tags
    |> set_type
    |> maybe_process_history
  end

  defp maybe_process_history(%{"formerRepresentations" => %{"orderedItems" => history}} = object) do
    processed_history =
      Enum.map(
        history,
        fn
          item when is_map(item) -> prepare_object(item)
          item -> item
        end
      )

    put_in(object, ["formerRepresentations", "orderedItems"], processed_history)
  end

  defp maybe_process_history(object) do
    object
  end

  #  @doc
  #  """
  #  internal -> Mastodon
  #  """

  @pleroma_reactions %{
    "👍" => "like",
    "❤️" => "love",
    "😆" => "laugh",
    "🤔" => "hmm",
    "😮" => "surprise",
    "🎉" => "congrats",
    "💢" => "angry",
    "😥" => "confused",
    "😇" => "rip",
    "🍮" => "pudding",
    "⭐" => "star"
  }

  @doc "Rewrite EmojiReact into misskey like to keep compatibility with Mastodon, Misskey and other Pleromas"
  def prepare_outgoing(%{"type" => "EmojiReact", "content" => content} = data) do
    data =
      data
      |> Map.replace("type", "Like")
      |> Map.put("_misskey_reaction", @pleroma_reactions[content] || content)
      |> Map.delete("content")
      |> Map.delete("tag")
      |> strip_internal_fields
      |> maybe_fix_object_url
      |> Map.merge(Utils.make_json_ld_header())
    {:ok, data}
  end

  def prepare_outgoing(%{"type" => activity_type, "object" => object_id} = data)
      when activity_type in ["Create"] do
    object =
      object_id
      |> Object.normalize(fetch: false)
      |> Map.get(:data)
      |> prepare_object

    data =
      data
      |> Map.put("object", object)
      |> Map.merge(Utils.make_json_ld_header())
      |> Map.delete("bcc")

    {:ok, data}
  end

  def prepare_outgoing(%{"type" => "Update", "object" => %{"type" => objtype} = object} = data)
      when objtype in Pleroma.Constants.updatable_object_types() do
    object =
      object
      |> prepare_object

    data =
      data
      |> Map.put("object", object)
      |> Map.merge(Utils.make_json_ld_header())
      |> Map.delete("bcc")

    {:ok, data}
  end

  def prepare_outgoing(%{"type" => "Announce", "actor" => ap_id, "object" => object_id} = data) do
    object =
      object_id
      |> Object.normalize(fetch: false)

    data =
      if Visibility.is_private?(object) && object.data["actor"] == ap_id do
        data |> Map.put("object", object |> Map.get(:data) |> prepare_object)
      else
        data |> maybe_fix_object_url
      end

    data =
      data
      |> strip_internal_fields
      |> Map.merge(Utils.make_json_ld_header())
      |> Map.delete("bcc")

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

  def maybe_fix_object_url(%{"object" => object} = data) when is_binary(object) do
    with false <- String.starts_with?(object, "http"),
         {:fetch, {:ok, relative_object}} <- {:fetch, get_obj_helper(object)},
         %{data: %{"external_url" => external_url}} when not is_nil(external_url) <-
           relative_object do
      Map.put(data, "object", external_url)
    else
      {:fetch, _} ->
        data

      _ ->
        data
    end
  end

  def maybe_fix_object_url(data), do: data

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

    Map.put(object, "tag", tags)
  end

  # TODO These should be added on our side on insertion, it doesn't make much
  # sense to regenerate these all the time
  def add_mention_tags(object) do
    to = object["to"] || []
    cc = object["cc"] || []
    mentioned = User.get_users_from_set(to ++ cc, local_only: false)

    mentions = Enum.map(mentioned, &build_mention_tag/1)

    tags = object["tag"] || []
    Map.put(object, "tag", tags ++ mentions)
  end

  defp build_mention_tag(%{ap_id: ap_id, nickname: nickname} = _) do
    %{"type" => "Mention", "href" => ap_id, "name" => "@#{nickname}"}
  end

  def take_emoji_tags(%User{emoji: emoji}) do
    emoji
    |> Map.to_list()
    |> Enum.map(&build_emoji_tag/1)
  end

  # TODO: we should probably send mtime instead of unix epoch time for updated
  def add_emoji_tags(%{"emoji" => emoji} = object) do
    tags = object["tag"] || []

    out = Enum.map(emoji, &build_emoji_tag/1)

    Map.put(object, "tag", tags ++ out)
  end

  def add_emoji_tags(object), do: object

  defp build_emoji_tag({name, url}) do
    %{
      "icon" => %{"url" => "#{URI.encode(url)}", "type" => "Image"},
      "name" => ":" <> name <> ":",
      "type" => "Emoji",
      "updated" => "1970-01-01T00:00:00Z"
    }
  end

  def set_conversation(object) do
    Map.put(object, "conversation", object["context"])
  end

  def set_type(%{"type" => "Answer"} = object) do
    Map.put(object, "type", "Note")
  end

  def set_type(object), do: object

  def add_attributed_to(object) do
    attributed_to = object["attributedTo"] || object["actor"]
    Map.put(object, "attributedTo", attributed_to)
  end

  def prepare_attachments(object) do
    attachments =
      case Map.get(object, "attachment", []) do
        [_ | _] = list -> list
        _ -> []
      end

    attachments =
      attachments
      |> Enum.map(fn data ->
        [%{"mediaType" => media_type, "href" => href} = url | _] = data["url"]

        %{
          "url" => href,
          "mediaType" => media_type,
          "name" => data["name"],
          "type" => "Document"
        }
        |> Maps.put_if_present("width", url["width"])
        |> Maps.put_if_present("height", url["height"])
        |> Maps.put_if_present("blurhash", data["blurhash"])
      end)

    Map.put(object, "attachment", attachments)
  end

  # for outgoing docs immediately stripping internal fields recursively breaks later emoji transformations
  # (XXX: it would be better to reorder operations so we can always use recursive stripping)
  def strip_internal_fields(object) do
    Map.drop(object, Pleroma.Constants.object_internal_fields())
  end

  defp strip_internal_tags(%{"tag" => tags} = object) do
    tags = Enum.filter(tags, fn x -> is_map(x) end)

    Map.put(object, "tag", tags)
  end

  defp strip_internal_tags(object), do: object

  def maybe_fix_user_url(%{"url" => url} = data) when is_map(url) do
    Map.put(data, "url", url["href"])
  end

  def maybe_fix_user_url(data), do: data

  def maybe_fix_user_object(data), do: maybe_fix_user_url(data)
end
