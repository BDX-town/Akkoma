# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Feed.FeedController do
  use Pleroma.Web, :controller

  alias Fallback.RedirectController
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.ActivityPubController

  plug(Pleroma.Plugs.SetFormatPlug when action in [:feed_redirect])

  action_fallback(:errors)

  def feed_redirect(%{assigns: %{format: "html"}} = conn, %{"nickname" => nickname}) do
    with {_, %User{} = user} <- {:fetch_user, User.get_cached_by_nickname_or_id(nickname)} do
      RedirectController.redirector_with_meta(conn, %{user: user})
    end
  end

  def feed_redirect(%{assigns: %{format: format}} = conn, _params)
      when format in ["json", "activity+json"] do
    ActivityPubController.call(conn, :user)
  end

  def feed_redirect(conn, %{"nickname" => nickname}) do
    with {_, %User{} = user} <- {:fetch_user, User.get_cached_by_nickname(nickname)} do
      redirect(conn, external: "#{feed_url(conn, :feed, user.nickname)}.atom")
    end
  end

  def feed(conn, %{"nickname" => nickname} = params) do
    with {_, %User{} = user} <- {:fetch_user, User.get_cached_by_nickname(nickname)} do
      activities =
        %{
          "type" => ["Create"],
          "whole_db" => true,
          "actor_id" => user.ap_id
        }
        |> Map.merge(Map.take(params, ["max_id"]))
        |> ActivityPub.fetch_public_activities()

      conn
      |> put_resp_content_type("application/atom+xml")
      |> render("feed.xml",
        user: user,
        activities: activities,
        feed_config: Pleroma.Config.get([:feed])
      )
    end
  end

  def errors(conn, {:error, :not_found}) do
    render_error(conn, :not_found, "Not found")
  end

  def errors(conn, {:fetch_user, nil}), do: errors(conn, {:error, :not_found})

  def errors(conn, _) do
    render_error(conn, :internal_server_error, "Something went wrong")
  end
end
