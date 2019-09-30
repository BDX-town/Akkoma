# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.PleromaAPI.MascotController do
  use Pleroma.Web, :controller

  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub

  @doc "GET /api/v1/pleroma/mascot"
  def show(%{assigns: %{user: user}} = conn, _params) do
    json(conn, User.get_mascot(user))
  end

  @doc "PUT /api/v1/pleroma/mascot"
  def update(%{assigns: %{user: user}} = conn, %{"file" => file}) do
    with {:ok, object} <- ActivityPub.upload(file, actor: User.ap_id(user)),
         # Reject if not an image
         %{type: "image"} = attachment <- render_attachment(object) do
      # Sure!
      # Save to the user's info
      {:ok, _user} = User.update_info(user, &User.Info.mascot_update(&1, attachment))

      json(conn, attachment)
    else
      %{type: _} -> render_error(conn, :unsupported_media_type, "mascots can only be images")
    end
  end

  defp render_attachment(object) do
    attachment_data = Map.put(object.data, "id", object.id)
    Pleroma.Web.MastodonAPI.StatusView.render("attachment.json", %{attachment: attachment_data})
  end
end
