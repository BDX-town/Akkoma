# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.CommonAPI do
  alias Pleroma.Activity
  alias Pleroma.Bookmark
  alias Pleroma.Formatter
  alias Pleroma.Object
  alias Pleroma.ThreadMute
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Utils

  import Pleroma.Web.CommonAPI.Utils

  def follow(follower, followed) do
    with {:ok, follower} <- User.maybe_direct_follow(follower, followed),
         {:ok, activity} <- ActivityPub.follow(follower, followed),
         {:ok, follower, followed} <-
           User.wait_and_refresh(
             Pleroma.Config.get([:activitypub, :follow_handshake_timeout]),
             follower,
             followed
           ) do
      {:ok, follower, followed, activity}
    end
  end

  def unfollow(follower, unfollowed) do
    with {:ok, follower, _follow_activity} <- User.unfollow(follower, unfollowed),
         {:ok, _activity} <- ActivityPub.unfollow(follower, unfollowed) do
      {:ok, follower}
    end
  end

  def accept_follow_request(follower, followed) do
    with {:ok, follower} <- User.maybe_follow(follower, followed),
         %Activity{} = follow_activity <- Utils.fetch_latest_follow(follower, followed),
         {:ok, follow_activity} <- Utils.update_follow_state(follow_activity, "accept"),
         {:ok, _activity} <-
           ActivityPub.accept(%{
             to: [follower.ap_id],
             actor: followed,
             object: follow_activity.data["id"],
             type: "Accept"
           }) do
      {:ok, follower}
    end
  end

  def reject_follow_request(follower, followed) do
    with %Activity{} = follow_activity <- Utils.fetch_latest_follow(follower, followed),
         {:ok, follow_activity} <- Utils.update_follow_state(follow_activity, "reject"),
         {:ok, _activity} <-
           ActivityPub.reject(%{
             to: [follower.ap_id],
             actor: followed,
             object: follow_activity.data["id"],
             type: "Reject"
           }) do
      {:ok, follower}
    end
  end

  def delete(activity_id, user) do
    with %Activity{data: %{"object" => _}} = activity <-
           Activity.get_by_id_with_object(activity_id),
         %Object{} = object <- Object.normalize(activity),
         true <- User.superuser?(user) || user.ap_id == object.data["actor"],
         {:ok, _} <- unpin(activity_id, user),
         {:ok, delete} <- ActivityPub.delete(object) do
      {:ok, delete}
    end
  end

  def repeat(id_or_ap_id, user) do
    with %Activity{} = activity <- get_by_id_or_ap_id(id_or_ap_id),
         object <- Object.normalize(activity),
         nil <- Utils.get_existing_announce(user.ap_id, object) do
      ActivityPub.announce(user, object)
    else
      _ ->
        {:error, "Could not repeat"}
    end
  end

  def unrepeat(id_or_ap_id, user) do
    with %Activity{} = activity <- get_by_id_or_ap_id(id_or_ap_id),
         object <- Object.normalize(activity) do
      ActivityPub.unannounce(user, object)
    else
      _ ->
        {:error, "Could not unrepeat"}
    end
  end

  def favorite(id_or_ap_id, user) do
    with %Activity{} = activity <- get_by_id_or_ap_id(id_or_ap_id),
         object <- Object.normalize(activity),
         nil <- Utils.get_existing_like(user.ap_id, object) do
      ActivityPub.like(user, object)
    else
      _ ->
        {:error, "Could not favorite"}
    end
  end

  def unfavorite(id_or_ap_id, user) do
    with %Activity{} = activity <- get_by_id_or_ap_id(id_or_ap_id),
         object <- Object.normalize(activity) do
      ActivityPub.unlike(user, object)
    else
      _ ->
        {:error, "Could not unfavorite"}
    end
  end

  def get_visibility(%{"visibility" => visibility})
      when visibility in ~w{public unlisted private direct},
      do: visibility

  def get_visibility(%{"in_reply_to_status_id" => status_id}) when not is_nil(status_id) do
    case get_replied_to_activity(status_id) do
      nil ->
        "public"

      in_reply_to ->
        # XXX: these heuristics should be moved out of MastodonAPI.
        with %Object{} = object <- Object.normalize(in_reply_to) do
          Pleroma.Web.MastodonAPI.StatusView.get_visibility(object)
        end
    end
  end

  def get_visibility(_), do: "public"

  def post(user, %{"status" => status} = data) do
    visibility = get_visibility(data)
    limit = Pleroma.Config.get([:instance, :limit])

    with status <- String.trim(status),
         attachments <- attachments_from_ids(data),
         in_reply_to <- get_replied_to_activity(data["in_reply_to_status_id"]),
         {content_html, mentions, tags} <-
           make_content_html(
             status,
             attachments,
             data,
             visibility
           ),
         {to, cc} <- to_for_user_and_mentions(user, mentions, in_reply_to, visibility),
         context <- make_context(in_reply_to),
         cw <- data["spoiler_text"] || "",
         full_payload <- String.trim(status <> cw),
         length when length in 1..limit <- String.length(full_payload),
         object <-
           make_note_data(
             user.ap_id,
             to,
             context,
             content_html,
             attachments,
             in_reply_to,
             tags,
             cw,
             cc
           ),
         object <-
           Map.put(
             object,
             "emoji",
             Formatter.get_emoji_map(full_payload)
           ) do
      res =
        ActivityPub.create(
          %{
            to: to,
            actor: user,
            context: context,
            object: object,
            additional: %{"cc" => cc, "directMessage" => visibility == "direct"}
          },
          Pleroma.Web.ControllerHelper.truthy_param?(data["preview"]) || false
        )

      res
    end
  end

  # Updates the emojis for a user based on their profile
  def update(user) do
    user =
      with emoji <- emoji_from_profile(user),
           source_data <- (user.info.source_data || %{}) |> Map.put("tag", emoji),
           info_cng <- Pleroma.User.Info.set_source_data(user.info, source_data),
           change <- Ecto.Changeset.change(user) |> Ecto.Changeset.put_embed(:info, info_cng),
           {:ok, user} <- User.update_and_set_cache(change) do
        user
      else
        _e ->
          user
      end

    ActivityPub.update(%{
      local: true,
      to: [user.follower_address],
      cc: [],
      actor: user.ap_id,
      object: Pleroma.Web.ActivityPub.UserView.render("user.json", %{user: user})
    })
  end

  def pin(id_or_ap_id, %{ap_id: user_ap_id} = user) do
    with %Activity{
           actor: ^user_ap_id,
           data: %{
             "type" => "Create"
           },
           object: %Object{
             data: %{
               "to" => object_to,
               "type" => "Note"
             }
           }
         } = activity <- get_by_id_or_ap_id(id_or_ap_id),
         true <- Enum.member?(object_to, "https://www.w3.org/ns/activitystreams#Public"),
         %{valid?: true} = info_changeset <-
           Pleroma.User.Info.add_pinnned_activity(user.info, activity),
         changeset <-
           Ecto.Changeset.change(user) |> Ecto.Changeset.put_embed(:info, info_changeset),
         {:ok, _user} <- User.update_and_set_cache(changeset) do
      {:ok, activity}
    else
      %{errors: [pinned_activities: {err, _}]} ->
        {:error, err}

      _ ->
        {:error, "Could not pin"}
    end
  end

  def unpin(id_or_ap_id, user) do
    with %Activity{} = activity <- get_by_id_or_ap_id(id_or_ap_id),
         %{valid?: true} = info_changeset <-
           Pleroma.User.Info.remove_pinnned_activity(user.info, activity),
         changeset <-
           Ecto.Changeset.change(user) |> Ecto.Changeset.put_embed(:info, info_changeset),
         {:ok, _user} <- User.update_and_set_cache(changeset) do
      {:ok, activity}
    else
      %{errors: [pinned_activities: {err, _}]} ->
        {:error, err}

      _ ->
        {:error, "Could not unpin"}
    end
  end

  def add_mute(user, activity) do
    with {:ok, _} <- ThreadMute.add_mute(user.id, activity.data["context"]) do
      {:ok, activity}
    else
      {:error, _} -> {:error, "conversation is already muted"}
    end
  end

  def remove_mute(user, activity) do
    ThreadMute.remove_mute(user.id, activity.data["context"])
    {:ok, activity}
  end

  def thread_muted?(%{id: nil} = _user, _activity), do: false

  def thread_muted?(user, activity) do
    with [] <- ThreadMute.check_muted(user.id, activity.data["context"]) do
      false
    else
      _ -> true
    end
  end

  def bookmarked?(user, activity) do
    with %Bookmark{} <- Bookmark.get(user.id, activity.id) do
      true
    else
      _ ->
        false
    end
  end

  def report(user, data) do
    with {:account_id, %{"account_id" => account_id}} <- {:account_id, data},
         {:account, %User{} = account} <- {:account, User.get_cached_by_id(account_id)},
         {:ok, {content_html, _, _}} <- make_report_content_html(data["comment"]),
         {:ok, statuses} <- get_report_statuses(account, data),
         {:ok, activity} <-
           ActivityPub.flag(%{
             context: Utils.generate_context_id(),
             actor: user,
             account: account,
             statuses: statuses,
             content: content_html,
             forward: data["forward"] || false
           }) do
      {:ok, activity}
    else
      {:error, err} -> {:error, err}
      {:account_id, %{}} -> {:error, "Valid `account_id` required"}
      {:account, nil} -> {:error, "Account not found"}
    end
  end

  def hide_reblogs(user, muted) do
    ap_id = muted.ap_id

    if ap_id not in user.info.muted_reblogs do
      info_changeset = User.Info.add_reblog_mute(user.info, ap_id)
      changeset = Ecto.Changeset.change(user) |> Ecto.Changeset.put_embed(:info, info_changeset)
      User.update_and_set_cache(changeset)
    end
  end

  def show_reblogs(user, muted) do
    ap_id = muted.ap_id

    if ap_id in user.info.muted_reblogs do
      info_changeset = User.Info.remove_reblog_mute(user.info, ap_id)
      changeset = Ecto.Changeset.change(user) |> Ecto.Changeset.put_embed(:info, info_changeset)
      User.update_and_set_cache(changeset)
    end
  end
end
