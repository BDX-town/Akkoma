# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.TwitterAPI.RemoteFollowControllerTest do
  use Pleroma.Web.ConnCase, async: false

  alias Pleroma.MFA
  alias Pleroma.MFA.TOTP
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI

  import ExUnit.CaptureLog
  import Pleroma.Factory
  import Ecto.Query

  setup_all do: clear_config([:instance, :federating], true)
  setup do: clear_config([:user, :deny_follow_blocked])
  setup do: clear_config([Pleroma.Upload, :uploader], Pleroma.Uploaders.Local)

  describe "GET /ostatus_subscribe - remote_follow/2" do
    test "adds status to pleroma instance if the `acct` is a status", %{conn: conn} do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://mastodon.social/users/emelie/statuses/101849165031453009"} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body: File.read!("test/fixtures/tesla_mock/status.emelie.json")
          }

        %{method: :get, url: "https://mastodon.social/users/emelie/collections/featured"} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body:
              File.read!("test/fixtures/users_mock/masto_featured.json")
              |> String.replace("{{domain}}", "mastodon.social")
              |> String.replace("{{nickname}}", "emelie")
          }

        %{method: :get, url: "https://mastodon.social/users/emelie"} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body: File.read!("test/fixtures/tesla_mock/emelie.json")
          }
      end)

      assert conn
             |> get(
               ~p[/ostatus_subscribe?#{[acct: "https://mastodon.social/users/emelie/statuses/101849165031453009"]}]
             )
             |> redirected_to() =~ "/notice/"
    end

    test "show follow account page if the `acct` is a account link", %{conn: conn} do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://mastodon.social/users/emelie"} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body: File.read!("test/fixtures/tesla_mock/emelie.json")
          }

        %{method: :get, url: "https://mastodon.social/users/emelie/collections/featured"} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body:
              File.read!("test/fixtures/users_mock/masto_featured.json")
              |> String.replace("{{domain}}", "mastodon.social")
              |> String.replace("{{nickname}}", "emelie")
          }
      end)

      response =
        conn
        |> get(~p[/ostatus_subscribe?#{[acct: "https://mastodon.social/users/emelie"]}])
        |> html_response(200)

      assert response =~ "Log in to follow"
    end

    test "show follow page if the `acct` is a account link", %{conn: conn} do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://mastodon.social/users/emelie"} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body: File.read!("test/fixtures/tesla_mock/emelie.json")
          }

        %{method: :get, url: "https://mastodon.social/users/emelie/collections/featured"} ->
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "application/activity+json"}],
            body:
              File.read!("test/fixtures/users_mock/masto_featured.json")
              |> String.replace("{{domain}}", "mastodon.social")
              |> String.replace("{{nickname}}", "emelie")
          }
      end)

      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> get(~p[/ostatus_subscribe?#{[acct: "https://mastodon.social/users/emelie"]}])
        |> html_response(200)

      assert response =~ "Remote follow"
    end

    test "show follow page with error when user can not be fetched by `acct` link", %{conn: conn} do
      Tesla.Mock.mock(fn
        %{method: :get, url: "https://mastodon.social/users/not_found"} ->
          %Tesla.Env{
            status: 404
          }
      end)

      user = insert(:user)

      assert capture_log(fn ->
               response =
                 conn
                 |> assign(:user, user)
                 |> get(
                   ~p[/ostatus_subscribe?#{[acct: "https://mastodon.social/users/not_found"]}]
                 )
                 |> html_response(200)

               assert response =~ "Error fetching user"
             end) =~ "User doesn't exist (anymore): https://mastodon.social/users/not_found"
    end
  end

  describe "POST /ostatus_subscribe - do_follow/2 with assigned user " do
    test "required `follow | write:follows` scope", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)
      read_token = insert(:oauth_token, user: user, scopes: ["read"])

      assert capture_log(fn ->
               response =
                 conn
                 |> assign(:user, user)
                 |> assign(:token, read_token)
                 |> post(~p"/ostatus_subscribe", %{"user" => %{"id" => user2.id}})
                 |> response(200)

               assert response =~ "Error following account"
             end) =~ "Insufficient permissions: follow | write:follows."
    end

    test "follows user", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> assign(:token, insert(:oauth_token, user: user, scopes: ["write:follows"]))
        |> post(~p"/ostatus_subscribe", %{"user" => %{"id" => user2.id}})

      assert redirected_to(conn) == "/users/#{user2.id}"
    end

    test "returns error when user is deactivated", %{conn: conn} do
      user = insert(:user, is_active: false)
      user2 = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> post(~p"/ostatus_subscribe", %{"user" => %{"id" => user2.id}})
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns error when user is blocked", %{conn: conn} do
      clear_config([:user, :deny_follow_blocked], true)
      user = insert(:user)
      user2 = insert(:user)

      {:ok, _user_block} = Pleroma.User.block(user2, user)

      response =
        conn
        |> assign(:user, user)
        |> post(~p"/ostatus_subscribe", %{"user" => %{"id" => user2.id}})
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns error when followee not found", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> post(~p"/ostatus_subscribe", %{"user" => %{"id" => "jimm"}})
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns success result when user already in followers", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)
      {:ok, _, _, _} = CommonAPI.follow(user, user2)

      conn =
        conn
        |> assign(:user, refresh_record(user))
        |> assign(:token, insert(:oauth_token, user: user, scopes: ["write:follows"]))
        |> post(~p"/ostatus_subscribe", %{"user" => %{"id" => user2.id}})

      assert redirected_to(conn) == "/users/#{user2.id}"
    end
  end

  describe "POST /ostatus_subscribe - follow/2 with enabled Two-Factor Auth " do
    test "render the MFA login form", %{conn: conn} do
      otp_secret = TOTP.generate_secret()

      user =
        insert(:user,
          multi_factor_authentication_settings: %MFA.Settings{
            enabled: true,
            totp: %MFA.Settings.TOTP{secret: otp_secret, confirmed: true}
          }
        )

      user2 = insert(:user)

      response =
        conn
        |> post(~p"/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test", "id" => user2.id}
        })
        |> response(200)

      mfa_token = Pleroma.Repo.one(from(q in Pleroma.MFA.Token, where: q.user_id == ^user.id))

      assert response =~ "Two-factor authentication"
      assert response =~ "Authentication code"
      assert response =~ mfa_token.token
      refute user2.follower_address in User.following(user)
    end

    test "returns error when password is incorrect", %{conn: conn} do
      otp_secret = TOTP.generate_secret()

      user =
        insert(:user,
          multi_factor_authentication_settings: %MFA.Settings{
            enabled: true,
            totp: %MFA.Settings.TOTP{secret: otp_secret, confirmed: true}
          }
        )

      user2 = insert(:user)

      response =
        conn
        |> post(~p"/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test1", "id" => user2.id}
        })
        |> response(200)

      assert response =~ "Wrong username or password"
      refute user2.follower_address in User.following(user)
    end

    test "follows", %{conn: conn} do
      otp_secret = TOTP.generate_secret()

      user =
        insert(:user,
          multi_factor_authentication_settings: %MFA.Settings{
            enabled: true,
            totp: %MFA.Settings.TOTP{secret: otp_secret, confirmed: true}
          }
        )

      {:ok, %{token: token}} = MFA.Token.create(user)

      user2 = insert(:user)
      otp_token = TOTP.generate_token(otp_secret)

      conn =
        conn
        |> post(
          ~p"/ostatus_subscribe",
          %{
            "mfa" => %{"code" => otp_token, "token" => token, "id" => user2.id}
          }
        )

      assert redirected_to(conn) == "/users/#{user2.id}"
      assert user2.follower_address in User.following(user)
    end

    test "returns error when auth code is incorrect", %{conn: conn} do
      otp_secret = TOTP.generate_secret()

      user =
        insert(:user,
          multi_factor_authentication_settings: %MFA.Settings{
            enabled: true,
            totp: %MFA.Settings.TOTP{secret: otp_secret, confirmed: true}
          }
        )

      {:ok, %{token: token}} = MFA.Token.create(user)

      user2 = insert(:user)
      otp_token = TOTP.generate_token(TOTP.generate_secret())

      response =
        conn
        |> post(
          ~p"/ostatus_subscribe",
          %{
            "mfa" => %{"code" => otp_token, "token" => token, "id" => user2.id}
          }
        )
        |> response(200)

      assert response =~ "Wrong authentication code"
      refute user2.follower_address in User.following(user)
    end
  end

  describe "POST /ostatus_subscribe - follow/2 without assigned user " do
    test "follows", %{conn: conn} do
      user = insert(:user)
      user2 = insert(:user)

      conn =
        conn
        |> post(~p"/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test", "id" => user2.id}
        })

      assert redirected_to(conn) == "/users/#{user2.id}"
      assert user2.follower_address in User.following(user)
    end

    test "returns error when followee not found", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> post(~p"/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test", "id" => "jimm"}
        })
        |> response(200)

      assert response =~ "Error following account"
    end

    test "returns error when login invalid", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> post(~p"/ostatus_subscribe", %{
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
        |> post(~p"/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "42", "id" => user2.id}
        })
        |> response(200)

      assert response =~ "Wrong username or password"
    end

    test "returns error when user is blocked", %{conn: conn} do
      clear_config([:user, :deny_follow_blocked], true)
      user = insert(:user)
      user2 = insert(:user)
      {:ok, _user_block} = Pleroma.User.block(user2, user)

      response =
        conn
        |> post(~p"/ostatus_subscribe", %{
          "authorization" => %{"name" => user.nickname, "password" => "test", "id" => user2.id}
        })
        |> response(200)

      assert response =~ "Error following account"
    end
  end

  describe "avatar url" do
    test "without media proxy" do
      clear_config([:media_proxy, :enabled], false)

      user =
        insert(:user, %{
          local: false,
          avatar: %{"url" => [%{"href" => "https://remote.org/avatar.png"}]}
        })

      avatar_url = Pleroma.Web.TwitterAPI.RemoteFollowView.avatar_url(user)

      assert avatar_url == "https://remote.org/avatar.png"
    end

    test "with media proxy" do
      clear_config([:media_proxy, :enabled], true)

      user =
        insert(:user, %{
          local: false,
          avatar: %{"url" => [%{"href" => "https://remote.org/avatar.png"}]}
        })

      avatar_url = Pleroma.Web.TwitterAPI.RemoteFollowView.avatar_url(user)
      url = Pleroma.Web.Endpoint.url()

      assert String.starts_with?(avatar_url, url)
    end

    test "local avatar is not proxied" do
      clear_config([:media_proxy, :enabled], true)

      user =
        insert(:user, %{
          local: true,
          avatar: %{"url" => [%{"href" => "#{Pleroma.Web.Endpoint.url()}/localuser/avatar.png"}]}
        })

      avatar_url = Pleroma.Web.TwitterAPI.RemoteFollowView.avatar_url(user)

      assert avatar_url == "#{Pleroma.Web.Endpoint.url()}/localuser/avatar.png"
    end
  end
end
