# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.AccountControllerTest do
  use Pleroma.Web.ConnCase

  alias Pleroma.Config
  alias Pleroma.Repo
  alias Pleroma.Tests.ObanHelpers
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI

  import Pleroma.Factory
  import Swoosh.TestAssertions

  @image "data:image/gif;base64,R0lGODlhEAAQAMQAAORHHOVSKudfOulrSOp3WOyDZu6QdvCchPGolfO0o/XBs/fNwfjZ0frl3/zy7////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAkAABAALAAAAAAQABAAAAVVICSOZGlCQAosJ6mu7fiyZeKqNKToQGDsM8hBADgUXoGAiqhSvp5QAnQKGIgUhwFUYLCVDFCrKUE1lBavAViFIDlTImbKC5Gm2hB0SlBCBMQiB0UjIQA7"

  describe "POST /api/v1/pleroma/accounts/confirmation_resend" do
    setup do
      {:ok, user} =
        insert(:user)
        |> User.change_info(&User.Info.confirmation_changeset(&1, need_confirmation: true))
        |> Repo.update()

      assert user.info.confirmation_pending

      [user: user]
    end

    clear_config([:instance, :account_activation_required]) do
      Config.put([:instance, :account_activation_required], true)
    end

    test "resend account confirmation email", %{conn: conn, user: user} do
      conn
      |> assign(:user, user)
      |> post("/api/v1/pleroma/accounts/confirmation_resend?email=#{user.email}")
      |> json_response(:no_content)

      ObanHelpers.perform_all()

      email = Pleroma.Emails.UserEmail.account_confirmation_email(user)
      notify_email = Config.get([:instance, :notify_email])
      instance_name = Config.get([:instance, :name])

      assert_email_sent(
        from: {instance_name, notify_email},
        to: {user.name, user.email},
        html_body: email.html_body
      )
    end
  end

  describe "PATCH /api/v1/pleroma/accounts/update_avatar" do
    test "user avatar can be set", %{conn: conn} do
      user = insert(:user)
      avatar_image = File.read!("test/fixtures/avatar_data_uri")

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/pleroma/accounts/update_avatar", %{img: avatar_image})

      user = refresh_record(user)

      assert %{
               "name" => _,
               "type" => _,
               "url" => [
                 %{
                   "href" => _,
                   "mediaType" => _,
                   "type" => _
                 }
               ]
             } = user.avatar

      assert %{"url" => _} = json_response(conn, 200)
    end

    test "user avatar can be reset", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/pleroma/accounts/update_avatar", %{img: ""})

      user = User.get_cached_by_id(user.id)

      assert user.avatar == nil

      assert %{"url" => nil} = json_response(conn, 200)
    end
  end

  describe "PATCH /api/v1/pleroma/accounts/update_banner" do
    test "can set profile banner", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/pleroma/accounts/update_banner", %{"banner" => @image})

      user = refresh_record(user)
      assert user.info.banner["type"] == "Image"

      assert %{"url" => _} = json_response(conn, 200)
    end

    test "can reset profile banner", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/pleroma/accounts/update_banner", %{"banner" => ""})

      user = refresh_record(user)
      assert user.info.banner == %{}

      assert %{"url" => nil} = json_response(conn, 200)
    end
  end

  describe "PATCH /api/v1/pleroma/accounts/update_background" do
    test "background image can be set", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/pleroma/accounts/update_background", %{"img" => @image})

      user = refresh_record(user)
      assert user.info.background["type"] == "Image"
      assert %{"url" => _} = json_response(conn, 200)
    end

    test "background image can be reset", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> patch("/api/v1/pleroma/accounts/update_background", %{"img" => ""})

      user = refresh_record(user)
      assert user.info.background == %{}
      assert %{"url" => nil} = json_response(conn, 200)
    end
  end

  describe "getting favorites timeline of specified user" do
    setup do
      [current_user, user] = insert_pair(:user, %{info: %{hide_favorites: false}})
      [current_user: current_user, user: user]
    end

    test "returns list of statuses favorited by specified user", %{
      conn: conn,
      current_user: current_user,
      user: user
    } do
      [activity | _] = insert_pair(:note_activity)
      CommonAPI.favorite(activity.id, user)

      response =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")
        |> json_response(:ok)

      [like] = response

      assert length(response) == 1
      assert like["id"] == activity.id
    end

    test "returns favorites for specified user_id when user is not logged in", %{
      conn: conn,
      user: user
    } do
      activity = insert(:note_activity)
      CommonAPI.favorite(activity.id, user)

      response =
        conn
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")
        |> json_response(:ok)

      assert length(response) == 1
    end

    test "returns favorited DM only when user is logged in and he is one of recipients", %{
      conn: conn,
      current_user: current_user,
      user: user
    } do
      {:ok, direct} =
        CommonAPI.post(current_user, %{
          "status" => "Hi @#{user.nickname}!",
          "visibility" => "direct"
        })

      CommonAPI.favorite(direct.id, user)

      response =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")
        |> json_response(:ok)

      assert length(response) == 1

      anonymous_response =
        conn
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")
        |> json_response(:ok)

      assert Enum.empty?(anonymous_response)
    end

    test "does not return others' favorited DM when user is not one of recipients", %{
      conn: conn,
      current_user: current_user,
      user: user
    } do
      user_two = insert(:user)

      {:ok, direct} =
        CommonAPI.post(user_two, %{
          "status" => "Hi @#{user.nickname}!",
          "visibility" => "direct"
        })

      CommonAPI.favorite(direct.id, user)

      response =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")
        |> json_response(:ok)

      assert Enum.empty?(response)
    end

    test "paginates favorites using since_id and max_id", %{
      conn: conn,
      current_user: current_user,
      user: user
    } do
      activities = insert_list(10, :note_activity)

      Enum.each(activities, fn activity ->
        CommonAPI.favorite(activity.id, user)
      end)

      third_activity = Enum.at(activities, 2)
      seventh_activity = Enum.at(activities, 6)

      response =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites", %{
          since_id: third_activity.id,
          max_id: seventh_activity.id
        })
        |> json_response(:ok)

      assert length(response) == 3
      refute third_activity in response
      refute seventh_activity in response
    end

    test "limits favorites using limit parameter", %{
      conn: conn,
      current_user: current_user,
      user: user
    } do
      7
      |> insert_list(:note_activity)
      |> Enum.each(fn activity ->
        CommonAPI.favorite(activity.id, user)
      end)

      response =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites", %{limit: "3"})
        |> json_response(:ok)

      assert length(response) == 3
    end

    test "returns empty response when user does not have any favorited statuses", %{
      conn: conn,
      current_user: current_user,
      user: user
    } do
      response =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")
        |> json_response(:ok)

      assert Enum.empty?(response)
    end

    test "returns 404 error when specified user is not exist", %{conn: conn} do
      conn = get(conn, "/api/v1/pleroma/accounts/test/favourites")

      assert json_response(conn, 404) == %{"error" => "Record not found"}
    end

    test "returns 403 error when user has hidden own favorites", %{
      conn: conn,
      current_user: current_user
    } do
      user = insert(:user, %{info: %{hide_favorites: true}})
      activity = insert(:note_activity)
      CommonAPI.favorite(activity.id, user)

      conn =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")

      assert json_response(conn, 403) == %{"error" => "Can't get favorites"}
    end

    test "hides favorites for new users by default", %{conn: conn, current_user: current_user} do
      user = insert(:user)
      activity = insert(:note_activity)
      CommonAPI.favorite(activity.id, user)

      conn =
        conn
        |> assign(:user, current_user)
        |> get("/api/v1/pleroma/accounts/#{user.id}/favourites")

      assert user.info.hide_favorites
      assert json_response(conn, 403) == %{"error" => "Can't get favorites"}
    end
  end

  describe "subscribing / unsubscribing" do
    test "subscribing / unsubscribing to a user", %{conn: conn} do
      user = insert(:user)
      subscription_target = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/pleroma/accounts/#{subscription_target.id}/subscribe")

      assert %{"id" => _id, "subscribing" => true} = json_response(conn, 200)

      conn =
        build_conn()
        |> assign(:user, user)
        |> post("/api/v1/pleroma/accounts/#{subscription_target.id}/unsubscribe")

      assert %{"id" => _id, "subscribing" => false} = json_response(conn, 200)
    end
  end

  describe "subscribing" do
    test "returns 404 when subscription_target not found", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/pleroma/accounts/target_id/subscribe")

      assert %{"error" => "Record not found"} = json_response(conn, 404)
    end
  end

  describe "unsubscribing" do
    test "returns 404 when subscription_target not found", %{conn: conn} do
      user = insert(:user)

      conn =
        conn
        |> assign(:user, user)
        |> post("/api/v1/pleroma/accounts/target_id/unsubscribe")

      assert %{"error" => "Record not found"} = json_response(conn, 404)
    end
  end
end
