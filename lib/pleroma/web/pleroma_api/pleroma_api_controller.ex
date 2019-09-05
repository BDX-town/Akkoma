# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.PleromaAPIController do
  use Pleroma.Web, :controller

  import Pleroma.Web.ControllerHelper, only: [add_link_headers: 7]

  alias Pleroma.Conversation.Participation
  alias Pleroma.Notification
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.MastodonAPI.ConversationView
  alias Pleroma.Web.MastodonAPI.NotificationView
  alias Pleroma.Web.MastodonAPI.StatusView

  def conversation(%{assigns: %{user: user}} = conn, %{"id" => participation_id}) do
    with %Participation{} = participation <- Participation.get(participation_id),
         true <- user.id == participation.user_id do
      conn
      |> put_view(ConversationView)
      |> render("participation.json", %{participation: participation, for: user})
    end
  end

  def conversation_statuses(
        %{assigns: %{user: user}} = conn,
        %{"id" => participation_id} = params
      ) do
    params =
      params
      |> Map.put("blocking_user", user)
      |> Map.put("muting_user", user)
      |> Map.put("user", user)

    participation =
      participation_id
      |> Participation.get(preload: [:conversation])

    if user.id == participation.user_id do
      activities =
        participation.conversation.ap_id
        |> ActivityPub.fetch_activities_for_context(params)
        |> Enum.reverse()

      conn
      |> add_link_headers(
        :conversation_statuses,
        activities,
        participation_id,
        params,
        nil,
        &pleroma_api_url/4
      )
      |> put_view(StatusView)
      |> render("index.json", %{activities: activities, for: user, as: :activity})
    end
  end

  def update_conversation(
        %{assigns: %{user: user}} = conn,
        %{"id" => participation_id, "recipients" => recipients}
      ) do
    participation =
      participation_id
      |> Participation.get()

    with true <- user.id == participation.user_id,
         {:ok, participation} <- Participation.set_recipients(participation, recipients) do
      conn
      |> put_view(ConversationView)
      |> render("participation.json", %{participation: participation, for: user})
    end
  end

  def read_notification(%{assigns: %{user: user}} = conn, %{"id" => notification_id}) do
    with {:ok, notification} <- Notification.read_one(user, notification_id) do
      conn
      |> put_view(NotificationView)
      |> render("show.json", %{notification: notification, for: user})
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => message})
    end
  end

  def read_notification(%{assigns: %{user: user}} = conn, %{"max_id" => max_id}) do
    with notifications <- Notification.set_read_up_to(user, max_id) do
      notifications = Enum.take(notifications, 80)

      conn
      |> put_view(NotificationView)
      |> render("index.json", %{notifications: notifications, for: user})
    end
  end
end
