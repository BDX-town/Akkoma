# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.MastodonAPIControllerTest do
  use Pleroma.Web.ConnCase

  alias Ecto.Changeset
  alias Pleroma.Activity
  alias Pleroma.Notification
  alias Pleroma.Object
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.MastodonAPI.FilterView
  alias Pleroma.Web.OAuth.App
  alias Pleroma.Web.OStatus
  alias Pleroma.Web.Push
  alias Pleroma.Web.TwitterAPI.TwitterAPI
  import Pleroma.Factory
  import ExUnit.CaptureLog
  import Tesla.Mock

  setup do
    mock(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  test "the home timeline", %{conn: conn} do
    user = insert(:user)
    following = insert(:user)

    {:ok, _activity} = TwitterAPI.create_status(following, %{"status" => "test"})

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/timelines/home")

    assert Enum.empty?(json_response(conn, 200))

    {:ok, user} = User.follow(user, following)

    conn =
      build_conn()
      |> assign(:user, user)
      |> get("/api/v1/timelines/home")

    assert [%{"content" => "test"}] = json_response(conn, 200)
  end

  test "the public timeline", %{conn: conn} do
    following = insert(:user)

    capture_log(fn ->
      {:ok, _activity} = TwitterAPI.create_status(following, %{"status" => "test"})

      {:ok, [_activity]} =
        OStatus.fetch_activity_from_url("https://shitposter.club/notice/2827873")

      conn =
        conn
        |> get("/api/v1/timelines/public", %{"local" => "False"})

      assert length(json_response(conn, 200)) == 2

      conn =
        build_conn()
        |> get("/api/v1/timelines/public", %{"local" => "True"})

      assert [%{"content" => "test"}] = json_response(conn, 200)

      conn =
        build_conn()
        |> get("/api/v1/timelines/public", %{"local" => "1"})

      assert [%{"content" => "test"}] = json_response(conn, 200)
    end)
  end

  test "posting a status", %{conn: conn} do
    user = insert(:user)

    idempotency_key = "Pikachu rocks!"

    conn_one =
      conn
      |> assign(:user, user)
      |> put_req_header("idempotency-key", idempotency_key)
      |> post("/api/v1/statuses", %{
        "status" => "cofe",
        "spoiler_text" => "2hu",
        "sensitive" => "false"
      })

    {:ok, ttl} = Cachex.ttl(:idempotency_cache, idempotency_key)
    # Six hours
    assert ttl > :timer.seconds(6 * 60 * 60 - 1)

    assert %{"content" => "cofe", "id" => id, "spoiler_text" => "2hu", "sensitive" => false} =
             json_response(conn_one, 200)

    assert Repo.get(Activity, id)

    conn_two =
      conn
      |> assign(:user, user)
      |> put_req_header("idempotency-key", idempotency_key)
      |> post("/api/v1/statuses", %{
        "status" => "cofe",
        "spoiler_text" => "2hu",
        "sensitive" => "false"
      })

    assert %{"id" => second_id} = json_response(conn_two, 200)

    assert id == second_id

    conn_three =
      conn
      |> assign(:user, user)
      |> post("/api/v1/statuses", %{
        "status" => "cofe",
        "spoiler_text" => "2hu",
        "sensitive" => "false"
      })

    assert %{"id" => third_id} = json_response(conn_three, 200)

    refute id == third_id
  end

  test "posting a sensitive status", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/statuses", %{"status" => "cofe", "sensitive" => true})

    assert %{"content" => "cofe", "id" => id, "sensitive" => true} = json_response(conn, 200)
    assert Repo.get(Activity, id)
  end

  test "posting a status with OGP link preview", %{conn: conn} do
    Pleroma.Config.put([:rich_media, :enabled], true)
    user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/statuses", %{
        "status" => "http://example.com/ogp"
      })

    assert %{"id" => id, "card" => %{"title" => "The Rock"}} = json_response(conn, 200)
    assert Repo.get(Activity, id)
    Pleroma.Config.put([:rich_media, :enabled], false)
  end

  test "posting a direct status", %{conn: conn} do
    user1 = insert(:user)
    user2 = insert(:user)
    content = "direct cofe @#{user2.nickname}"

    conn =
      conn
      |> assign(:user, user1)
      |> post("api/v1/statuses", %{"status" => content, "visibility" => "direct"})

    assert %{"id" => id, "visibility" => "direct"} = json_response(conn, 200)
    assert activity = Repo.get(Activity, id)
    assert activity.recipients == [user2.ap_id, user1.ap_id]
    assert activity.data["to"] == [user2.ap_id]
    assert activity.data["cc"] == []
  end

  test "direct timeline", %{conn: conn} do
    user_one = insert(:user)
    user_two = insert(:user)

    {:ok, user_two} = User.follow(user_two, user_one)

    {:ok, direct} =
      CommonAPI.post(user_one, %{
        "status" => "Hi @#{user_two.nickname}!",
        "visibility" => "direct"
      })

    {:ok, _follower_only} =
      CommonAPI.post(user_one, %{
        "status" => "Hi @#{user_two.nickname}!",
        "visibility" => "private"
      })

    # Only direct should be visible here
    res_conn =
      conn
      |> assign(:user, user_two)
      |> get("api/v1/timelines/direct")

    [status] = json_response(res_conn, 200)

    assert %{"visibility" => "direct"} = status
    assert status["url"] != direct.data["id"]

    # User should be able to see his own direct message
    res_conn =
      build_conn()
      |> assign(:user, user_one)
      |> get("api/v1/timelines/direct")

    [status] = json_response(res_conn, 200)

    assert %{"visibility" => "direct"} = status

    # Both should be visible here
    res_conn =
      conn
      |> assign(:user, user_two)
      |> get("api/v1/timelines/home")

    [_s1, _s2] = json_response(res_conn, 200)

    # Test pagination
    Enum.each(1..20, fn _ ->
      {:ok, _} =
        CommonAPI.post(user_one, %{
          "status" => "Hi @#{user_two.nickname}!",
          "visibility" => "direct"
        })
    end)

    res_conn =
      conn
      |> assign(:user, user_two)
      |> get("api/v1/timelines/direct")

    statuses = json_response(res_conn, 200)
    assert length(statuses) == 20

    res_conn =
      conn
      |> assign(:user, user_two)
      |> get("api/v1/timelines/direct", %{max_id: List.last(statuses)["id"]})

    [status] = json_response(res_conn, 200)

    assert status["url"] != direct.data["id"]
  end

  test "doesn't include DMs from blocked users", %{conn: conn} do
    blocker = insert(:user)
    blocked = insert(:user)
    user = insert(:user)
    {:ok, blocker} = User.block(blocker, blocked)

    {:ok, _blocked_direct} =
      CommonAPI.post(blocked, %{
        "status" => "Hi @#{blocker.nickname}!",
        "visibility" => "direct"
      })

    {:ok, direct} =
      CommonAPI.post(user, %{
        "status" => "Hi @#{blocker.nickname}!",
        "visibility" => "direct"
      })

    res_conn =
      conn
      |> assign(:user, user)
      |> get("api/v1/timelines/direct")

    [status] = json_response(res_conn, 200)
    assert status["id"] == direct.id
  end

  test "replying to a status", %{conn: conn} do
    user = insert(:user)

    {:ok, replied_to} = TwitterAPI.create_status(user, %{"status" => "cofe"})

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/statuses", %{"status" => "xD", "in_reply_to_id" => replied_to.id})

    assert %{"content" => "xD", "id" => id} = json_response(conn, 200)

    activity = Repo.get(Activity, id)

    assert activity.data["context"] == replied_to.data["context"]
    assert activity.data["object"]["inReplyToStatusId"] == replied_to.id
  end

  test "posting a status with an invalid in_reply_to_id", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/statuses", %{"status" => "xD", "in_reply_to_id" => ""})

    assert %{"content" => "xD", "id" => id} = json_response(conn, 200)

    activity = Repo.get(Activity, id)

    assert activity
  end

  test "verify_credentials", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/accounts/verify_credentials")

    assert %{"id" => id, "source" => %{"privacy" => "public"}} = json_response(conn, 200)
    assert id == to_string(user.id)
  end

  test "verify_credentials default scope unlisted", %{conn: conn} do
    user = insert(:user, %{info: %Pleroma.User.Info{default_scope: "unlisted"}})

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/accounts/verify_credentials")

    assert %{"id" => id, "source" => %{"privacy" => "unlisted"}} = json_response(conn, 200)
    assert id == to_string(user.id)
  end

  test "apps/verify_credentials", %{conn: conn} do
    token = insert(:oauth_token)

    conn =
      conn
      |> assign(:user, token.user)
      |> assign(:token, token)
      |> get("/api/v1/apps/verify_credentials")

    app = Repo.preload(token, :app).app

    expected = %{
      "name" => app.client_name,
      "website" => app.website,
      "vapid_key" => Push.vapid_config() |> Keyword.get(:public_key)
    }

    assert expected == json_response(conn, 200)
  end

  test "creates an oauth app", %{conn: conn} do
    user = insert(:user)
    app_attrs = build(:oauth_app)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/apps", %{
        client_name: app_attrs.client_name,
        redirect_uris: app_attrs.redirect_uris
      })

    [app] = Repo.all(App)

    expected = %{
      "name" => app.client_name,
      "website" => app.website,
      "client_id" => app.client_id,
      "client_secret" => app.client_secret,
      "id" => app.id |> to_string(),
      "redirect_uri" => app.redirect_uris,
      "vapid_key" => Push.vapid_config() |> Keyword.get(:public_key)
    }

    assert expected == json_response(conn, 200)
  end

  test "get a status", %{conn: conn} do
    activity = insert(:note_activity)

    conn =
      conn
      |> get("/api/v1/statuses/#{activity.id}")

    assert %{"id" => id} = json_response(conn, 200)
    assert id == to_string(activity.id)
  end

  describe "deleting a status" do
    test "when you created it", %{conn: conn} do
      activity = insert(:note_activity)
      author = User.get_by_ap_id(activity.data["actor"])

      conn =
        conn
        |> assign(:user, author)
        |> delete("/api/v1/statuses/#{activity.id}")

      assert %{} = json_response(conn, 200)

      refute Repo.get(Activity, activity.id)
    end

    test "when you didn't create it", %{conn: conn} do
      activity = insert(:note_activity)
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> delete("/api/v1/statuses/#{activity.id}")

      assert %{"error" => _} = json_response(conn, 403)

      assert Repo.get(Activity, activity.id) == activity
    end

    test "when you're an admin or moderator", %{conn: conn} do
      activity1 = insert(:note_activity)
      activity2 = insert(:note_activity)
      admin = insert(:user, info: %{is_admin: true})
      moderator = insert(:user, info: %{is_moderator: true})

      res_conn =
        conn
        |> assign(:user, admin)
        |> delete("/api/v1/statuses/#{activity1.id}")

      assert %{} = json_response(res_conn, 200)

      res_conn =
        conn
        |> assign(:user, moderator)
        |> delete("/api/v1/statuses/#{activity2.id}")

      assert %{} = json_response(res_conn, 200)

      refute Repo.get(Activity, activity1.id)
      refute Repo.get(Activity, activity2.id)
    end
  end

  describe "filters" do
    test "creating a filter", %{conn: conn} do
      user = insert(:user)

      filter = %Pleroma.Filter{
        phrase: "knights",
        context: ["home"]
      }

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/filters", %{"phrase" => filter.phrase, context: filter.context})

      assert response = json_response(conn, 200)
      assert response["phrase"] == filter.phrase
      assert response["context"] == filter.context
      assert response["id"] != nil
      assert response["id"] != ""
    end

    test "fetching a list of filters", %{conn: conn} do
      user = insert(:user)

      query_one = %Pleroma.Filter{
        user_id: user.id,
        filter_id: 1,
        phrase: "knights",
        context: ["home"]
      }

      query_two = %Pleroma.Filter{
        user_id: user.id,
        filter_id: 2,
        phrase: "who",
        context: ["home"]
      }

      {:ok, filter_one} = Pleroma.Filter.create(query_one)
      {:ok, filter_two} = Pleroma.Filter.create(query_two)

      response =
        conn
        |> assign(:user, user)
        |> get("/api/v1/filters")
        |> json_response(200)

      assert response ==
               render_json(
                 FilterView,
                 "filters.json",
                 filters: [filter_two, filter_one]
               )
    end

    test "get a filter", %{conn: conn} do
      user = insert(:user)

      query = %Pleroma.Filter{
        user_id: user.id,
        filter_id: 2,
        phrase: "knight",
        context: ["home"]
      }

      {:ok, filter} = Pleroma.Filter.create(query)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/filters/#{filter.filter_id}")

      assert _response = json_response(conn, 200)
    end

    test "update a filter", %{conn: conn} do
      user = insert(:user)

      query = %Pleroma.Filter{
        user_id: user.id,
        filter_id: 2,
        phrase: "knight",
        context: ["home"]
      }

      {:ok, _filter} = Pleroma.Filter.create(query)

      new = %Pleroma.Filter{
        phrase: "nii",
        context: ["home"]
      }

      conn =
        conn
        |> assign(:user, user)
        |> put("/api/v1/filters/#{query.filter_id}", %{
          phrase: new.phrase,
          context: new.context
        })

      assert response = json_response(conn, 200)
      assert response["phrase"] == new.phrase
      assert response["context"] == new.context
    end

    test "delete a filter", %{conn: conn} do
      user = insert(:user)

      query = %Pleroma.Filter{
        user_id: user.id,
        filter_id: 2,
        phrase: "knight",
        context: ["home"]
      }

      {:ok, filter} = Pleroma.Filter.create(query)

      conn =
        conn
        |> assign(:user, user)
        |> delete("/api/v1/filters/#{filter.filter_id}")

      assert response = json_response(conn, 200)
      assert response == %{}
    end
  end

  describe "lists" do
    test "creating a list", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/lists", %{"title" => "cuties"})

      assert %{"title" => title} = json_response(conn, 200)
      assert title == "cuties"
    end

    test "adding users to a list", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)
      {:ok, list} = Pleroma.List.create("name", user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/lists/#{list.id}/accounts", %{"account_ids" => [other_user.id]})

      assert %{} == json_response(conn, 200)
      %Pleroma.List{following: following} = Pleroma.List.get(list.id, user)
      assert following == [other_user.follower_address]
    end

    test "removing users from a list", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)
      third_user = insert(:user)
      {:ok, list} = Pleroma.List.create("name", user)
      {:ok, list} = Pleroma.List.follow(list, other_user)
      {:ok, list} = Pleroma.List.follow(list, third_user)

      conn =
        conn
        |> assign(:user, user)
        |> delete("/api/v1/lists/#{list.id}/accounts", %{"account_ids" => [other_user.id]})

      assert %{} == json_response(conn, 200)
      %Pleroma.List{following: following} = Pleroma.List.get(list.id, user)
      assert following == [third_user.follower_address]
    end

    test "listing users in a list", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)
      {:ok, list} = Pleroma.List.create("name", user)
      {:ok, list} = Pleroma.List.follow(list, other_user)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/lists/#{list.id}/accounts", %{"account_ids" => [other_user.id]})

      assert [%{"id" => id}] = json_response(conn, 200)
      assert id == to_string(other_user.id)
    end

    test "retrieving a list", %{conn: conn} do
      user = insert(:user)
      {:ok, list} = Pleroma.List.create("name", user)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/lists/#{list.id}")

      assert %{"id" => id} = json_response(conn, 200)
      assert id == to_string(list.id)
    end

    test "renaming a list", %{conn: conn} do
      user = insert(:user)
      {:ok, list} = Pleroma.List.create("name", user)

      conn =
        conn
        |> assign(:user, user)
        |> put("/api/v1/lists/#{list.id}", %{"title" => "newname"})

      assert %{"title" => name} = json_response(conn, 200)
      assert name == "newname"
    end

    test "deleting a list", %{conn: conn} do
      user = insert(:user)
      {:ok, list} = Pleroma.List.create("name", user)

      conn =
        conn
        |> assign(:user, user)
        |> delete("/api/v1/lists/#{list.id}")

      assert %{} = json_response(conn, 200)
      assert is_nil(Repo.get(Pleroma.List, list.id))
    end

    test "list timeline", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)
      {:ok, _activity_one} = TwitterAPI.create_status(user, %{"status" => "Marisa is cute."})
      {:ok, activity_two} = TwitterAPI.create_status(other_user, %{"status" => "Marisa is cute."})
      {:ok, list} = Pleroma.List.create("name", user)
      {:ok, list} = Pleroma.List.follow(list, other_user)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/timelines/list/#{list.id}")

      assert [%{"id" => id}] = json_response(conn, 200)

      assert id == to_string(activity_two.id)
    end

    test "list timeline does not leak non-public statuses for unfollowed users", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)
      {:ok, activity_one} = TwitterAPI.create_status(other_user, %{"status" => "Marisa is cute."})

      {:ok, _activity_two} =
        TwitterAPI.create_status(other_user, %{
          "status" => "Marisa is cute.",
          "visibility" => "private"
        })

      {:ok, list} = Pleroma.List.create("name", user)
      {:ok, list} = Pleroma.List.follow(list, other_user)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/timelines/list/#{list.id}")

      assert [%{"id" => id}] = json_response(conn, 200)

      assert id == to_string(activity_one.id)
    end
  end

  describe "notifications" do
    test "list of notifications", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} =
        TwitterAPI.create_status(other_user, %{"status" => "hi @#{user.nickname}"})

      {:ok, [_notification]} = Notification.create_notifications(activity)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/notifications")

      expected_response =
        "hi <span class=\"h-card\"><a data-user=\"#{user.id}\" class=\"u-url mention\" href=\"#{
          user.ap_id
        }\">@<span>#{user.nickname}</span></a></span>"

      assert [%{"status" => %{"content" => response}} | _rest] = json_response(conn, 200)
      assert response == expected_response
    end

    test "getting a single notification", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} =
        TwitterAPI.create_status(other_user, %{"status" => "hi @#{user.nickname}"})

      {:ok, [notification]} = Notification.create_notifications(activity)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/notifications/#{notification.id}")

      expected_response =
        "hi <span class=\"h-card\"><a data-user=\"#{user.id}\" class=\"u-url mention\" href=\"#{
          user.ap_id
        }\">@<span>#{user.nickname}</span></a></span>"

      assert %{"status" => %{"content" => response}} = json_response(conn, 200)
      assert response == expected_response
    end

    test "dismissing a single notification", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} =
        TwitterAPI.create_status(other_user, %{"status" => "hi @#{user.nickname}"})

      {:ok, [notification]} = Notification.create_notifications(activity)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/notifications/dismiss", %{"id" => notification.id})

      assert %{} = json_response(conn, 200)
    end

    test "clearing all notifications", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity} =
        TwitterAPI.create_status(other_user, %{"status" => "hi @#{user.nickname}"})

      {:ok, [_notification]} = Notification.create_notifications(activity)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/notifications/clear")

      assert %{} = json_response(conn, 200)

      conn =
        build_conn()
        |> assign(:user, user)
        |> get("/api/v1/notifications")

      assert all = json_response(conn, 200)
      assert all == []
    end

    test "paginates notifications using min_id, since_id, max_id, and limit", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity1} = CommonAPI.post(other_user, %{"status" => "hi @#{user.nickname}"})
      {:ok, activity2} = CommonAPI.post(other_user, %{"status" => "hi @#{user.nickname}"})
      {:ok, activity3} = CommonAPI.post(other_user, %{"status" => "hi @#{user.nickname}"})
      {:ok, activity4} = CommonAPI.post(other_user, %{"status" => "hi @#{user.nickname}"})

      notification1_id = Repo.get_by(Notification, activity_id: activity1.id).id |> to_string()
      notification2_id = Repo.get_by(Notification, activity_id: activity2.id).id |> to_string()
      notification3_id = Repo.get_by(Notification, activity_id: activity3.id).id |> to_string()
      notification4_id = Repo.get_by(Notification, activity_id: activity4.id).id |> to_string()

      conn =
        conn
        |> assign(:user, user)

      # min_id
      conn_res =
        conn
        |> get("/api/v1/notifications?limit=2&min_id=#{notification1_id}")

      result = json_response(conn_res, 200)
      assert [%{"id" => ^notification3_id}, %{"id" => ^notification2_id}] = result

      # since_id
      conn_res =
        conn
        |> get("/api/v1/notifications?limit=2&since_id=#{notification1_id}")

      result = json_response(conn_res, 200)
      assert [%{"id" => ^notification4_id}, %{"id" => ^notification3_id}] = result

      # max_id
      conn_res =
        conn
        |> get("/api/v1/notifications?limit=2&max_id=#{notification4_id}")

      result = json_response(conn_res, 200)
      assert [%{"id" => ^notification3_id}, %{"id" => ^notification2_id}] = result
    end

    test "filters notifications using exclude_types", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, mention_activity} = CommonAPI.post(other_user, %{"status" => "hey @#{user.nickname}"})
      {:ok, create_activity} = CommonAPI.post(user, %{"status" => "hey"})
      {:ok, favorite_activity, _} = CommonAPI.favorite(create_activity.id, other_user)
      {:ok, reblog_activity, _} = CommonAPI.repeat(create_activity.id, other_user)
      {:ok, _, _, follow_activity} = CommonAPI.follow(other_user, user)

      mention_notification_id =
        Repo.get_by(Notification, activity_id: mention_activity.id).id |> to_string()

      favorite_notification_id =
        Repo.get_by(Notification, activity_id: favorite_activity.id).id |> to_string()

      reblog_notification_id =
        Repo.get_by(Notification, activity_id: reblog_activity.id).id |> to_string()

      follow_notification_id =
        Repo.get_by(Notification, activity_id: follow_activity.id).id |> to_string()

      conn =
        conn
        |> assign(:user, user)

      conn_res =
        get(conn, "/api/v1/notifications", %{exclude_types: ["mention", "favourite", "reblog"]})

      assert [%{"id" => ^follow_notification_id}] = json_response(conn_res, 200)

      conn_res =
        get(conn, "/api/v1/notifications", %{exclude_types: ["favourite", "reblog", "follow"]})

      assert [%{"id" => ^mention_notification_id}] = json_response(conn_res, 200)

      conn_res =
        get(conn, "/api/v1/notifications", %{exclude_types: ["reblog", "follow", "mention"]})

      assert [%{"id" => ^favorite_notification_id}] = json_response(conn_res, 200)

      conn_res =
        get(conn, "/api/v1/notifications", %{exclude_types: ["follow", "mention", "favourite"]})

      assert [%{"id" => ^reblog_notification_id}] = json_response(conn_res, 200)
    end
  end

  describe "reblogging" do
    test "reblogs and returns the reblogged status", %{conn: conn} do
      activity = insert(:note_activity)
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/statuses/#{activity.id}/reblog")

      assert %{"reblog" => %{"id" => id, "reblogged" => true, "reblogs_count" => 1}} =
               json_response(conn, 200)

      assert to_string(activity.id) == id
    end
  end

  describe "unreblogging" do
    test "unreblogs and returns the unreblogged status", %{conn: conn} do
      activity = insert(:note_activity)
      user = insert(:user)

      {:ok, _, _} = CommonAPI.repeat(activity.id, user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/statuses/#{activity.id}/unreblog")

      assert %{"id" => id, "reblogged" => false, "reblogs_count" => 0} = json_response(conn, 200)

      assert to_string(activity.id) == id
    end
  end

  describe "favoriting" do
    test "favs a status and returns it", %{conn: conn} do
      activity = insert(:note_activity)
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/statuses/#{activity.id}/favourite")

      assert %{"id" => id, "favourites_count" => 1, "favourited" => true} =
               json_response(conn, 200)

      assert to_string(activity.id) == id
    end

    test "returns 500 for a wrong id", %{conn: conn} do
      user = insert(:user)

      resp =
        conn
        |> assign(:user, user)
        |> post("/api/v1/statuses/1/favourite")
        |> json_response(500)

      assert resp == "Something went wrong"
    end
  end

  describe "unfavoriting" do
    test "unfavorites a status and returns it", %{conn: conn} do
      activity = insert(:note_activity)
      user = insert(:user)

      {:ok, _, _} = CommonAPI.favorite(activity.id, user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/statuses/#{activity.id}/unfavourite")

      assert %{"id" => id, "favourites_count" => 0, "favourited" => false} =
               json_response(conn, 200)

      assert to_string(activity.id) == id
    end
  end

  describe "user timelines" do
    test "gets a users statuses", %{conn: conn} do
      user_one = insert(:user)
      user_two = insert(:user)
      user_three = insert(:user)

      {:ok, user_three} = User.follow(user_three, user_one)

      {:ok, activity} = CommonAPI.post(user_one, %{"status" => "HI!!!"})

      {:ok, direct_activity} =
        CommonAPI.post(user_one, %{
          "status" => "Hi, @#{user_two.nickname}.",
          "visibility" => "direct"
        })

      {:ok, private_activity} =
        CommonAPI.post(user_one, %{"status" => "private", "visibility" => "private"})

      resp =
        conn
        |> get("/api/v1/accounts/#{user_one.id}/statuses")

      assert [%{"id" => id}] = json_response(resp, 200)
      assert id == to_string(activity.id)

      resp =
        conn
        |> assign(:user, user_two)
        |> get("/api/v1/accounts/#{user_one.id}/statuses")

      assert [%{"id" => id_one}, %{"id" => id_two}] = json_response(resp, 200)
      assert id_one == to_string(direct_activity.id)
      assert id_two == to_string(activity.id)

      resp =
        conn
        |> assign(:user, user_three)
        |> get("/api/v1/accounts/#{user_one.id}/statuses")

      assert [%{"id" => id_one}, %{"id" => id_two}] = json_response(resp, 200)
      assert id_one == to_string(private_activity.id)
      assert id_two == to_string(activity.id)
    end

    test "unimplemented pinned statuses feature", %{conn: conn} do
      note = insert(:note_activity)
      user = User.get_by_ap_id(note.data["actor"])

      conn =
        conn
        |> get("/api/v1/accounts/#{user.id}/statuses?pinned=true")

      assert json_response(conn, 200) == []
    end

    test "gets an users media", %{conn: conn} do
      note = insert(:note_activity)
      user = User.get_by_ap_id(note.data["actor"])

      file = %Plug.Upload{
        content_type: "image/jpg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      media =
        TwitterAPI.upload(file, user, "json")
        |> Poison.decode!()

      {:ok, image_post} =
        TwitterAPI.create_status(user, %{"status" => "cofe", "media_ids" => [media["media_id"]]})

      conn =
        conn
        |> get("/api/v1/accounts/#{user.id}/statuses", %{"only_media" => "true"})

      assert [%{"id" => id}] = json_response(conn, 200)
      assert id == to_string(image_post.id)

      conn =
        build_conn()
        |> get("/api/v1/accounts/#{user.id}/statuses", %{"only_media" => "1"})

      assert [%{"id" => id}] = json_response(conn, 200)
      assert id == to_string(image_post.id)
    end

    test "gets a user's statuses without reblogs", %{conn: conn} do
      user = insert(:user)
      {:ok, post} = CommonAPI.post(user, %{"status" => "HI!!!"})
      {:ok, _, _} = CommonAPI.repeat(post.id, user)

      conn =
        conn
        |> get("/api/v1/accounts/#{user.id}/statuses", %{"exclude_reblogs" => "true"})

      assert [%{"id" => id}] = json_response(conn, 200)
      assert id == to_string(post.id)

      conn =
        conn
        |> get("/api/v1/accounts/#{user.id}/statuses", %{"exclude_reblogs" => "1"})

      assert [%{"id" => id}] = json_response(conn, 200)
      assert id == to_string(post.id)
    end
  end

  describe "user relationships" do
    test "returns the relationships for the current user", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)
      {:ok, user} = User.follow(user, other_user)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/accounts/relationships", %{"id" => [other_user.id]})

      assert [relationship] = json_response(conn, 200)

      assert to_string(other_user.id) == relationship["id"]
    end
  end

  describe "locked accounts" do
    test "/api/v1/follow_requests works" do
      user = insert(:user, %{info: %Pleroma.User.Info{locked: true}})
      other_user = insert(:user)

      {:ok, _activity} = ActivityPub.follow(other_user, user)

      user = Repo.get(User, user.id)
      other_user = Repo.get(User, other_user.id)

      assert User.following?(other_user, user) == false

      conn =
        build_conn()
        |> assign(:user, user)
        |> get("/api/v1/follow_requests")

      assert [relationship] = json_response(conn, 200)
      assert to_string(other_user.id) == relationship["id"]
    end

    test "/api/v1/follow_requests/:id/authorize works" do
      user = insert(:user, %{info: %User.Info{locked: true}})
      other_user = insert(:user)

      {:ok, _activity} = ActivityPub.follow(other_user, user)

      user = Repo.get(User, user.id)
      other_user = Repo.get(User, other_user.id)

      assert User.following?(other_user, user) == false

      conn =
        build_conn()
        |> assign(:user, user)
        |> post("/api/v1/follow_requests/#{other_user.id}/authorize")

      assert relationship = json_response(conn, 200)
      assert to_string(other_user.id) == relationship["id"]

      user = Repo.get(User, user.id)
      other_user = Repo.get(User, other_user.id)

      assert User.following?(other_user, user) == true
    end

    test "verify_credentials", %{conn: conn} do
      user = insert(:user, %{info: %Pleroma.User.Info{default_scope: "private"}})

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/accounts/verify_credentials")

      assert %{"id" => id, "source" => %{"privacy" => "private"}} = json_response(conn, 200)
      assert id == to_string(user.id)
    end

    test "/api/v1/follow_requests/:id/reject works" do
      user = insert(:user, %{info: %Pleroma.User.Info{locked: true}})
      other_user = insert(:user)

      {:ok, _activity} = ActivityPub.follow(other_user, user)

      user = Repo.get(User, user.id)

      conn =
        build_conn()
        |> assign(:user, user)
        |> post("/api/v1/follow_requests/#{other_user.id}/reject")

      assert relationship = json_response(conn, 200)
      assert to_string(other_user.id) == relationship["id"]

      user = Repo.get(User, user.id)
      other_user = Repo.get(User, other_user.id)

      assert User.following?(other_user, user) == false
    end
  end

  test "account fetching", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> get("/api/v1/accounts/#{user.id}")

    assert %{"id" => id} = json_response(conn, 200)
    assert id == to_string(user.id)

    conn =
      build_conn()
      |> get("/api/v1/accounts/-1")

    assert %{"error" => "Can't find user"} = json_response(conn, 404)
  end

  test "account fetching also works nickname", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> get("/api/v1/accounts/#{user.nickname}")

    assert %{"id" => id} = json_response(conn, 200)
    assert id == user.id
  end

  test "media upload", %{conn: conn} do
    file = %Plug.Upload{
      content_type: "image/jpg",
      path: Path.absname("test/fixtures/image.jpg"),
      filename: "an_image.jpg"
    }

    desc = "Description of the image"

    user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/media", %{"file" => file, "description" => desc})

    assert media = json_response(conn, 200)

    assert media["type"] == "image"
    assert media["description"] == desc
    assert media["id"]

    object = Repo.get(Object, media["id"])
    assert object.data["actor"] == User.ap_id(user)
  end

  test "hashtag timeline", %{conn: conn} do
    following = insert(:user)

    capture_log(fn ->
      {:ok, activity} = TwitterAPI.create_status(following, %{"status" => "test #2hu"})

      {:ok, [_activity]} =
        OStatus.fetch_activity_from_url("https://shitposter.club/notice/2827873")

      nconn =
        conn
        |> get("/api/v1/timelines/tag/2hu")

      assert [%{"id" => id}] = json_response(nconn, 200)

      assert id == to_string(activity.id)

      # works for different capitalization too
      nconn =
        conn
        |> get("/api/v1/timelines/tag/2HU")

      assert [%{"id" => id}] = json_response(nconn, 200)

      assert id == to_string(activity.id)
    end)
  end

  test "multi-hashtag timeline", %{conn: conn} do
    user = insert(:user)

    {:ok, activity_test} = CommonAPI.post(user, %{"status" => "#test"})
    {:ok, activity_test1} = CommonAPI.post(user, %{"status" => "#test #test1"})
    {:ok, activity_none} = CommonAPI.post(user, %{"status" => "#test #none"})

    any_test =
      conn
      |> get("/api/v1/timelines/tag/test", %{"any" => ["test1"]})

    [status_none, status_test1, status_test] = json_response(any_test, 200)

    assert to_string(activity_test.id) == status_test["id"]
    assert to_string(activity_test1.id) == status_test1["id"]
    assert to_string(activity_none.id) == status_none["id"]

    restricted_test =
      conn
      |> get("/api/v1/timelines/tag/test", %{"all" => ["test1"], "none" => ["none"]})

    assert [status_test1] == json_response(restricted_test, 200)

    all_test = conn |> get("/api/v1/timelines/tag/test", %{"all" => ["none"]})

    assert [status_none] == json_response(all_test, 200)
  end

  test "getting followers", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)
    {:ok, user} = User.follow(user, other_user)

    conn =
      conn
      |> get("/api/v1/accounts/#{other_user.id}/followers")

    assert [%{"id" => id}] = json_response(conn, 200)
    assert id == to_string(user.id)
  end

  test "getting followers, hide_followers", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user, %{info: %{hide_followers: true}})
    {:ok, _user} = User.follow(user, other_user)

    conn =
      conn
      |> get("/api/v1/accounts/#{other_user.id}/followers")

    assert [] == json_response(conn, 200)
  end

  test "getting followers, hide_followers, same user requesting", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user, %{info: %{hide_followers: true}})
    {:ok, _user} = User.follow(user, other_user)

    conn =
      conn
      |> assign(:user, other_user)
      |> get("/api/v1/accounts/#{other_user.id}/followers")

    refute [] == json_response(conn, 200)
  end

  test "getting followers, pagination", %{conn: conn} do
    user = insert(:user)
    follower1 = insert(:user)
    follower2 = insert(:user)
    follower3 = insert(:user)
    {:ok, _} = User.follow(follower1, user)
    {:ok, _} = User.follow(follower2, user)
    {:ok, _} = User.follow(follower3, user)

    conn =
      conn
      |> assign(:user, user)

    res_conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/followers?since_id=#{follower1.id}")

    assert [%{"id" => id3}, %{"id" => id2}] = json_response(res_conn, 200)
    assert id3 == follower3.id
    assert id2 == follower2.id

    res_conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/followers?max_id=#{follower3.id}")

    assert [%{"id" => id2}, %{"id" => id1}] = json_response(res_conn, 200)
    assert id2 == follower2.id
    assert id1 == follower1.id

    res_conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/followers?limit=1&max_id=#{follower3.id}")

    assert [%{"id" => id2}] = json_response(res_conn, 200)
    assert id2 == follower2.id

    assert [link_header] = get_resp_header(res_conn, "link")
    assert link_header =~ ~r/since_id=#{follower2.id}/
    assert link_header =~ ~r/max_id=#{follower2.id}/
  end

  test "getting following", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)
    {:ok, user} = User.follow(user, other_user)

    conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/following")

    assert [%{"id" => id}] = json_response(conn, 200)
    assert id == to_string(other_user.id)
  end

  test "getting following, hide_follows", %{conn: conn} do
    user = insert(:user, %{info: %{hide_follows: true}})
    other_user = insert(:user)
    {:ok, user} = User.follow(user, other_user)

    conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/following")

    assert [] == json_response(conn, 200)
  end

  test "getting following, hide_follows, same user requesting", %{conn: conn} do
    user = insert(:user, %{info: %{hide_follows: true}})
    other_user = insert(:user)
    {:ok, user} = User.follow(user, other_user)

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/accounts/#{user.id}/following")

    refute [] == json_response(conn, 200)
  end

  test "getting following, pagination", %{conn: conn} do
    user = insert(:user)
    following1 = insert(:user)
    following2 = insert(:user)
    following3 = insert(:user)
    {:ok, _} = User.follow(user, following1)
    {:ok, _} = User.follow(user, following2)
    {:ok, _} = User.follow(user, following3)

    conn =
      conn
      |> assign(:user, user)

    res_conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/following?since_id=#{following1.id}")

    assert [%{"id" => id3}, %{"id" => id2}] = json_response(res_conn, 200)
    assert id3 == following3.id
    assert id2 == following2.id

    res_conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/following?max_id=#{following3.id}")

    assert [%{"id" => id2}, %{"id" => id1}] = json_response(res_conn, 200)
    assert id2 == following2.id
    assert id1 == following1.id

    res_conn =
      conn
      |> get("/api/v1/accounts/#{user.id}/following?limit=1&max_id=#{following3.id}")

    assert [%{"id" => id2}] = json_response(res_conn, 200)
    assert id2 == following2.id

    assert [link_header] = get_resp_header(res_conn, "link")
    assert link_header =~ ~r/since_id=#{following2.id}/
    assert link_header =~ ~r/max_id=#{following2.id}/
  end

  test "following / unfollowing a user", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/accounts/#{other_user.id}/follow")

    assert %{"id" => _id, "following" => true} = json_response(conn, 200)

    user = Repo.get(User, user.id)

    conn =
      build_conn()
      |> assign(:user, user)
      |> post("/api/v1/accounts/#{other_user.id}/unfollow")

    assert %{"id" => _id, "following" => false} = json_response(conn, 200)

    user = Repo.get(User, user.id)

    conn =
      build_conn()
      |> assign(:user, user)
      |> post("/api/v1/follows", %{"uri" => other_user.nickname})

    assert %{"id" => id} = json_response(conn, 200)
    assert id == to_string(other_user.id)
  end

  test "muting / unmuting a user", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/accounts/#{other_user.id}/mute")

    assert %{"id" => _id, "muting" => true} = json_response(conn, 200)

    user = Repo.get(User, user.id)

    conn =
      build_conn()
      |> assign(:user, user)
      |> post("/api/v1/accounts/#{other_user.id}/unmute")

    assert %{"id" => _id, "muting" => false} = json_response(conn, 200)
  end

  test "getting a list of mutes", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, user} = User.mute(user, other_user)

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/mutes")

    other_user_id = to_string(other_user.id)
    assert [%{"id" => ^other_user_id}] = json_response(conn, 200)
  end

  test "blocking / unblocking a user", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/accounts/#{other_user.id}/block")

    assert %{"id" => _id, "blocking" => true} = json_response(conn, 200)

    user = Repo.get(User, user.id)

    conn =
      build_conn()
      |> assign(:user, user)
      |> post("/api/v1/accounts/#{other_user.id}/unblock")

    assert %{"id" => _id, "blocking" => false} = json_response(conn, 200)
  end

  test "getting a list of blocks", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, user} = User.block(user, other_user)

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/blocks")

    other_user_id = to_string(other_user.id)
    assert [%{"id" => ^other_user_id}] = json_response(conn, 200)
  end

  test "blocking / unblocking a domain", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user, %{ap_id: "https://dogwhistle.zone/@pundit"})

    conn =
      conn
      |> assign(:user, user)
      |> post("/api/v1/domain_blocks", %{"domain" => "dogwhistle.zone"})

    assert %{} = json_response(conn, 200)
    user = User.get_cached_by_ap_id(user.ap_id)
    assert User.blocks?(user, other_user)

    conn =
      build_conn()
      |> assign(:user, user)
      |> delete("/api/v1/domain_blocks", %{"domain" => "dogwhistle.zone"})

    assert %{} = json_response(conn, 200)
    user = User.get_cached_by_ap_id(user.ap_id)
    refute User.blocks?(user, other_user)
  end

  test "getting a list of domain blocks", %{conn: conn} do
    user = insert(:user)

    {:ok, user} = User.block_domain(user, "bad.site")
    {:ok, user} = User.block_domain(user, "even.worse.site")

    conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/domain_blocks")

    domain_blocks = json_response(conn, 200)

    assert "bad.site" in domain_blocks
    assert "even.worse.site" in domain_blocks
  end

  test "unimplemented follow_requests, blocks, domain blocks" do
    user = insert(:user)

    ["blocks", "domain_blocks", "follow_requests"]
    |> Enum.each(fn endpoint ->
      conn =
        build_conn()
        |> assign(:user, user)
        |> get("/api/v1/#{endpoint}")

      assert [] = json_response(conn, 200)
    end)
  end

  test "account search", %{conn: conn} do
    user = insert(:user)
    user_two = insert(:user, %{nickname: "shp@shitposter.club"})
    user_three = insert(:user, %{nickname: "shp@heldscal.la", name: "I love 2hu"})

    results =
      conn
      |> assign(:user, user)
      |> get("/api/v1/accounts/search", %{"q" => "shp"})
      |> json_response(200)

    result_ids = for result <- results, do: result["acct"]

    assert user_two.nickname in result_ids
    assert user_three.nickname in result_ids

    results =
      conn
      |> assign(:user, user)
      |> get("/api/v1/accounts/search", %{"q" => "2hu"})
      |> json_response(200)

    result_ids = for result <- results, do: result["acct"]

    assert user_three.nickname in result_ids
  end

  test "search", %{conn: conn} do
    user = insert(:user)
    user_two = insert(:user, %{nickname: "shp@shitposter.club"})
    user_three = insert(:user, %{nickname: "shp@heldscal.la", name: "I love 2hu"})

    {:ok, activity} = CommonAPI.post(user, %{"status" => "This is about 2hu"})

    {:ok, _activity} =
      CommonAPI.post(user, %{
        "status" => "This is about 2hu, but private",
        "visibility" => "private"
      })

    {:ok, _} = CommonAPI.post(user_two, %{"status" => "This isn't"})

    conn =
      conn
      |> get("/api/v1/search", %{"q" => "2hu"})

    assert results = json_response(conn, 200)

    [account | _] = results["accounts"]
    assert account["id"] == to_string(user_three.id)

    assert results["hashtags"] == []

    [status] = results["statuses"]
    assert status["id"] == to_string(activity.id)
  end

  test "search fetches remote statuses", %{conn: conn} do
    capture_log(fn ->
      conn =
        conn
        |> get("/api/v1/search", %{"q" => "https://shitposter.club/notice/2827873"})

      assert results = json_response(conn, 200)

      [status] = results["statuses"]
      assert status["uri"] == "tag:shitposter.club,2017-05-05:noticeId=2827873:objectType=comment"
    end)
  end

  test "search doesn't show statuses that it shouldn't", %{conn: conn} do
    {:ok, activity} =
      CommonAPI.post(insert(:user), %{
        "status" => "This is about 2hu, but private",
        "visibility" => "private"
      })

    capture_log(fn ->
      conn =
        conn
        |> get("/api/v1/search", %{"q" => activity.data["object"]["id"]})

      assert results = json_response(conn, 200)

      [] = results["statuses"]
    end)
  end

  test "search fetches remote accounts", %{conn: conn} do
    conn =
      conn
      |> get("/api/v1/search", %{"q" => "shp@social.heldscal.la", "resolve" => "true"})

    assert results = json_response(conn, 200)
    [account] = results["accounts"]
    assert account["acct"] == "shp@social.heldscal.la"
  end

  test "returns the favorites of a user", %{conn: conn} do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, _} = CommonAPI.post(other_user, %{"status" => "bla"})
    {:ok, activity} = CommonAPI.post(other_user, %{"status" => "traps are happy"})

    {:ok, _, _} = CommonAPI.favorite(activity.id, user)

    first_conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/favourites")

    assert [status] = json_response(first_conn, 200)
    assert status["id"] == to_string(activity.id)

    assert [{"link", _link_header}] =
             Enum.filter(first_conn.resp_headers, fn element -> match?({"link", _}, element) end)

    # Honours query params
    {:ok, second_activity} =
      CommonAPI.post(other_user, %{
        "status" =>
          "Trees Are Never Sad Look At Them Every Once In Awhile They're Quite Beautiful."
      })

    {:ok, _, _} = CommonAPI.favorite(second_activity.id, user)

    last_like = status["id"]

    second_conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/favourites?since_id=#{last_like}")

    assert [second_status] = json_response(second_conn, 200)
    assert second_status["id"] == to_string(second_activity.id)

    third_conn =
      conn
      |> assign(:user, user)
      |> get("/api/v1/favourites?limit=0")

    assert [] = json_response(third_conn, 200)
  end

  describe "updating credentials" do
    test "updates the user's bio", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{
          "note" => "I drink #cofe with @#{user2.nickname}"
        })

      assert user = json_response(conn, 200)

      assert user["note"] ==
               ~s(I drink <a class="hashtag" data-tag="cofe" href="http://localhost:4001/tag/cofe" rel="tag">#cofe</a> with <span class="h-card"><a data-user=") <>
                 user2.id <>
                 ~s(" class="u-url mention" href=") <>
                 user2.ap_id <> ~s(">@<span>) <> user2.nickname <> ~s(</span></a></span>)
    end

    test "updates the user's locking status", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{locked: "true"})

      assert user = json_response(conn, 200)
      assert user["locked"] == true
    end

    test "updates the user's name", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{"display_name" => "markorepairs"})

      assert user = json_response(conn, 200)
      assert user["display_name"] == "markorepairs"
    end

    test "updates the user's avatar", %{conn: conn} do
      user = insert(:user)

      new_avatar = %Plug.Upload{
        content_type: "image/jpg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{"avatar" => new_avatar})

      assert user_response = json_response(conn, 200)
      assert user_response["avatar"] != User.avatar_url(user)
    end

    test "updates the user's banner", %{conn: conn} do
      user = insert(:user)

      new_header = %Plug.Upload{
        content_type: "image/jpg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{"header" => new_header})

      assert user_response = json_response(conn, 200)
      assert user_response["header"] != User.banner_url(user)
    end

    test "requires 'write' permission", %{conn: conn} do
      token1 = insert(:oauth_token, scopes: ["read"])
      token2 = insert(:oauth_token, scopes: ["write", "follow"])

      for token <- [token1, token2] do
        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token.token}")
          |> patch("/api/v1/accounts/update_credentials", %{})

        if token == token1 do
          assert %{"error" => "Insufficient permissions: write."} == json_response(conn, 403)
        else
          assert json_response(conn, 200)
        end
      end
    end
  end

  test "get instance information", %{conn: conn} do
    conn = get(conn, "/api/v1/instance")
    assert result = json_response(conn, 200)

    # Note: not checking for "max_toot_chars" since it's optional
    assert %{
             "uri" => _,
             "title" => _,
             "description" => _,
             "version" => _,
             "email" => _,
             "urls" => %{
               "streaming_api" => _
             },
             "stats" => _,
             "thumbnail" => _,
             "languages" => _,
             "registrations" => _
           } = result
  end

  test "get instance stats", %{conn: conn} do
    user = insert(:user, %{local: true})

    user2 = insert(:user, %{local: true})
    {:ok, _user2} = User.deactivate(user2, !user2.info.deactivated)

    insert(:user, %{local: false, nickname: "u@peer1.com"})
    insert(:user, %{local: false, nickname: "u@peer2.com"})

    {:ok, _} = TwitterAPI.create_status(user, %{"status" => "cofe"})

    # Stats should count users with missing or nil `info.deactivated` value
    user = Repo.get(User, user.id)
    info_change = Changeset.change(user.info, %{deactivated: nil})

    {:ok, _user} =
      user
      |> Changeset.change()
      |> Changeset.put_embed(:info, info_change)
      |> User.update_and_set_cache()

    Pleroma.Stats.update_stats()

    conn = get(conn, "/api/v1/instance")

    assert result = json_response(conn, 200)

    stats = result["stats"]

    assert stats
    assert stats["user_count"] == 1
    assert stats["status_count"] == 1
    assert stats["domain_count"] == 2
  end

  test "get peers", %{conn: conn} do
    insert(:user, %{local: false, nickname: "u@peer1.com"})
    insert(:user, %{local: false, nickname: "u@peer2.com"})

    Pleroma.Stats.update_stats()

    conn = get(conn, "/api/v1/instance/peers")

    assert result = json_response(conn, 200)

    assert ["peer1.com", "peer2.com"] == Enum.sort(result)
  end

  test "put settings", %{conn: conn} do
    user = insert(:user)

    conn =
      conn
      |> assign(:user, user)
      |> put("/api/web/settings", %{"data" => %{"programming" => "socks"}})

    assert _result = json_response(conn, 200)

    user = User.get_cached_by_ap_id(user.ap_id)
    assert user.info.settings == %{"programming" => "socks"}
  end

  describe "pinned statuses" do
    setup do
      Pleroma.Config.put([:instance, :max_pinned_statuses], 1)

      user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{"status" => "HI!!!"})

      [user: user, activity: activity]
    end

    test "returns pinned statuses", %{conn: conn, user: user, activity: activity} do
      {:ok, _} = CommonAPI.pin(activity.id, user)

      result =
        conn
        |> assign(:user, user)
        |> get("/api/v1/accounts/#{user.id}/statuses?pinned=true")
        |> json_response(200)

      id_str = to_string(activity.id)

      assert [%{"id" => ^id_str, "pinned" => true}] = result
    end

    test "pin status", %{conn: conn, user: user, activity: activity} do
      id_str = to_string(activity.id)

      assert %{"id" => ^id_str, "pinned" => true} =
               conn
               |> assign(:user, user)
               |> post("/api/v1/statuses/#{activity.id}/pin")
               |> json_response(200)

      assert [%{"id" => ^id_str, "pinned" => true}] =
               conn
               |> assign(:user, user)
               |> get("/api/v1/accounts/#{user.id}/statuses?pinned=true")
               |> json_response(200)
    end

    test "unpin status", %{conn: conn, user: user, activity: activity} do
      {:ok, _} = CommonAPI.pin(activity.id, user)

      id_str = to_string(activity.id)
      user = refresh_record(user)

      assert %{"id" => ^id_str, "pinned" => false} =
               conn
               |> assign(:user, user)
               |> post("/api/v1/statuses/#{activity.id}/unpin")
               |> json_response(200)

      assert [] =
               conn
               |> assign(:user, user)
               |> get("/api/v1/accounts/#{user.id}/statuses?pinned=true")
               |> json_response(200)
    end

    test "max pinned statuses", %{conn: conn, user: user, activity: activity_one} do
      {:ok, activity_two} = CommonAPI.post(user, %{"status" => "HI!!!"})

      id_str_one = to_string(activity_one.id)

      assert %{"id" => ^id_str_one, "pinned" => true} =
               conn
               |> assign(:user, user)
               |> post("/api/v1/statuses/#{id_str_one}/pin")
               |> json_response(200)

      user = refresh_record(user)

      assert %{"error" => "You have already pinned the maximum number of statuses"} =
               conn
               |> assign(:user, user)
               |> post("/api/v1/statuses/#{activity_two.id}/pin")
               |> json_response(400)
    end

    test "Status rich-media Card", %{conn: conn, user: user} do
      Pleroma.Config.put([:rich_media, :enabled], true)
      {:ok, activity} = CommonAPI.post(user, %{"status" => "http://example.com/ogp"})

      response =
        conn
        |> get("/api/v1/statuses/#{activity.id}/card")
        |> json_response(200)

      assert response == %{
               "image" => "http://ia.media-imdb.com/images/rock.jpg",
               "provider_name" => "www.imdb.com",
               "provider_url" => "http://www.imdb.com",
               "title" => "The Rock",
               "type" => "link",
               "url" => "http://www.imdb.com/title/tt0117500/",
               "description" => nil,
               "pleroma" => %{
                 "opengraph" => %{
                   "image" => "http://ia.media-imdb.com/images/rock.jpg",
                   "title" => "The Rock",
                   "type" => "video.movie",
                   "url" => "http://www.imdb.com/title/tt0117500/"
                 }
               }
             }

      # works with private posts
      {:ok, activity} =
        CommonAPI.post(user, %{"status" => "http://example.com/ogp", "visibility" => "direct"})

      response_two =
        conn
        |> assign(:user, user)
        |> get("/api/v1/statuses/#{activity.id}/card")
        |> json_response(200)

      assert response_two == response

      Pleroma.Config.put([:rich_media, :enabled], false)
    end
  end

  test "bookmarks" do
    user = insert(:user)
    for_user = insert(:user)

    {:ok, activity1} =
      CommonAPI.post(user, %{
        "status" => "heweoo?"
      })

    {:ok, activity2} =
      CommonAPI.post(user, %{
        "status" => "heweoo!"
      })

    response1 =
      build_conn()
      |> assign(:user, for_user)
      |> post("/api/v1/statuses/#{activity1.id}/bookmark")

    assert json_response(response1, 200)["bookmarked"] == true

    response2 =
      build_conn()
      |> assign(:user, for_user)
      |> post("/api/v1/statuses/#{activity2.id}/bookmark")

    assert json_response(response2, 200)["bookmarked"] == true

    bookmarks =
      build_conn()
      |> assign(:user, for_user)
      |> get("/api/v1/bookmarks")

    assert [json_response(response2, 200), json_response(response1, 200)] ==
             json_response(bookmarks, 200)

    response1 =
      build_conn()
      |> assign(:user, for_user)
      |> post("/api/v1/statuses/#{activity1.id}/unbookmark")

    assert json_response(response1, 200)["bookmarked"] == false

    bookmarks =
      build_conn()
      |> assign(:user, for_user)
      |> get("/api/v1/bookmarks")

    assert [json_response(response2, 200)] == json_response(bookmarks, 200)
  end

  describe "conversation muting" do
    setup do
      user = insert(:user)
      {:ok, activity} = CommonAPI.post(user, %{"status" => "HIE"})

      [user: user, activity: activity]
    end

    test "mute conversation", %{conn: conn, user: user, activity: activity} do
      id_str = to_string(activity.id)

      assert %{"id" => ^id_str, "muted" => true} =
               conn
               |> assign(:user, user)
               |> post("/api/v1/statuses/#{activity.id}/mute")
               |> json_response(200)
    end

    test "unmute conversation", %{conn: conn, user: user, activity: activity} do
      {:ok, _} = CommonAPI.add_mute(user, activity)

      id_str = to_string(activity.id)
      user = refresh_record(user)

      assert %{"id" => ^id_str, "muted" => false} =
               conn
               |> assign(:user, user)
               |> post("/api/v1/statuses/#{activity.id}/unmute")
               |> json_response(200)
    end
  end

  test "flavours switching (Pleroma Extension)", %{conn: conn} do
    user = insert(:user)

    get_old_flavour =
      conn
      |> assign(:user, user)
      |> get("/api/v1/pleroma/flavour")

    assert "glitch" == json_response(get_old_flavour, 200)

    set_flavour =
      conn
      |> assign(:user, user)
      |> post("/api/v1/pleroma/flavour/vanilla")

    assert "vanilla" == json_response(set_flavour, 200)

    get_new_flavour =
      conn
      |> assign(:user, user)
      |> post("/api/v1/pleroma/flavour/vanilla")

    assert json_response(set_flavour, 200) == json_response(get_new_flavour, 200)
  end

  describe "reports" do
    setup do
      reporter = insert(:user)
      target_user = insert(:user)

      {:ok, activity} = CommonAPI.post(target_user, %{"status" => "foobar"})

      [reporter: reporter, target_user: target_user, activity: activity]
    end

    test "submit a basic report", %{conn: conn, reporter: reporter, target_user: target_user} do
      assert %{"action_taken" => false, "id" => _} =
               conn
               |> assign(:user, reporter)
               |> post("/api/v1/reports", %{"account_id" => target_user.id})
               |> json_response(200)
    end

    test "submit a report with statuses and comment", %{
      conn: conn,
      reporter: reporter,
      target_user: target_user,
      activity: activity
    } do
      assert %{"action_taken" => false, "id" => _} =
               conn
               |> assign(:user, reporter)
               |> post("/api/v1/reports", %{
                 "account_id" => target_user.id,
                 "status_ids" => [activity.id],
                 "comment" => "bad status!"
               })
               |> json_response(200)
    end

    test "account_id is required", %{
      conn: conn,
      reporter: reporter,
      activity: activity
    } do
      assert %{"error" => "Valid `account_id` required"} =
               conn
               |> assign(:user, reporter)
               |> post("/api/v1/reports", %{"status_ids" => [activity.id]})
               |> json_response(400)
    end

    test "comment must be up to the size specified in the config", %{
      conn: conn,
      reporter: reporter,
      target_user: target_user
    } do
      max_size = Pleroma.Config.get([:instance, :max_report_comment_size], 1000)
      comment = String.pad_trailing("a", max_size + 1, "a")

      error = %{"error" => "Comment must be up to #{max_size} characters"}

      assert ^error =
               conn
               |> assign(:user, reporter)
               |> post("/api/v1/reports", %{"account_id" => target_user.id, "comment" => comment})
               |> json_response(400)
    end
  end

  describe "link headers" do
    test "preserves parameters in link headers", %{conn: conn} do
      user = insert(:user)
      other_user = insert(:user)

      {:ok, activity1} =
        CommonAPI.post(other_user, %{
          "status" => "hi @#{user.nickname}",
          "visibility" => "public"
        })

      {:ok, activity2} =
        CommonAPI.post(other_user, %{
          "status" => "hi @#{user.nickname}",
          "visibility" => "public"
        })

      notification1 = Repo.get_by(Notification, activity_id: activity1.id)
      notification2 = Repo.get_by(Notification, activity_id: activity2.id)

      conn =
        conn
        |> assign(:user, user)
        |> get("/api/v1/notifications", %{media_only: true})

      assert [link_header] = get_resp_header(conn, "link")
      assert link_header =~ ~r/media_only=true/
      assert link_header =~ ~r/since_id=#{notification2.id}/
      assert link_header =~ ~r/max_id=#{notification1.id}/
    end
  end
end
