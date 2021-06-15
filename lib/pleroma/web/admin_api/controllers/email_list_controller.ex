# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.EmailListController do
  use Pleroma.Web, :controller

  alias Pleroma.User.EmailList
  alias Pleroma.Web.Plugs.OAuthScopesPlug

  require Logger

  plug(OAuthScopesPlug, %{scopes: ["admin:read:accounts"]})

  def subscribers(conn, _params) do
    render_csv(conn, :subscribers)
  end

  def unsubscribers(conn, _params) do
    render_csv(conn, :unsubscribers)
  end

  def combined(conn, _params) do
    render_csv(conn, :combined)
  end

  defp render_csv(conn, audience) when is_atom(audience) do
    csv = EmailList.generate_csv(audience)

    conn
    |> put_resp_content_type("text/csv")
    |> resp(200, csv)
    |> send_resp()
  end
end
