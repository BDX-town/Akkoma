# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.CommonAPITest do
  use Pleroma.DataCase
  alias Pleroma.Activity
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory

  test "it de-duplicates tags" do
    user = insert(:user)
    {:ok, activity} = CommonAPI.post(user, %{"status" => "#2hu #2HU"})

    assert activity.data["object"]["tag"] == ["2hu"]
  end

  test "it adds emoji in the object" do
    user = insert(:user)
    {:ok, activity} = CommonAPI.post(user, %{"status" => ":moominmamma:"})

    assert activity.data["object"]["emoji"]["moominmamma"]
  end

  test "it adds emoji when updating profiles" do
    user = insert(:user, %{name: ":karjalanpiirakka:"})

    CommonAPI.update(user)
    user = User.get_cached_by_ap_id(user.ap_id)
    [karjalanpiirakka] = user.info.source_data["tag"]

    assert karjalanpiirakka["name"] == ":karjalanpiirakka:"
  end

  describe "posting" do
    test "it filters out obviously bad tags when accepting a post as HTML" do
      user = insert(:user)

      post = "<p><b>2hu</b></p><script>alert('xss')</script>"

      {:ok, activity} =
        CommonAPI.post(user, %{
          "status" => post,
          "content_type" => "text/html"
        })

      content = activity.data["object"]["content"]
      assert content == "<p><b>2hu</b></p>alert('xss')"
    end

    test "it filters out obviously bad tags when accepting a post as Markdown" do
      user = insert(:user)

      post = "<p><b>2hu</b></p><script>alert('xss')</script>"

      {:ok, activity} =
        CommonAPI.post(user, %{
          "status" => post,
          "content_type" => "text/markdown"
        })

      content = activity.data["object"]["content"]
      assert content == "<p><b>2hu</b></p>alert('xss')"
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
                 "object" => [^target_ap_id, ^activity_ap_id]
               }
             } = flag_activity
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

      assert Pleroma.User.showing_reblogs?(muter, muted) == false
    end

    test "remove a reblog mute", %{muter: muter, muted: muted} do
      {:ok, muter} = CommonAPI.hide_reblogs(muter, muted)
      {:ok, muter} = CommonAPI.show_reblogs(muter, muted)

      assert Pleroma.User.showing_reblogs?(muter, muted) == true
    end
  end
end
