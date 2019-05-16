# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.ActivityPub do
  alias Pleroma.Activity
  alias Pleroma.Conversation
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Object.Fetcher
  alias Pleroma.Pagination
  alias Pleroma.Repo
  alias Pleroma.Upload
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.MRF
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.WebFinger

  import Ecto.Query
  import Pleroma.Web.ActivityPub.Utils
  import Pleroma.Web.ActivityPub.Visibility

  require Logger

  # For Announce activities, we filter the recipients based on following status for any actors
  # that match actual users.  See issue #164 for more information about why this is necessary.
  defp get_recipients(%{"type" => "Announce"} = data) do
    to = data["to"] || []
    cc = data["cc"] || []
    actor = User.get_cached_by_ap_id(data["actor"])

    recipients =
      (to ++ cc)
      |> Enum.filter(fn recipient ->
        case User.get_cached_by_ap_id(recipient) do
          nil ->
            true

          user ->
            User.following?(user, actor)
        end
      end)

    {recipients, to, cc}
  end

  defp get_recipients(%{"type" => "Create"} = data) do
    to = data["to"] || []
    cc = data["cc"] || []
    actor = data["actor"] || []
    recipients = (to ++ cc ++ [actor]) |> Enum.uniq()
    {recipients, to, cc}
  end

  defp get_recipients(data) do
    to = data["to"] || []
    cc = data["cc"] || []
    recipients = to ++ cc
    {recipients, to, cc}
  end

  defp check_actor_is_active(actor) do
    if not is_nil(actor) do
      with user <- User.get_cached_by_ap_id(actor),
           false <- user.info.deactivated do
        :ok
      else
        _e -> :reject
      end
    else
      :ok
    end
  end

  defp check_remote_limit(%{"object" => %{"content" => content}}) when not is_nil(content) do
    limit = Pleroma.Config.get([:instance, :remote_limit])
    String.length(content) <= limit
  end

  defp check_remote_limit(_), do: true

  def increase_note_count_if_public(actor, object) do
    if is_public?(object), do: User.increase_note_count(actor), else: {:ok, actor}
  end

  def decrease_note_count_if_public(actor, object) do
    if is_public?(object), do: User.decrease_note_count(actor), else: {:ok, actor}
  end

  def increase_replies_count_if_reply(%{
        "object" => %{"inReplyTo" => reply_ap_id} = object,
        "type" => "Create"
      }) do
    if is_public?(object) do
      Object.increase_replies_count(reply_ap_id)
    end
  end

  def increase_replies_count_if_reply(_create_data), do: :noop

  def decrease_replies_count_if_reply(%Object{
        data: %{"inReplyTo" => reply_ap_id} = object
      }) do
    if is_public?(object) do
      Object.decrease_replies_count(reply_ap_id)
    end
  end

  def decrease_replies_count_if_reply(_object), do: :noop

  def insert(map, local \\ true, fake \\ false) when is_map(map) do
    with nil <- Activity.normalize(map),
         map <- lazy_put_activity_defaults(map, fake),
         :ok <- check_actor_is_active(map["actor"]),
         {_, true} <- {:remote_limit_error, check_remote_limit(map)},
         {:ok, map} <- MRF.filter(map),
         {recipients, _, _} = get_recipients(map),
         {:fake, false, map, recipients} <- {:fake, fake, map, recipients},
         {:ok, map, object} <- insert_full_object(map) do
      {:ok, activity} =
        Repo.insert(%Activity{
          data: map,
          local: local,
          actor: map["actor"],
          recipients: recipients
        })

      # Splice in the child object if we have one.
      activity =
        if !is_nil(object) do
          Map.put(activity, :object, object)
        else
          activity
        end

      PleromaJobQueue.enqueue(:background, Pleroma.Web.RichMedia.Helpers, [:fetch, activity])

      Notification.create_notifications(activity)

      participations =
        activity
        |> Conversation.create_or_bump_for()
        |> get_participations()

      stream_out(activity)
      stream_out_participations(participations)
      {:ok, activity}
    else
      %Activity{} = activity ->
        {:ok, activity}

      {:fake, true, map, recipients} ->
        activity = %Activity{
          data: map,
          local: local,
          actor: map["actor"],
          recipients: recipients,
          id: "pleroma:fakeid"
        }

        Pleroma.Web.RichMedia.Helpers.fetch_data_for_activity(activity)
        {:ok, activity}

      error ->
        {:error, error}
    end
  end

  defp get_participations({:ok, %{participations: participations}}), do: participations
  defp get_participations(_), do: []

  def stream_out_participations(participations) do
    participations =
      participations
      |> Repo.preload(:user)

    Enum.each(participations, fn participation ->
      Pleroma.Web.Streamer.stream("participation", participation)
    end)
  end

  def stream_out(activity) do
    public = "https://www.w3.org/ns/activitystreams#Public"

    if activity.data["type"] in ["Create", "Announce", "Delete"] do
      Pleroma.Web.Streamer.stream("user", activity)
      Pleroma.Web.Streamer.stream("list", activity)

      if Enum.member?(activity.data["to"], public) do
        Pleroma.Web.Streamer.stream("public", activity)

        if activity.local do
          Pleroma.Web.Streamer.stream("public:local", activity)
        end

        if activity.data["type"] in ["Create"] do
          object = Object.normalize(activity)

          object.data
          |> Map.get("tag", [])
          |> Enum.filter(fn tag -> is_bitstring(tag) end)
          |> Enum.each(fn tag -> Pleroma.Web.Streamer.stream("hashtag:" <> tag, activity) end)

          if object.data["attachment"] != [] do
            Pleroma.Web.Streamer.stream("public:media", activity)

            if activity.local do
              Pleroma.Web.Streamer.stream("public:local:media", activity)
            end
          end
        end
      else
        # TODO: Write test, replace with visibility test
        if !Enum.member?(activity.data["cc"] || [], public) &&
             !Enum.member?(
               activity.data["to"],
               User.get_cached_by_ap_id(activity.data["actor"]).follower_address
             ),
           do: Pleroma.Web.Streamer.stream("direct", activity)
      end
    end
  end

  def create(%{to: to, actor: actor, context: context, object: object} = params, fake \\ false) do
    additional = params[:additional] || %{}
    # only accept false as false value
    local = !(params[:local] == false)
    published = params[:published]

    with create_data <-
           make_create_data(
             %{to: to, actor: actor, published: published, context: context, object: object},
             additional
           ),
         {:ok, activity} <- insert(create_data, local, fake),
         {:fake, false, activity} <- {:fake, fake, activity},
         _ <- increase_replies_count_if_reply(create_data),
         # Changing note count prior to enqueuing federation task in order to avoid
         # race conditions on updating user.info
         {:ok, _actor} <- increase_note_count_if_public(actor, activity),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    else
      {:fake, true, activity} ->
        {:ok, activity}
    end
  end

  def accept(%{to: to, actor: actor, object: object} = params) do
    # only accept false as false value
    local = !(params[:local] == false)

    with data <- %{"to" => to, "type" => "Accept", "actor" => actor.ap_id, "object" => object},
         {:ok, activity} <- insert(data, local),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    end
  end

  def reject(%{to: to, actor: actor, object: object} = params) do
    # only accept false as false value
    local = !(params[:local] == false)

    with data <- %{"to" => to, "type" => "Reject", "actor" => actor.ap_id, "object" => object},
         {:ok, activity} <- insert(data, local),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    end
  end

  def update(%{to: to, cc: cc, actor: actor, object: object} = params) do
    # only accept false as false value
    local = !(params[:local] == false)

    with data <- %{
           "to" => to,
           "cc" => cc,
           "type" => "Update",
           "actor" => actor,
           "object" => object
         },
         {:ok, activity} <- insert(data, local),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    end
  end

  # TODO: This is weird, maybe we shouldn't check here if we can make the activity.
  def like(
        %User{ap_id: ap_id} = user,
        %Object{data: %{"id" => _}} = object,
        activity_id \\ nil,
        local \\ true
      ) do
    with nil <- get_existing_like(ap_id, object),
         like_data <- make_like_data(user, object, activity_id),
         {:ok, activity} <- insert(like_data, local),
         {:ok, object} <- add_like_to_object(activity, object),
         :ok <- maybe_federate(activity) do
      {:ok, activity, object}
    else
      %Activity{} = activity -> {:ok, activity, object}
      error -> {:error, error}
    end
  end

  def unlike(
        %User{} = actor,
        %Object{} = object,
        activity_id \\ nil,
        local \\ true
      ) do
    with %Activity{} = like_activity <- get_existing_like(actor.ap_id, object),
         unlike_data <- make_unlike_data(actor, like_activity, activity_id),
         {:ok, unlike_activity} <- insert(unlike_data, local),
         {:ok, _activity} <- Repo.delete(like_activity),
         {:ok, object} <- remove_like_from_object(like_activity, object),
         :ok <- maybe_federate(unlike_activity) do
      {:ok, unlike_activity, like_activity, object}
    else
      _e -> {:ok, object}
    end
  end

  def announce(
        %User{ap_id: _} = user,
        %Object{data: %{"id" => _}} = object,
        activity_id \\ nil,
        local \\ true,
        public \\ true
      ) do
    with true <- is_public?(object),
         announce_data <- make_announce_data(user, object, activity_id, public),
         {:ok, activity} <- insert(announce_data, local),
         {:ok, object} <- add_announce_to_object(activity, object),
         :ok <- maybe_federate(activity) do
      {:ok, activity, object}
    else
      error -> {:error, error}
    end
  end

  def unannounce(
        %User{} = actor,
        %Object{} = object,
        activity_id \\ nil,
        local \\ true
      ) do
    with %Activity{} = announce_activity <- get_existing_announce(actor.ap_id, object),
         unannounce_data <- make_unannounce_data(actor, announce_activity, activity_id),
         {:ok, unannounce_activity} <- insert(unannounce_data, local),
         :ok <- maybe_federate(unannounce_activity),
         {:ok, _activity} <- Repo.delete(announce_activity),
         {:ok, object} <- remove_announce_from_object(announce_activity, object) do
      {:ok, unannounce_activity, object}
    else
      _e -> {:ok, object}
    end
  end

  def follow(follower, followed, activity_id \\ nil, local \\ true) do
    with data <- make_follow_data(follower, followed, activity_id),
         {:ok, activity} <- insert(data, local),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    end
  end

  def unfollow(follower, followed, activity_id \\ nil, local \\ true) do
    with %Activity{} = follow_activity <- fetch_latest_follow(follower, followed),
         {:ok, follow_activity} <- update_follow_state(follow_activity, "cancelled"),
         unfollow_data <- make_unfollow_data(follower, followed, follow_activity, activity_id),
         {:ok, activity} <- insert(unfollow_data, local),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    end
  end

  def delete(%Object{data: %{"id" => id, "actor" => actor}} = object, local \\ true) do
    user = User.get_cached_by_ap_id(actor)
    to = (object.data["to"] || []) ++ (object.data["cc"] || [])

    with {:ok, object, activity} <- Object.delete(object),
         data <- %{
           "type" => "Delete",
           "actor" => actor,
           "object" => id,
           "to" => to,
           "deleted_activity_id" => activity && activity.id
         },
         {:ok, activity} <- insert(data, local),
         _ <- decrease_replies_count_if_reply(object),
         # Changing note count prior to enqueuing federation task in order to avoid
         # race conditions on updating user.info
         {:ok, _actor} <- decrease_note_count_if_public(user, object),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    end
  end

  def block(blocker, blocked, activity_id \\ nil, local \\ true) do
    ap_config = Application.get_env(:pleroma, :activitypub)
    unfollow_blocked = Keyword.get(ap_config, :unfollow_blocked)
    outgoing_blocks = Keyword.get(ap_config, :outgoing_blocks)

    with true <- unfollow_blocked do
      follow_activity = fetch_latest_follow(blocker, blocked)

      if follow_activity do
        unfollow(blocker, blocked, nil, local)
      end
    end

    with true <- outgoing_blocks,
         block_data <- make_block_data(blocker, blocked, activity_id),
         {:ok, activity} <- insert(block_data, local),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    else
      _e -> {:ok, nil}
    end
  end

  def unblock(blocker, blocked, activity_id \\ nil, local \\ true) do
    with %Activity{} = block_activity <- fetch_latest_block(blocker, blocked),
         unblock_data <- make_unblock_data(blocker, blocked, block_activity, activity_id),
         {:ok, activity} <- insert(unblock_data, local),
         :ok <- maybe_federate(activity) do
      {:ok, activity}
    end
  end

  def flag(
        %{
          actor: actor,
          context: context,
          account: account,
          statuses: statuses,
          content: content
        } = params
      ) do
    # only accept false as false value
    local = !(params[:local] == false)
    forward = !(params[:forward] == false)

    additional = params[:additional] || %{}

    params = %{
      actor: actor,
      context: context,
      account: account,
      statuses: statuses,
      content: content
    }

    additional =
      if forward do
        Map.merge(additional, %{"to" => [], "cc" => [account.ap_id]})
      else
        Map.merge(additional, %{"to" => [], "cc" => []})
      end

    with flag_data <- make_flag_data(params, additional),
         {:ok, activity} <- insert(flag_data, local),
         :ok <- maybe_federate(activity) do
      Enum.each(User.all_superusers(), fn superuser ->
        superuser
        |> Pleroma.Emails.AdminEmail.report(actor, account, statuses, content)
        |> Pleroma.Emails.Mailer.deliver_async()
      end)

      {:ok, activity}
    end
  end

  defp fetch_activities_for_context_query(context, opts) do
    public = ["https://www.w3.org/ns/activitystreams#Public"]

    recipients =
      if opts["user"], do: [opts["user"].ap_id | opts["user"].following] ++ public, else: public

    from(activity in Activity)
    |> restrict_blocked(opts)
    |> restrict_recipients(recipients, opts["user"])
    |> where(
      [activity],
      fragment(
        "?->>'type' = ? and ?->>'context' = ?",
        activity.data,
        "Create",
        activity.data,
        ^context
      )
    )
    |> order_by([activity], desc: activity.id)
  end

  @spec fetch_activities_for_context(String.t(), keyword() | map()) :: [Activity.t()]
  def fetch_activities_for_context(context, opts \\ %{}) do
    context
    |> fetch_activities_for_context_query(opts)
    |> Activity.with_preloaded_object()
    |> Repo.all()
  end

  @spec fetch_latest_activity_id_for_context(String.t(), keyword() | map()) ::
          Pleroma.FlakeId.t() | nil
  def fetch_latest_activity_id_for_context(context, opts \\ %{}) do
    context
    |> fetch_activities_for_context_query(opts)
    |> limit(1)
    |> select([a], a.id)
    |> Repo.one()
  end

  def fetch_public_activities(opts \\ %{}) do
    q = fetch_activities_query(["https://www.w3.org/ns/activitystreams#Public"], opts)

    q
    |> restrict_unlisted()
    |> Pagination.fetch_paginated(opts)
    |> Enum.reverse()
  end

  @valid_visibilities ~w[direct unlisted public private]

  defp restrict_visibility(query, %{visibility: visibility})
       when is_list(visibility) do
    if Enum.all?(visibility, &(&1 in @valid_visibilities)) do
      query =
        from(
          a in query,
          where:
            fragment(
              "activity_visibility(?, ?, ?) = ANY (?)",
              a.actor,
              a.recipients,
              a.data,
              ^visibility
            )
        )

      query
    else
      Logger.error("Could not restrict visibility to #{visibility}")
    end
  end

  defp restrict_visibility(query, %{visibility: visibility})
       when visibility in @valid_visibilities do
    query =
      from(
        a in query,
        where:
          fragment("activity_visibility(?, ?, ?) = ?", a.actor, a.recipients, a.data, ^visibility)
      )

    query
  end

  defp restrict_visibility(_query, %{visibility: visibility})
       when visibility not in @valid_visibilities do
    Logger.error("Could not restrict visibility to #{visibility}")
  end

  defp restrict_visibility(query, _visibility), do: query

  defp restrict_thread_visibility(query, %{"user" => %User{ap_id: ap_id}}) do
    query =
      from(
        a in query,
        where: fragment("thread_visibility(?, (?)->>'id') = true", ^ap_id, a.data)
      )

    query
  end

  defp restrict_thread_visibility(query, _), do: query

  def fetch_user_activities(user, reading_user, params \\ %{}) do
    params =
      params
      |> Map.put("type", ["Create", "Announce"])
      |> Map.put("actor_id", user.ap_id)
      |> Map.put("whole_db", true)
      |> Map.put("pinned_activity_ids", user.info.pinned_activities)

    recipients =
      if reading_user do
        ["https://www.w3.org/ns/activitystreams#Public"] ++
          [reading_user.ap_id | reading_user.following]
      else
        ["https://www.w3.org/ns/activitystreams#Public"]
      end

    fetch_activities(recipients, params)
    |> Enum.reverse()
  end

  defp restrict_since(query, %{"since_id" => ""}), do: query

  defp restrict_since(query, %{"since_id" => since_id}) do
    from(activity in query, where: activity.id > ^since_id)
  end

  defp restrict_since(query, _), do: query

  defp restrict_tag_reject(_query, %{"tag_reject" => _tag_reject, "skip_preload" => true}) do
    raise "Can't use the child object without preloading!"
  end

  defp restrict_tag_reject(query, %{"tag_reject" => tag_reject})
       when is_list(tag_reject) and tag_reject != [] do
    from(
      [_activity, object] in query,
      where: fragment("not (?)->'tag' \\?| (?)", object.data, ^tag_reject)
    )
  end

  defp restrict_tag_reject(query, _), do: query

  defp restrict_tag_all(_query, %{"tag_all" => _tag_all, "skip_preload" => true}) do
    raise "Can't use the child object without preloading!"
  end

  defp restrict_tag_all(query, %{"tag_all" => tag_all})
       when is_list(tag_all) and tag_all != [] do
    from(
      [_activity, object] in query,
      where: fragment("(?)->'tag' \\?& (?)", object.data, ^tag_all)
    )
  end

  defp restrict_tag_all(query, _), do: query

  defp restrict_tag(_query, %{"tag" => _tag, "skip_preload" => true}) do
    raise "Can't use the child object without preloading!"
  end

  defp restrict_tag(query, %{"tag" => tag}) when is_list(tag) do
    from(
      [_activity, object] in query,
      where: fragment("(?)->'tag' \\?| (?)", object.data, ^tag)
    )
  end

  defp restrict_tag(query, %{"tag" => tag}) when is_binary(tag) do
    from(
      [_activity, object] in query,
      where: fragment("(?)->'tag' \\? (?)", object.data, ^tag)
    )
  end

  defp restrict_tag(query, _), do: query

  defp restrict_to_cc(query, recipients_to, recipients_cc) do
    from(
      activity in query,
      where:
        fragment(
          "(?->'to' \\?| ?) or (?->'cc' \\?| ?)",
          activity.data,
          ^recipients_to,
          activity.data,
          ^recipients_cc
        )
    )
  end

  defp restrict_recipients(query, [], _user), do: query

  defp restrict_recipients(query, recipients, nil) do
    from(activity in query, where: fragment("? && ?", ^recipients, activity.recipients))
  end

  defp restrict_recipients(query, recipients, user) do
    from(
      activity in query,
      where: fragment("? && ?", ^recipients, activity.recipients),
      or_where: activity.actor == ^user.ap_id
    )
  end

  defp restrict_local(query, %{"local_only" => true}) do
    from(activity in query, where: activity.local == true)
  end

  defp restrict_local(query, _), do: query

  defp restrict_actor(query, %{"actor_id" => actor_id}) do
    from(activity in query, where: activity.actor == ^actor_id)
  end

  defp restrict_actor(query, _), do: query

  defp restrict_type(query, %{"type" => type}) when is_binary(type) do
    from(activity in query, where: fragment("?->>'type' = ?", activity.data, ^type))
  end

  defp restrict_type(query, %{"type" => type}) do
    from(activity in query, where: fragment("?->>'type' = ANY(?)", activity.data, ^type))
  end

  defp restrict_type(query, _), do: query

  defp restrict_state(query, %{"state" => state}) do
    from(activity in query, where: fragment("?->>'state' = ?", activity.data, ^state))
  end

  defp restrict_state(query, _), do: query

  defp restrict_favorited_by(query, %{"favorited_by" => ap_id}) do
    from(
      activity in query,
      where: fragment(~s(? <@ (? #> '{"object","likes"}'\)), ^ap_id, activity.data)
    )
  end

  defp restrict_favorited_by(query, _), do: query

  defp restrict_media(_query, %{"only_media" => _val, "skip_preload" => true}) do
    raise "Can't use the child object without preloading!"
  end

  defp restrict_media(query, %{"only_media" => val}) when val == "true" or val == "1" do
    from(
      [_activity, object] in query,
      where: fragment("not (?)->'attachment' = (?)", object.data, ^[])
    )
  end

  defp restrict_media(query, _), do: query

  defp restrict_replies(query, %{"exclude_replies" => val}) when val == "true" or val == "1" do
    from(
      activity in query,
      where: fragment("?->'object'->>'inReplyTo' is null", activity.data)
    )
  end

  defp restrict_replies(query, _), do: query

  defp restrict_reblogs(query, %{"exclude_reblogs" => val}) when val == "true" or val == "1" do
    from(activity in query, where: fragment("?->>'type' != 'Announce'", activity.data))
  end

  defp restrict_reblogs(query, _), do: query

  defp restrict_muted(query, %{"with_muted" => val}) when val in [true, "true", "1"], do: query

  defp restrict_muted(query, %{"muting_user" => %User{info: info}}) do
    mutes = info.mutes

    from(
      activity in query,
      where: fragment("not (? = ANY(?))", activity.actor, ^mutes),
      where: fragment("not (?->'to' \\?| ?)", activity.data, ^mutes)
    )
  end

  defp restrict_muted(query, _), do: query

  defp restrict_blocked(query, %{"blocking_user" => %User{info: info}}) do
    blocks = info.blocks || []
    domain_blocks = info.domain_blocks || []

    query =
      if has_named_binding?(query, :object), do: query, else: Activity.with_joined_object(query)

    from(
      [activity, object: o] in query,
      where: fragment("not (? = ANY(?))", activity.actor, ^blocks),
      where: fragment("not (? && ?)", activity.recipients, ^blocks),
      where:
        fragment(
          "not (?->>'type' = 'Announce' and ?->'to' \\?| ?)",
          activity.data,
          activity.data,
          ^blocks
        ),
      where: fragment("not (split_part(?, '/', 3) = ANY(?))", activity.actor, ^domain_blocks),
      where: fragment("not (split_part(?->>'actor', '/', 3) = ANY(?))", o.data, ^domain_blocks)
    )
  end

  defp restrict_blocked(query, _), do: query

  defp restrict_unlisted(query) do
    from(
      activity in query,
      where:
        fragment(
          "not (coalesce(?->'cc', '{}'::jsonb) \\?| ?)",
          activity.data,
          ^["https://www.w3.org/ns/activitystreams#Public"]
        )
    )
  end

  defp restrict_pinned(query, %{"pinned" => "true", "pinned_activity_ids" => ids}) do
    from(activity in query, where: activity.id in ^ids)
  end

  defp restrict_pinned(query, _), do: query

  defp restrict_muted_reblogs(query, %{"muting_user" => %User{info: info}}) do
    muted_reblogs = info.muted_reblogs || []

    from(
      activity in query,
      where:
        fragment(
          "not ( ?->>'type' = 'Announce' and ? = ANY(?))",
          activity.data,
          activity.actor,
          ^muted_reblogs
        )
    )
  end

  defp restrict_muted_reblogs(query, _), do: query

  defp maybe_preload_objects(query, %{"skip_preload" => true}), do: query

  defp maybe_preload_objects(query, _) do
    query
    |> Activity.with_preloaded_object()
  end

  defp maybe_preload_bookmarks(query, %{"skip_preload" => true}), do: query

  defp maybe_preload_bookmarks(query, opts) do
    query
    |> Activity.with_preloaded_bookmark(opts["user"])
  end

  defp maybe_order(query, %{order: :desc}) do
    query
    |> order_by(desc: :id)
  end

  defp maybe_order(query, %{order: :asc}) do
    query
    |> order_by(asc: :id)
  end

  defp maybe_order(query, _), do: query

  def fetch_activities_query(recipients, opts \\ %{}) do
    base_query = from(activity in Activity)

    base_query
    |> maybe_preload_objects(opts)
    |> maybe_preload_bookmarks(opts)
    |> maybe_order(opts)
    |> restrict_recipients(recipients, opts["user"])
    |> restrict_tag(opts)
    |> restrict_tag_reject(opts)
    |> restrict_tag_all(opts)
    |> restrict_since(opts)
    |> restrict_local(opts)
    |> restrict_actor(opts)
    |> restrict_type(opts)
    |> restrict_state(opts)
    |> restrict_favorited_by(opts)
    |> restrict_blocked(opts)
    |> restrict_muted(opts)
    |> restrict_media(opts)
    |> restrict_visibility(opts)
    |> restrict_thread_visibility(opts)
    |> restrict_replies(opts)
    |> restrict_reblogs(opts)
    |> restrict_pinned(opts)
    |> restrict_muted_reblogs(opts)
    |> Activity.restrict_deactivated_users()
  end

  def fetch_activities(recipients, opts \\ %{}) do
    fetch_activities_query(recipients, opts)
    |> Pagination.fetch_paginated(opts)
    |> Enum.reverse()
  end

  def fetch_activities_bounded(recipients_to, recipients_cc, opts \\ %{}) do
    fetch_activities_query([], opts)
    |> restrict_to_cc(recipients_to, recipients_cc)
    |> Pagination.fetch_paginated(opts)
    |> Enum.reverse()
  end

  def upload(file, opts \\ []) do
    with {:ok, data} <- Upload.store(file, opts) do
      obj_data =
        if opts[:actor] do
          Map.put(data, "actor", opts[:actor])
        else
          data
        end

      Repo.insert(%Object{data: obj_data})
    end
  end

  def user_data_from_user_object(data) do
    avatar =
      data["icon"]["url"] &&
        %{
          "type" => "Image",
          "url" => [%{"href" => data["icon"]["url"]}]
        }

    banner =
      data["image"]["url"] &&
        %{
          "type" => "Image",
          "url" => [%{"href" => data["image"]["url"]}]
        }

    locked = data["manuallyApprovesFollowers"] || false
    data = Transmogrifier.maybe_fix_user_object(data)

    user_data = %{
      ap_id: data["id"],
      info: %{
        "ap_enabled" => true,
        "source_data" => data,
        "banner" => banner,
        "locked" => locked
      },
      avatar: avatar,
      name: data["name"],
      follower_address: data["followers"],
      bio: data["summary"]
    }

    # nickname can be nil because of virtual actors
    user_data =
      if data["preferredUsername"] do
        Map.put(
          user_data,
          :nickname,
          "#{data["preferredUsername"]}@#{URI.parse(data["id"]).host}"
        )
      else
        Map.put(user_data, :nickname, nil)
      end

    {:ok, user_data}
  end

  def fetch_and_prepare_user_from_ap_id(ap_id) do
    with {:ok, data} <- Fetcher.fetch_and_contain_remote_object_from_id(ap_id) do
      user_data_from_user_object(data)
    else
      e -> Logger.error("Could not decode user at fetch #{ap_id}, #{inspect(e)}")
    end
  end

  def make_user_from_ap_id(ap_id) do
    if _user = User.get_cached_by_ap_id(ap_id) do
      Transmogrifier.upgrade_user_from_ap_id(ap_id)
    else
      with {:ok, data} <- fetch_and_prepare_user_from_ap_id(ap_id) do
        User.insert_or_update_user(data)
      else
        e -> {:error, e}
      end
    end
  end

  def make_user_from_nickname(nickname) do
    with {:ok, %{"ap_id" => ap_id}} when not is_nil(ap_id) <- WebFinger.finger(nickname) do
      make_user_from_ap_id(ap_id)
    else
      _e -> {:error, "No AP id in WebFinger"}
    end
  end

  # filter out broken threads
  def contain_broken_threads(%Activity{} = activity, %User{} = user) do
    entire_thread_visible_for_user?(activity, user)
  end

  # do post-processing on a specific activity
  def contain_activity(%Activity{} = activity, %User{} = user) do
    contain_broken_threads(activity, user)
  end

  def fetch_direct_messages_query do
    Activity
    |> restrict_type(%{"type" => "Create"})
    |> restrict_visibility(%{visibility: "direct"})
    |> order_by([activity], asc: activity.id)
  end
end
