# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.DomainBlockController do
  use Pleroma.Web, :controller

  alias Pleroma.User

  @doc "GET /api/v1/domain_blocks"
  def index(%{assigns: %{user: %{info: info}}} = conn, _) do
    json(conn, Map.get(info, :domain_blocks, []))
  end

  @doc "POST /api/v1/domain_blocks"
  def create(%{assigns: %{user: blocker}} = conn, %{"domain" => domain}) do
    User.block_domain(blocker, domain)
    json(conn, %{})
  end

  @doc "DELETE /api/v1/domain_blocks"
  def delete(%{assigns: %{user: blocker}} = conn, %{"domain" => domain}) do
    User.unblock_domain(blocker, domain)
    json(conn, %{})
  end
end
