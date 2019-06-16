# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.MastodonAPIController.UpdateCredentialsTest do
  alias Pleroma.Repo
  alias Pleroma.User

  use Pleroma.Web.ConnCase

  import Pleroma.Factory

  describe "updating credentials" do
    test "sets user settings in a generic way", %{conn: conn} do
      user = insert(:user)

      res_conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{
          "pleroma_settings_store" => %{
            pleroma_fe: %{
              theme: "bla"
            }
          }
        })

      assert user = json_response(res_conn, 200)
      assert user["pleroma"]["settings_store"] == %{"pleroma_fe" => %{"theme" => "bla"}}

      user = Repo.get(User, user["id"])

      res_conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{
          "pleroma_settings_store" => %{
            masto_fe: %{
              theme: "bla"
            }
          }
        })

      assert user = json_response(res_conn, 200)

      assert user["pleroma"]["settings_store"] ==
               %{
                 "pleroma_fe" => %{"theme" => "bla"},
                 "masto_fe" => %{"theme" => "bla"}
               }

      user = Repo.get(User, user["id"])

      res_conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{
          "pleroma_settings_store" => %{
            masto_fe: %{
              theme: "blub"
            }
          }
        })

      assert user = json_response(res_conn, 200)

      assert user["pleroma"]["settings_store"] ==
               %{
                 "pleroma_fe" => %{"theme" => "bla"},
                 "masto_fe" => %{"theme" => "blub"}
               }
    end

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

    test "updates the user's default scope", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{default_scope: "cofe"})

      assert user = json_response(conn, 200)
      assert user["source"]["privacy"] == "cofe"
    end

    test "updates the user's hide_followers status", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{hide_followers: "true"})

      assert user = json_response(conn, 200)
      assert user["pleroma"]["hide_followers"] == true
    end

    test "updates the user's skip_thread_containment option", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{skip_thread_containment: "true"})
        |> json_response(200)

      assert response["pleroma"]["skip_thread_containment"] == true
      assert refresh_record(user).info.skip_thread_containment
    end

    test "updates the user's hide_follows status", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{hide_follows: "true"})

      assert user = json_response(conn, 200)
      assert user["pleroma"]["hide_follows"] == true
    end

    test "updates the user's hide_favorites status", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{hide_favorites: "true"})

      assert user = json_response(conn, 200)
      assert user["pleroma"]["hide_favorites"] == true
    end

    test "updates the user's show_role status", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{show_role: "false"})

      assert user = json_response(conn, 200)
      assert user["source"]["pleroma"]["show_role"] == false
    end

    test "updates the user's no_rich_text status", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{no_rich_text: "true"})

      assert user = json_response(conn, 200)
      assert user["source"]["pleroma"]["no_rich_text"] == true
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

    test "updates the user's background", %{conn: conn} do
      user = insert(:user)

      new_header = %Plug.Upload{
        content_type: "image/jpg",
        path: Path.absname("test/fixtures/image.jpg"),
        filename: "an_image.jpg"
      }

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{
          "pleroma_background_image" => new_header
        })

      assert user_response = json_response(conn, 200)
      assert user_response["pleroma"]["background_image"]
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

    test "updates profile emojos", %{conn: conn} do
      user = insert(:user)

      note = "*sips :blank:*"
      name = "I am :firefox:"

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/accounts/update_credentials", %{
          "note" => note,
          "display_name" => name
        })

      assert json_response(conn, 200)

      conn =
        conn
        |> get("/api/v1/accounts/#{user.id}")

      assert user = json_response(conn, 200)

      assert user["note"] == note
      assert user["display_name"] == name
      assert [%{"shortcode" => "blank"}, %{"shortcode" => "firefox"}] = user["emojis"]
    end
  end
end
