# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.NotificationController do
  use Pleroma.Web, :controller

  import Pleroma.Web.ControllerHelper, only: [add_link_headers: 2]

  alias Pleroma.Notification
  alias Pleroma.Web.MastodonAPI.MastodonAPI

  # GET /api/v1/notifications
  def index(%{assigns: %{user: user}} = conn, params) do
    notifications = MastodonAPI.get_notifications(user, params)

    conn
    |> add_link_headers(notifications)
    |> render("index.json", notifications: notifications, for: user)
  end

  # GET /api/v1/notifications/:id
  def show(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    with {:ok, notification} <- Notification.get(user, id) do
      render(conn, "show.json", notification: notification, for: user)
    else
      {:error, reason} ->
        conn
        |> put_status(:forbidden)
        |> json(%{"error" => reason})
    end
  end

  # POST /api/v1/notifications/clear
  def clear(%{assigns: %{user: user}} = conn, _params) do
    Notification.clear(user)
    json(conn, %{})
  end

  # POST /api/v1/notifications/dismiss
  def dismiss(%{assigns: %{user: user}} = conn, %{"id" => id} = _params) do
    with {:ok, _notif} <- Notification.dismiss(user, id) do
      json(conn, %{})
    else
      {:error, reason} ->
        conn
        |> put_status(:forbidden)
        |> json(%{"error" => reason})
    end
  end

  # DELETE /api/v1/notifications/destroy_multiple
  def destroy_multiple(%{assigns: %{user: user}} = conn, %{"ids" => ids} = _params) do
    Notification.destroy_multiple(user, ids)
    json(conn, %{})
  end
end
