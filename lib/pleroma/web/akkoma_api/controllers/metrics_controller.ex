defmodule Pleroma.Web.AkkomaAPI.MetricsController do
  use Pleroma.Web, :controller

  alias Pleroma.Web.Plugs.OAuthScopesPlug

  plug(
    OAuthScopesPlug,
    %{scopes: ["admin:metrics"]}
    when action in [
           :show
         ]
  )

  def show(conn, _params) do
    stats = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> text(stats)
  end
end
