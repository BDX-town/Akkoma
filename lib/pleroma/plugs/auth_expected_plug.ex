# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Plugs.AuthExpectedPlug do
  import Plug.Conn

  def init(options), do: options

  def call(conn, _) do
    put_private(conn, :auth_expected, true)
  end

  def auth_expected?(conn) do
    conn.private[:auth_expected]
  end
end
