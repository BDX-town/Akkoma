# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.TwitterAPI.UtilControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Notification
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI
  import Pleroma.Factory
  import Mock

  setup do
    Tesla.Mock.mock(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  clear_config([:instance])
  clear_config([:frontend_configurations, :pleroma_fe])
  clear_config([:user, :deny_follow_blocked])

  describe "POST /api/pleroma/follow_import" do
    test "it returns HTTP 200", %{conn: conn} do
      user1 = insert(:user)
      user2 = insert(:user)

      response =
        conn
        |> assign(:user, user1)
        |> post("/api/pleroma/follow_import", %{"list" => "#{user2.ap_id}"})
        |> json_response(:ok)

      assert response == "job started"
    end

    test "it imports follow lists from file", %{conn: conn} do
      user1 = insert(:user)
      user2 = insert(:user)

      with_mocks([
        {File, [],
         read!: fn "follow_list.txt" ->
           "Account address,Show boosts\n#{user2.ap_id},true"
         end},
        {PleromaJobQueue, [:passthrough], []}
      ]) do
        response =
          conn
          |> assign(:user, user1)
          |> post("/api/pleroma/follow_import", %{"list" => %Plug.Upload{path: "follow_list.txt"}})
          |> json_response(:ok)

        assert called(
                 PleromaJobQueue.enqueue(
                   :background,
                   User,
                   [:follow_import, user1, [user2.ap_id]]
                 )
               )

        assert response == "job started"
      end
    end

    test "it imports new-style mastodon follow lists", %{conn: conn} do
      user1 = insert(:user)
      user2 = insert(:user)

      response =
        conn
        |> assign(:user, user1)
        |> post("/api/pleroma/follow_import", %{
          "list" => "Account address,Show boosts\n#{user2.ap_id},true"
        })
        |> json_response(:ok)

      assert response == "job started"
    end

    test "requires 'follow' permission", %{conn: conn} do
      token1 = insert(:oauth_token, scopes: ["read", "write"])
      token2 = insert(:oauth_token, scopes: ["follow"])
      another_user = insert(:user)

      for token <- [token1, token2] do
        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token.token}")
          |> post("/api/pleroma/follow_import", %{"list" => "#{another_user.ap_id}"})

        if token == token1 do
          assert %{"error" => "Insufficient permissions: follow."} == json_response(conn, 403)
        else
          assert json_response(conn, 200)
        end
      end
    end
  end

  describe "POST /api/pleroma/blocks_import" do
    test "it returns HTTP 200", %{conn: conn} do
      user1 = insert(:user)
      user2 = insert(:user)

      response =
        conn
        |> assign(:user, user1)
        |> post("/api/pleroma/blocks_import", %{"list" => "#{user2.ap_id}"})
        |> json_response(:ok)

      assert response == "job started"
    end

    test "it imports blocks users from file", %{conn: conn} do
      user1 = insert(:user)
      user2 = insert(:user)
      user3 = insert(:user)

      with_mocks([
        {File, [], read!: fn "blocks_list.txt" -> "#{user2.ap_id} #{user3.ap_id}" end},
        {PleromaJobQueue, [:passthrough], []}
      ]) do
        response =
          conn
          |> assign(:user, user1)
          |> post("/api/pleroma/blocks_import", %{"list" => %Plug.Upload{path: "blocks_list.txt"}})
          |> json_response(:ok)

        assert called(
                 PleromaJobQueue.enqueue(
                   :background,
                   User,
                   [:blocks_import, user1, [user2.ap_id, user3.ap_id]]
                 )
               )

        assert response == "job started"
      end
    end
  end

  describe "POST /api/pleroma/notifications/read" do
    test "it marks a single notification as read", %{conn: conn} do
      user1 = insert(:user)
      user2 = insert(:user)
      {:ok, activity1} = CommonAPI.post(user2, %{"status" => "hi @#{user1.nickname}"})
      {:ok, activity2} = CommonAPI.post(user2, %{"status" => "hi @#{user1.nickname}"})
      {:ok, [notification1]} = Notification.create_notifications(activity1)
      {:ok, [notification2]} = Notification.create_notifications(activity2)

      conn
      |> assign(:user, user1)
      |> post("/api/pleroma/notifications/read", %{"id" => "#{notification1.id}"})
      |> json_response(:ok)

      assert Repo.get(Notification, notification1.id).seen
      refute Repo.get(Notification, notification2.id).seen
    end

    test "it returns error when notification not found", %{conn: conn} do
      user1 = insert(:user)

      response =
        conn
        |> assign(:user, user1)
        |> post("/api/pleroma/notifications/read", %{"id" => "22222222222222"})
        |> json_response(403)

      assert response == %{"error" => "Cannot get notification"}
    end
  end

  describe "PUT /api/pleroma/notification_settings" do
    test "it updates notification settings", %{conn: conn} do
      user = insert(:user)

      conn
      |> assign(:user, user)
      |> put("/api/pleroma/notification_settings", %{
        "followers" => false,
        "bar" => 1
      })
      |> json_response(:ok)

      user = Repo.get(User, user.id)

      assert %{
               "followers" => false,
               "follows" => true,
               "non_follows" => true,
               "non_followers" => true
             } == user.info.notification_settings
    end
  end

  describe "GET /api/statusnet/config" do
    test "it returns config in xml format", %{conn: conn} do
      instance = Pleroma.Config.get(:instance)

      response =
        conn
        |> put_req_header("accept", "application/xml")
        |> get("/api/statusnet/config")
        |> response(:ok)

      assert response ==
               "<config>\n<site>\n<name>#{Keyword.get(instance, :name)}</name>\n<site>#{
                 Pleroma.Web.base_url()
               }</site>\n<textlimit>#{Keyword.get(instance, :limit)}</textlimit>\n<closed>#{
                 !Keyword.get(instance, :registrations_open)
               }</closed>\n</site>\n</config>\n"
    end

    test "it returns config in json format", %{conn: conn} do
      instance = Pleroma.Config.get(:instance)
      Pleroma.Config.put([:instance, :managed_config], true)
      Pleroma.Config.put([:instance, :registrations_open], false)
      Pleroma.Config.put([:instance, :invites_enabled], true)
      Pleroma.Config.put([:instance, :public], false)
      Pleroma.Config.put([:frontend_configurations, :pleroma_fe], %{theme: "asuka-hospital"})

      response =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/statusnet/config")
        |> json_response(:ok)

      expected_data = %{
        "site" => %{
          "accountActivationRequired" => "0",
          "closed" => "1",
          "description" => Keyword.get(instance, :description),
          "invitesEnabled" => "1",
          "name" => Keyword.get(instance, :name),
          "pleromafe" => %{"theme" => "asuka-hospital"},
          "private" => "1",
          "safeDMMentionsEnabled" => "0",
          "server" => Pleroma.Web.base_url(),
          "textlimit" => to_string(Keyword.get(instance, :limit)),
          "uploadlimit" => %{
            "avatarlimit" => to_string(Keyword.get(instance, :avatar_upload_limit)),
            "backgroundlimit" => to_string(Keyword.get(instance, :background_upload_limit)),
            "bannerlimit" => to_string(Keyword.get(instance, :banner_upload_limit)),
            "uploadlimit" => to_string(Keyword.get(instance, :upload_limit))
          },
          "vapidPublicKey" => Keyword.get(Pleroma.Web.Push.vapid_config(), :public_key)
        }
      }

      assert response == expected_data
    end

    test "returns the state of safe_dm_mentions flag", %{conn: conn} do
      Pleroma.Config.put([:instance, :safe_dm_mentions], true)

      response =
        conn
        |> get("/api/statusnet/config.json")
        |> json_response(:ok)

      assert response["site"]["safeDMMentionsEnabled"] == "1"

      Pleroma.Config.put([:instance, :safe_dm_mentions], false)

      response =
        conn
        |> get("/api/statusnet/config.json")
        |> json_response(:ok)

      assert response["site"]["safeDMMentionsEnabled"] == "0"
    end

    test "it returns the managed config", %{conn: conn} do
      Pleroma.Config.put([:instance, :managed_config], false)
      Pleroma.Config.put([:frontend_configurations, :pleroma_fe], %{theme: "asuka-hospital"})

      response =
        conn
        |> get("/api/statusnet/config.json")
        |> json_response(:ok)

      refute response["site"]["pleromafe"]

      Pleroma.Config.put([:instance, :managed_config], true)

      response =
        conn
        |> get("/api/statusnet/config.json")
        |> json_response(:ok)

      assert response["site"]["pleromafe"] == %{"theme" => "asuka-hospital"}
    end
  end

  describe "GET /api/pleroma/frontend_configurations" do
    test "returns everything in :pleroma, :frontend_configurations", %{conn: conn} do
      config = [
        frontend_a: %{
          x: 1,
          y: 2
        },
        frontend_b: %{
          z: 3
        }
      ]

      Pleroma.Config.put(:frontend_configurations, config)

      response =
        conn
        |> get("/api/pleroma/frontend_configurations")
        |> json_response(:ok)

      assert response == Jason.encode!(config |> Enum.into(%{})) |> Jason.decode!()
    end
  end

  describe "/api/pleroma/emoji" do
    test "returns json with custom emoji with tags", %{conn: conn} do
      emoji =
        conn
        |> get("/api/pleroma/emoji")
        |> json_response(200)

      assert Enum.all?(emoji, fn
               {_key,
                %{
                  "image_url" => url,
                  "tags" => tags
                }} ->
                 is_binary(url) and is_list(tags)
             end)
    end
  end

  describe "GET /ostatus_subscribe - remote_follow/2" do
    test "adds status to pleroma instance if the `acct` is a status", %{conn: conn} do
      conn =
        get(
          conn,
          "/ostatus_subscribe?acct=https://mastodon.social/users/emelie/statuses/101849165031453009"
        )

      assert redirected_to(conn) =~ "/notice/"
    end

    test "show follow account page if the `acct` is a account link", %{conn: conn} do
      response =
        get(
          conn,
          "/ostatus_subscribe?acct=https://mastodon.social/users/emelie"
        )

      assert html_response(response, 200) =~ "Log in to follow"
    end

    test "show follow page if the `acct` is a account link", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> get("/ostatus_subscribe?acct=https://mastodon.social/users/emelie")

      assert html_response(response, 200) =~ "Remote follow"
    end

    test "show follow page with error when user cannot fecth by `acct` link", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> get("/ostatus_subscribe?acct=https://mastodon.social/users/not_found")

      assert html_response(response, 200) =~ "Error fetching user"
    end
  end

  describe "POST /ostatus_subscribe - do_remote_follow/2 with assigned user " do
    test "follows user", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> post("/ostatus_subscribe", %{"user" => %{"id" => user2.id}})
        |> response(200)

      assert response =~ "Account followed!"
      assert user2.follower_address in refresh_record(user).following
    end

    test "returns error when user is deactivated", %{conn: conn} do
      user = insert(:user, info: %{deactivated: true})
      user2 = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> post("/ostatus_subscribe", %{"user" => %{"id" => user2.id}})
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns error when user is blocked", %{conn: conn} do
      Pleroma.Config.put([:user, :deny_follow_blocked], true)
      user = insert(:user)
      user2 = insert(:user)

      {:ok, _user} = Pleroma.User.block(user2, user)

      response =
        conn
        |> assign(:user, user)
        |> post("/ostatus_subscribe", %{"user" => %{"id" => user2.id}})
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns error when followee not found", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> post("/ostatus_subscribe", %{"user" => %{"id" => "jimm"}})
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns success result when user already in followers", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)
      {:ok, _, _, _} = CommonAPI.follow(user, user2)

      response =
        conn
        |> assign(:user, refresh_record(user))
        |> post("/ostatus_subscribe", %{"user" => %{"id" => user2.id}})
        |> response(200)

      assert response =~ "Account followed!"
    end
  end

  describe "POST /ostatus_subscribe - do_remote_follow/2 without assigned user " do
    test "follows", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)

      response =
        conn
        |> post("/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test", "id" => user2.id}
        })
        |> response(200)

      assert response =~ "Account followed!"
      assert user2.follower_address in refresh_record(user).following
    end

    test "returns error when followee not found", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> post("/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test", "id" => "jimm"}
        })
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns error when login invalid", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> post("/ostatus_subscribe", %{
          "authorization" => %{"name" => "jimm", "password" => "test", "id" => user.id}
        })
        |> response(200)

      assert response =~ "Wrong username or password"
    end

    test "returns error when password invalid", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)

      response =
        conn
        |> post("/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "42", "id" => user2.id}
        })
        |> response(200)

      assert response =~ "Wrong username or password"
    end

    test "returns error when user is blocked", %{conn: conn} do
      Pleroma.Config.put([:user, :deny_follow_blocked], true)
      user = insert(:user)
      user2 = insert(:user)
      {:ok, _user} = Pleroma.User.block(user2, user)

      response =
        conn
        |> post("/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test", "id" => user2.id}
        })
        |> response(200)

      assert response =~ "Error following account"
    end
  end

  describe "GET /api/pleroma/healthcheck" do
    clear_config([:instance, :healthcheck])

    test "returns 503 when healthcheck disabled", %{conn: conn} do
      Pleroma.Config.put([:instance, :healthcheck], false)

      response =
        conn
        |> get("/api/pleroma/healthcheck")
        |> json_response(503)

      assert response == %{}
    end

    test "returns 200 when healthcheck enabled and all ok", %{conn: conn} do
      Pleroma.Config.put([:instance, :healthcheck], true)

      with_mock Pleroma.Healthcheck,
        system_info: fn -> %Pleroma.Healthcheck{healthy: true} end do
        response =
          conn
          |> get("/api/pleroma/healthcheck")
          |> json_response(200)

        assert %{
                 "active" => _,
                 "healthy" => true,
                 "idle" => _,
                 "memory_used" => _,
                 "pool_size" => _
               } = response
      end
    end

    test "returns 503 when healthcheck enabled and  health is false", %{conn: conn} do
      Pleroma.Config.put([:instance, :healthcheck], true)

      with_mock Pleroma.Healthcheck,
        system_info: fn -> %Pleroma.Healthcheck{healthy: false} end do
        response =
          conn
          |> get("/api/pleroma/healthcheck")
          |> json_response(503)

        assert %{
                 "active" => _,
                 "healthy" => false,
                 "idle" => _,
                 "memory_used" => _,
                 "pool_size" => _
               } = response
      end
    end
  end

  describe "POST /api/pleroma/disable_account" do
    test "it returns HTTP 200", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> post("/api/pleroma/disable_account", %{"password" => "test"})
        |> json_response(:ok)

      assert response == %{"status" => "success"}

      user = User.get_cached_by_id(user.id)

      assert user.info.deactivated == true
    end

    test "it returns returns when password invalid", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> post("/api/pleroma/disable_account", %{"password" => "test1"})
        |> json_response(:ok)

      assert response == %{"error" => "Invalid password."}
      user = User.get_cached_by_id(user.id)

      refute user.info.deactivated
    end
  end

  describe "GET /api/statusnet/version" do
    test "it returns version in xml format", %{conn: conn} do
      response =
        conn
        |> put_req_header("accept", "application/xml")
        |> get("/api/statusnet/version")
        |> response(:ok)

      assert response == "<version>#{Pleroma.Application.named_version()}</version>"
    end

    test "it returns version in json format", %{conn: conn} do
      response =
        conn
        |> put_req_header("accept", "application/json")
        |> get("/api/statusnet/version")
        |> json_response(:ok)

      assert response == "#{Pleroma.Application.named_version()}"
    end
  end

  describe "POST /main/ostatus - remote_subscribe/2" do
    test "renders subscribe form", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> post("/main/ostatus", %{"nickname" => user.nickname, "profile" => ""})
        |> response(:ok)

      refute response =~ "Could not find user"
      assert response =~ "Remotely follow #{user.nickname}"
    end

    test "renders subscribe form with error when user not found", %{conn: conn} do
      response =
        conn
        |> post("/main/ostatus", %{"nickname" => "nickname", "profile" => ""})
        |> response(:ok)

      assert response =~ "Could not find user"
      refute response =~ "Remotely follow"
    end

    test "it redirect to webfinger url", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user, ap_id: "shp@social.heldscal.la")

      conn =
        conn
        |> post("/main/ostatus", %{
          "user" => %{"nickname" => user.nickname, "profile" => user2.ap_id}
        })

      assert redirected_to(conn) ==
               "https://social.heldscal.la/main/ostatussub?profile=#{user.ap_id}"
    end

    test "it renders form with error when use not found", %{conn: conn} do
      user2 = insert(:user, ap_id: "shp@social.heldscal.la")

      response =
        conn
        |> post("/main/ostatus", %{"user" => %{"nickname" => "jimm", "profile" => user2.ap_id}})
        |> response(:ok)

      assert response =~ "Something went wrong."
    end
  end

  test "it returns new captcha", %{conn: conn} do
    with_mock Pleroma.Captcha,
      new: fn -> "test_captcha" end do
      resp =
        conn
        |> get("/api/pleroma/captcha")
        |> response(200)

      assert resp == "\"test_captcha\""
      assert called(Pleroma.Captcha.new())
    end
  end
end
