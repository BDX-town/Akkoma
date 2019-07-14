# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.TranslationHelpers do
  defmacro render_error(conn, status, msgid, bindings \\ Macro.escape(%{})) do
    quote do
      require Pleroma.Web.Gettext

      unquote(conn)
      |> Plug.Conn.put_status(unquote(status))
      |> Phoenix.Controller.json(%{
        error: Pleroma.Web.Gettext.dgettext("errors", unquote(msgid), unquote(bindings))
      })
    end
  end
end
