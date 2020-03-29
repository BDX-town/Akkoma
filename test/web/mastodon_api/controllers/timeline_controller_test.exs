# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.TimelineControllerTest do
  use Pleroma.Web.ConnCase

  import Pleroma.Factory
  import Tesla.Mock

  alias Pleroma.Config
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI

  setup do
    mock(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  describe "home" do
    setup do: oauth_access(["read:statuses"])

    test "the home timeline", %{user: user, conn: conn} do
      following = insert(:user, nickname: "followed")
      third_user = insert(:user, nickname: "repeated")

      {:ok, _activity} = CommonAPI.post(following, %{"status" => "post"})
      {:ok, activity} = CommonAPI.post(third_user, %{"status" => "repeated post"})
      {:ok, _, _} = CommonAPI.repeat(activity.id, following)

      ret_conn = get(conn, "/api/v1/timelines/home")

      assert Enum.empty?(json_response(ret_conn, :ok))

      {:ok, _user} = User.follow(user, following)

      ret_conn = get(conn, "/api/v1/timelines/home")

      assert [
               %{
                 "reblog" => %{
                   "content" => "repeated post",
                   "account" => %{
                     "pleroma" => %{
                       "relationship" => %{"following" => false, "followed_by" => false}
                     }
                   }
                 },
                 "account" => %{"pleroma" => %{"relationship" => %{"following" => true}}}
               },
               %{
                 "content" => "post",
                 "account" => %{
                   "acct" => "followed",
                   "pleroma" => %{"relationship" => %{"following" => true}}
                 }
               }
             ] = json_response(ret_conn, :ok)

      {:ok, _user} = User.follow(third_user, user)

      ret_conn = get(conn, "/api/v1/timelines/home")

      assert [
               %{
                 "reblog" => %{
                   "content" => "repeated post",
                   "account" => %{
                     "acct" => "repeated",
                     "pleroma" => %{
                       "relationship" => %{"following" => false, "followed_by" => true}
                     }
                   }
                 },
                 "account" => %{"pleroma" => %{"relationship" => %{"following" => true}}}
               },
               %{
                 "content" => "post",
                 "account" => %{
                   "acct" => "followed",
                   "pleroma" => %{"relationship" => %{"following" => true}}
                 }
               }
             ] = json_response(ret_conn, :ok)
    end

    test "the home timeline when the direct messages are excluded", %{user: user, conn: conn} do
      {:ok, public_activity} = CommonAPI.post(user, %{"status" => ".", "visibility" => "public"})
      {:ok, direct_activity} = CommonAPI.post(user, %{"status" => ".", "visibility" => "direct"})

      {:ok, unlisted_activity} =
        CommonAPI.post(user, %{"status" => ".", "visibility" => "unlisted"})

      {:ok, private_activity} =
        CommonAPI.post(user, %{"status" => ".", "visibility" => "private"})

      conn = get(conn, "/api/v1/timelines/home", %{"exclude_visibilities" => ["direct"]})

      assert status_ids = json_response(conn, :ok) |> Enum.map(& &1["id"])
      assert public_activity.id in status_ids
      assert unlisted_activity.id in status_ids
      assert private_activity.id in status_ids
      refute direct_activity.id in status_ids
    end
  end

  describe "public" do
    @tag capture_log: true
    test "the public timeline", %{conn: conn} do
      following = insert(:user)

      {:ok, _activity} = CommonAPI.post(following, %{"status" => "test"})

      _activity = insert(:note_activity, local: false)

      conn = get(conn, "/api/v1/timelines/public", %{"local" => "False"})

      assert length(json_response(conn, :ok)) == 2

      conn = get(build_conn(), "/api/v1/timelines/public", %{"local" => "True"})

      assert [%{"content" => "test"}] = json_response(conn, :ok)

      conn = get(build_conn(), "/api/v1/timelines/public", %{"local" => "1"})

      assert [%{"content" => "test"}] = json_response(conn, :ok)
    end

    test "the public timeline includes only public statuses for an authenticated user" do
      %{user: user, conn: conn} = oauth_access(["read:statuses"])

      {:ok, _activity} = CommonAPI.post(user, %{"status" => "test"})
      {:ok, _activity} = CommonAPI.post(user, %{"status" => "test", "visibility" => "private"})
      {:ok, _activity} = CommonAPI.post(user, %{"status" => "test", "visibility" => "unlisted"})
      {:ok, _activity} = CommonAPI.post(user, %{"status" => "test", "visibility" => "direct"})

      res_conn = get(conn, "/api/v1/timelines/public")
      assert length(json_response(res_conn, 200)) == 1
    end
  end

  defp local_and_remote_activities do
    insert(:note_activity)
    insert(:note_activity, local: false)
    :ok
  end

  describe "public with restrict unauthenticated timeline for local and federated timelines" do
    setup do: local_and_remote_activities()

    setup do: clear_config([:restrict_unauthenticated, :timelines, :local], true)

    setup do: clear_config([:restrict_unauthenticated, :timelines, :federated], true)

    test "if user is unauthenticated", %{conn: conn} do
      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "true"})

      assert json_response(res_conn, :unauthorized) == %{
               "error" => "authorization required for timeline view"
             }

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "false"})

      assert json_response(res_conn, :unauthorized) == %{
               "error" => "authorization required for timeline view"
             }
    end

    test "if user is authenticated" do
      %{conn: conn} = oauth_access(["read:statuses"])

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "true"})
      assert length(json_response(res_conn, 200)) == 1

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "false"})
      assert length(json_response(res_conn, 200)) == 2
    end
  end

  describe "public with restrict unauthenticated timeline for local" do
    setup do: local_and_remote_activities()

    setup do: clear_config([:restrict_unauthenticated, :timelines, :local], true)

    test "if user is unauthenticated", %{conn: conn} do
      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "true"})

      assert json_response(res_conn, :unauthorized) == %{
               "error" => "authorization required for timeline view"
             }

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "false"})
      assert length(json_response(res_conn, 200)) == 2
    end

    test "if user is authenticated", %{conn: _conn} do
      %{conn: conn} = oauth_access(["read:statuses"])

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "true"})
      assert length(json_response(res_conn, 200)) == 1

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "false"})
      assert length(json_response(res_conn, 200)) == 2
    end
  end

  describe "public with restrict unauthenticated timeline for remote" do
    setup do: local_and_remote_activities()

    setup do: clear_config([:restrict_unauthenticated, :timelines, :federated], true)

    test "if user is unauthenticated", %{conn: conn} do
      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "true"})
      assert length(json_response(res_conn, 200)) == 1

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "false"})

      assert json_response(res_conn, :unauthorized) == %{
               "error" => "authorization required for timeline view"
             }
    end

    test "if user is authenticated", %{conn: _conn} do
      %{conn: conn} = oauth_access(["read:statuses"])

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "true"})
      assert length(json_response(res_conn, 200)) == 1

      res_conn = get(conn, "/api/v1/timelines/public", %{"local" => "false"})
      assert length(json_response(res_conn, 200)) == 2
    end
  end

  describe "direct" do
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

      conn_user_two =
        conn
        |> assign(:user, user_two)
        |> assign(:token, insert(:oauth_token, user: user_two, scopes: ["read:statuses"]))

      # Only direct should be visible here
      res_conn = get(conn_user_two, "api/v1/timelines/direct")

      [status] = json_response(res_conn, :ok)

      assert %{"visibility" => "direct"} = status
      assert status["url"] != direct.data["id"]

      # User should be able to see their own direct message
      res_conn =
        build_conn()
        |> assign(:user, user_one)
        |> assign(:token, insert(:oauth_token, user: user_one, scopes: ["read:statuses"]))
        |> get("api/v1/timelines/direct")

      [status] = json_response(res_conn, :ok)

      assert %{"visibility" => "direct"} = status

      # Both should be visible here
      res_conn = get(conn_user_two, "api/v1/timelines/home")

      [_s1, _s2] = json_response(res_conn, :ok)

      # Test pagination
      Enum.each(1..20, fn _ ->
        {:ok, _} =
          CommonAPI.post(user_one, %{
            "status" => "Hi @#{user_two.nickname}!",
            "visibility" => "direct"
          })
      end)

      res_conn = get(conn_user_two, "api/v1/timelines/direct")

      statuses = json_response(res_conn, :ok)
      assert length(statuses) == 20

      res_conn =
        get(conn_user_two, "api/v1/timelines/direct", %{max_id: List.last(statuses)["id"]})

      [status] = json_response(res_conn, :ok)

      assert status["url"] != direct.data["id"]
    end

    test "doesn't include DMs from blocked users" do
      %{user: blocker, conn: conn} = oauth_access(["read:statuses"])
      blocked = insert(:user)
      other_user = insert(:user)
      {:ok, _user_relationship} = User.block(blocker, blocked)

      {:ok, _blocked_direct} =
        CommonAPI.post(blocked, %{
          "status" => "Hi @#{blocker.nickname}!",
          "visibility" => "direct"
        })

      {:ok, direct} =
        CommonAPI.post(other_user, %{
          "status" => "Hi @#{blocker.nickname}!",
          "visibility" => "direct"
        })

      res_conn = get(conn, "api/v1/timelines/direct")

      [status] = json_response(res_conn, :ok)
      assert status["id"] == direct.id
    end
  end

  describe "list" do
    setup do: oauth_access(["read:lists"])

    test "list timeline", %{user: user, conn: conn} do
      other_user = insert(:user)
      {:ok, _activity_one} = CommonAPI.post(user, %{"status" => "Marisa is cute."})
      {:ok, activity_two} = CommonAPI.post(other_user, %{"status" => "Marisa is cute."})
      {:ok, list} = Pleroma.List.create("name", user)
      {:ok, list} = Pleroma.List.follow(list, other_user)

      conn = get(conn, "/api/v1/timelines/list/#{list.id}")

      assert [%{"id" => id}] = json_response(conn, :ok)

      assert id == to_string(activity_two.id)
    end

    test "list timeline does not leak non-public statuses for unfollowed users", %{
      user: user,
      conn: conn
    } do
      other_user = insert(:user)
      {:ok, activity_one} = CommonAPI.post(other_user, %{"status" => "Marisa is cute."})

      {:ok, _activity_two} =
        CommonAPI.post(other_user, %{
          "status" => "Marisa is cute.",
          "visibility" => "private"
        })

      {:ok, list} = Pleroma.List.create("name", user)
      {:ok, list} = Pleroma.List.follow(list, other_user)

      conn = get(conn, "/api/v1/timelines/list/#{list.id}")

      assert [%{"id" => id}] = json_response(conn, :ok)

      assert id == to_string(activity_one.id)
    end
  end

  describe "hashtag" do
    setup do: oauth_access(["n/a"])

    @tag capture_log: true
    test "hashtag timeline", %{conn: conn} do
      following = insert(:user)

      {:ok, activity} = CommonAPI.post(following, %{"status" => "test #2hu"})

      nconn = get(conn, "/api/v1/timelines/tag/2hu")

      assert [%{"id" => id}] = json_response(nconn, :ok)

      assert id == to_string(activity.id)

      # works for different capitalization too
      nconn = get(conn, "/api/v1/timelines/tag/2HU")

      assert [%{"id" => id}] = json_response(nconn, :ok)

      assert id == to_string(activity.id)
    end

    test "multi-hashtag timeline", %{conn: conn} do
      user = insert(:user)

      {:ok, activity_test} = CommonAPI.post(user, %{"status" => "#test"})
      {:ok, activity_test1} = CommonAPI.post(user, %{"status" => "#test #test1"})
      {:ok, activity_none} = CommonAPI.post(user, %{"status" => "#test #none"})

      any_test = get(conn, "/api/v1/timelines/tag/test", %{"any" => ["test1"]})

      [status_none, status_test1, status_test] = json_response(any_test, :ok)

      assert to_string(activity_test.id) == status_test["id"]
      assert to_string(activity_test1.id) == status_test1["id"]
      assert to_string(activity_none.id) == status_none["id"]

      restricted_test =
        get(conn, "/api/v1/timelines/tag/test", %{"all" => ["test1"], "none" => ["none"]})

      assert [status_test1] == json_response(restricted_test, :ok)

      all_test = get(conn, "/api/v1/timelines/tag/test", %{"all" => ["none"]})

      assert [status_none] == json_response(all_test, :ok)
    end
  end
end
