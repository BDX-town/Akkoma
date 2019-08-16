# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.RelayTest do
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Relay

  import Pleroma.Factory

  test "gets an actor for the relay" do
    user = Relay.get_actor()
    assert user.ap_id == "#{Pleroma.Web.Endpoint.url()}/relay"
  end

  describe "follow/1" do
    test "returns errors when user not found" do
      assert Relay.follow("test-ap-id") == {:error, "Could not fetch by AP id"}
    end

    test "returns activity" do
      user = insert(:user)
      service_actor = Relay.get_actor()
      assert {:ok, %Activity{} = activity} = Relay.follow(user.ap_id)
      assert activity.actor == "#{Pleroma.Web.Endpoint.url()}/relay"
      assert user.ap_id in activity.recipients
      assert activity.data["type"] == "Follow"
      assert activity.data["actor"] == service_actor.ap_id
      assert activity.data["object"] == user.ap_id
    end
  end

  describe "unfollow/1" do
    test "returns errors when user not found" do
      assert Relay.unfollow("test-ap-id") == {:error, "Could not fetch by AP id"}
    end

    test "returns activity" do
      user = insert(:user)
      service_actor = Relay.get_actor()
      ActivityPub.follow(service_actor, user)
      assert {:ok, %Activity{} = activity} = Relay.unfollow(user.ap_id)
      assert activity.actor == "#{Pleroma.Web.Endpoint.url()}/relay"
      assert user.ap_id in activity.recipients
      assert activity.data["type"] == "Undo"
      assert activity.data["actor"] == service_actor.ap_id
      assert activity.data["to"] == [user.ap_id]
    end
  end

  describe "publish/1" do
    test "returns error when activity not `Create` type" do
      activity = insert(:like_activity)
      assert Relay.publish(activity) == {:error, "Not implemented"}
    end

    test "returns error when activity not public" do
      activity = insert(:direct_note_activity)
      assert Relay.publish(activity) == {:error, false}
    end

    test "returns announce activity" do
      service_actor = Relay.get_actor()
      note = insert(:note_activity)
      assert {:ok, %Activity{} = activity, %Object{} = obj} = Relay.publish(note)
      assert activity.data["type"] == "Announce"
      assert activity.data["actor"] == service_actor.ap_id
      assert activity.data["object"] == obj.data["id"]
    end
  end
end
