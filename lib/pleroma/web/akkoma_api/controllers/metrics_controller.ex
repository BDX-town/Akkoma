defmodule Pleroma.Web.AkkomaAPI.MetricsController do
  use Pleroma.Web, :controller

  alias Pleroma.Web.Plugs.OAuthScopesPlug

  @unauthenticated_access %{fallback: :proceed_unauthenticated, scopes: []}
  plug(:skip_auth)


  def show(conn, _params) do
    stats = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> text(stats)
  end
end
