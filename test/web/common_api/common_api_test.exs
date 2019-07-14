# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.CommonAPITest do
  use Pleroma.DataCase
  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  test "with the safe_dm_mention option set, it does not mention people beyond the initial tags" do
    har = insert(:user)
    jafnhar = insert(:user)
    tridi = insert(:user)
    option = Pleroma.Config.get([:instance, :safe_dm_mentions])
    Pleroma.Config.put([:instance, :safe_dm_mentions], true)

    {:ok, activity} =
      CommonAPI.post(har, %{
        "status" => "@#{jafnhar.nickname} hey, i never want to see @#{tridi.nickname} again",
        "visibility" => "direct"
      })

    refute tridi.ap_id in activity.recipients
    assert jafnhar.ap_id in activity.recipients
    Pleroma.Config.put([:instance, :safe_dm_mentions], option)
  end

  test "it de-duplicates tags" do
    user = insert(:user)
    {:ok, activity} = CommonAPI.post(user, %{"status" => "#2hu #2HU"})

    object = Object.normalize(activity)

    assert object.data["tag"] == ["2hu"]
  end

  test "it adds emoji in the object" do
    user = insert(:user)
    {:ok, activity} = CommonAPI.post(user, %{"status" => ":firefox:"})

    assert Object.normalize(activity).data["emoji"]["firefox"]
  end

  test "it adds emoji when updating profiles" do
    user = insert(:user, %{name: ":firefox:"})

    CommonAPI.update(user)
    user = User.get_cached_by_ap_id(user.ap_id)
    [firefox] = user.info.source_data["tag"]

    assert firefox["name"] == ":firefox:"
  end

  describe "posting" do
    test "it supports explicit addressing" do
      user = insert(:user)
      user_two = insert(:user)
      user_three = insert(:user)
      user_four = insert(:user)

      {:ok, activity} =
        CommonAPI.post(user, %{
          "status" =>
            "Hey, I think @#{user_three.nickname} is ugly. @#{user_four.nickname} is alright though.",
          "to" => [user_two.nickname, user_four.nickname, "nonexistent"]
        })

      assert user.ap_id in activity.recipients
      assert user_two.ap_id in activity.recipients
      assert user_four.ap_id in activity.recipients
      refute user_three.ap_id in activity.recipients
    end

    test "it filters out obviously bad tags when accepting a post as HTML" do
      user = insert(:user)

      post = "<p><b>2hu</b></p><script>alert('xss')</script>"

      {:ok, activity} =
        CommonAPI.post(user, %{
          "status" => post,
          "content_type" => "text/html"
        })

      object = Object.normalize(activity)

      assert object.data["content"] == "<p><b>2hu</b></p>alert('xss')"
    end

    test "it filters out obviously bad tags when accepting a post as Markdown" do
      user = insert(:user)

      post = "<p><b>2hu</b></p><script>alert('xss')</script>"

      {:ok, activity} =
        CommonAPI.post(user, %{
          "status" => post,
          "content_type" => "text/markdown"
        })

      object = Object.normalize(activity)

      assert object.data["content"] == "<p><b>2hu</b></p>alert('xss')"
    end

    test "it does not allow replies to direct messages that are not direct messages themselves" do
      user = insert(:user)

      {:ok, activity} = CommonAPI.post(user, %{"status" => "suya..", "visibility" => "direct"})

      assert {:ok, _} =
               CommonAPI.post(user, %{
                 "status" => "suya..",
                 "visibility" => "direct",
                 "in_reply_to_status_id" => activity.id
               })

      Enum.each(["public", "private", "unlisted"], fn visibility ->
        assert {:error, "The message visibility must be direct"} =
                 CommonAPI.post(user, %{
                   "status" => "suya..",
                   "visibility" => visibility,
                   "in_reply_to_status_id" => activity.id
                 })
      end)
    end
  end

  describe "reactions" do
    test "repeating a status" do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} = CommonAPI.post(other_user, %{"status" => "cofe"})

      {:ok, %Activity{}, _} = CommonAPI.repeat(activity.id, user)
    end

    test "favoriting a status" do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} = CommonAPI.post(other_user, %{"status" => "cofe"})

      {:ok, %Activity{}, _} = CommonAPI.favorite(activity.id, user)
    end

    test "retweeting a status twice returns an error" do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} = CommonAPI.post(other_user, %{"status" => "cofe"})
      {:ok, %Activity{}, _object} = CommonAPI.repeat(activity.id, user)
      {:error, _} = CommonAPI.repeat(activity.id, user)
    end

    test "favoriting a status twice returns an error" do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} = CommonAPI.post(other_user, %{"status" => "cofe"})
      {:ok, %Activity{}, _object} = CommonAPI.favorite(activity.id, user)
      {:error, _} = CommonAPI.favorite(activity.id, user)
    end
  end

  describe "pinned statuses" do
    setup do
      Pleroma.Config.put([:instance, :max_pinned_statuses], 1)

      user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{"status" => "HI!!!"})

      [user: user, activity: activity]
    end

    test "pin status", %{user: user, activity: activity} do
      assert {:ok, ^activity} = CommonAPI.pin(activity.id, user)

      id = activity.id
      user = refresh_record(user)

      assert %User{info: %{pinned_activities: [^id]}} = user
    end

    test "unlisted statuses can be pinned", %{user: user} do
      {:ok, activity} = CommonAPI.post(user, %{"status" => "HI!!!", "visibility" => "unlisted"})
      assert {:ok, ^activity} = CommonAPI.pin(activity.id, user)
    end

    test "only self-authored can be pinned", %{activity: activity} do
      user = insert(:user)

      assert {:error, "Could not pin"} = CommonAPI.pin(activity.id, user)
    end

    test "max pinned statuses", %{user: user, activity: activity_one} do
      {:ok, activity_two} = CommonAPI.post(user, %{"status" => "HI!!!"})

      assert {:ok, ^activity_one} = CommonAPI.pin(activity_one.id, user)

      user = refresh_record(user)

      assert {:error, "You have already pinned the maximum number of statuses"} =
               CommonAPI.pin(activity_two.id, user)
    end

    test "unpin status", %{user: user, activity: activity} do
      {:ok, activity} = CommonAPI.pin(activity.id, user)

      user = refresh_record(user)

      assert {:ok, ^activity} = CommonAPI.unpin(activity.id, user)

      user = refresh_record(user)

      assert %User{info: %{pinned_activities: []}} = user
    end

    test "should unpin when deleting a status", %{user: user, activity: activity} do
      {:ok, activity} = CommonAPI.pin(activity.id, user)

      user = refresh_record(user)

      assert {:ok, _} = CommonAPI.delete(activity.id, user)

      user = refresh_record(user)

      assert %User{info: %{pinned_activities: []}} = user
    end
  end

  describe "mute tests" do
    setup do
      user = insert(:user)

      activity = insert(:note_activity)

      [user: user, activity: activity]
    end

    test "add mute", %{user: user, activity: activity} do
      {:ok, _} = CommonAPI.add_mute(user, activity)
      assert CommonAPI.thread_muted?(user, activity)
    end

    test "remove mute", %{user: user, activity: activity} do
      CommonAPI.add_mute(user, activity)
      {:ok, _} = CommonAPI.remove_mute(user, activity)
      refute CommonAPI.thread_muted?(user, activity)
    end

    test "check that mutes can't be duplicate", %{user: user, activity: activity} do
      CommonAPI.add_mute(user, activity)
      {:error, _} = CommonAPI.add_mute(user, activity)
    end
  end

  describe "reports" do
    test "creates a report" do
      reporter = insert(:user)
      target_user = insert(:user)

      {:ok, activity} = CommonAPI.post(target_user, %{"status" => "foobar"})

      reporter_ap_id = reporter.ap_id
      target_ap_id = target_user.ap_id
      activity_ap_id = activity.data["id"]
      comment = "foobar"

      report_data = %{
        "account_id" => target_user.id,
        "comment" => comment,
        "status_ids" => [activity.id]
      }

      assert {:ok, flag_activity} = CommonAPI.report(reporter, report_data)

      assert %Activity{
               actor: ^reporter_ap_id,
               data: %{
                 "type" => "Flag",
                 "content" => ^comment,
                 "object" => [^target_ap_id, ^activity_ap_id],
                 "state" => "open"
               }
             } = flag_activity
    end

    test "updates report state" do
      [reporter, target_user] = insert_pair(:user)
      activity = insert(:note_activity, user: target_user)

      {:ok, %Activity{id: report_id}} =
        CommonAPI.report(reporter, %{
          "account_id" => target_user.id,
          "comment" => "I feel offended",
          "status_ids" => [activity.id]
        })

      {:ok, report} = CommonAPI.update_report_state(report_id, "resolved")

      assert report.data["state"] == "resolved"
    end

    test "does not update report state when state is unsupported" do
      [reporter, target_user] = insert_pair(:user)
      activity = insert(:note_activity, user: target_user)

      {:ok, %Activity{id: report_id}} =
        CommonAPI.report(reporter, %{
          "account_id" => target_user.id,
          "comment" => "I feel offended",
          "status_ids" => [activity.id]
        })

      assert CommonAPI.update_report_state(report_id, "test") == {:error, "Unsupported state"}
    end
  end

  describe "reblog muting" do
    setup do
      muter = insert(:user)

      muted = insert(:user)

      [muter: muter, muted: muted]
    end

    test "add a reblog mute", %{muter: muter, muted: muted} do
      {:ok, muter} = CommonAPI.hide_reblogs(muter, muted)

      assert User.showing_reblogs?(muter, muted) == false
    end

    test "remove a reblog mute", %{muter: muter, muted: muted} do
      {:ok, muter} = CommonAPI.hide_reblogs(muter, muted)
      {:ok, muter} = CommonAPI.show_reblogs(muter, muted)

      assert User.showing_reblogs?(muter, muted) == true
    end
  end

  describe "unfollow/2" do
    test "also unsubscribes a user" do
      [follower, followed] = insert_pair(:user)
      {:ok, follower, followed, _} = CommonAPI.follow(follower, followed)
      {:ok, followed} = User.subscribe(follower, followed)

      assert User.subscribed_to?(follower, followed)

      {:ok, follower} = CommonAPI.unfollow(follower, followed)

      refute User.subscribed_to?(follower, followed)
    end
  end

  describe "accept_follow_request/2" do
    test "after acceptance, it sets all existing pending follow request states to 'accept'" do
      user = insert(:user, info: %{locked: true})
      follower = insert(:user)
      follower_two = insert(:user)

      {:ok, follow_activity} = ActivityPub.follow(follower, user)
      {:ok, follow_activity_two} = ActivityPub.follow(follower, user)
      {:ok, follow_activity_three} = ActivityPub.follow(follower_two, user)

      assert follow_activity.data["state"] == "pending"
      assert follow_activity_two.data["state"] == "pending"
      assert follow_activity_three.data["state"] == "pending"

      {:ok, _follower} = CommonAPI.accept_follow_request(follower, user)

      assert Repo.get(Activity, follow_activity.id).data["state"] == "accept"
      assert Repo.get(Activity, follow_activity_two.id).data["state"] == "accept"
      assert Repo.get(Activity, follow_activity_three.id).data["state"] == "pending"
    end

    test "after rejection, it sets all existing pending follow request states to 'reject'" do
      user = insert(:user, info: %{locked: true})
      follower = insert(:user)
      follower_two = insert(:user)

      {:ok, follow_activity} = ActivityPub.follow(follower, user)
      {:ok, follow_activity_two} = ActivityPub.follow(follower, user)
      {:ok, follow_activity_three} = ActivityPub.follow(follower_two, user)

      assert follow_activity.data["state"] == "pending"
      assert follow_activity_two.data["state"] == "pending"
      assert follow_activity_three.data["state"] == "pending"

      {:ok, _follower} = CommonAPI.reject_follow_request(follower, user)

      assert Repo.get(Activity, follow_activity.id).data["state"] == "reject"
      assert Repo.get(Activity, follow_activity_two.id).data["state"] == "reject"
      assert Repo.get(Activity, follow_activity_three.id).data["state"] == "pending"
    end
  end
end
