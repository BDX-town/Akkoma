defmodule Pleroma.Web.AkkomaAPI.MetricsController do
  use Pleroma.Web, :controller

  alias Pleroma.Web.Plugs.OAuthScopesPlug
  alias Pleroma.Config

  plug(
    OAuthScopesPlug,
    %{scopes: ["admin:metrics"]}
    when action in [
           :show
         ]
  )

  def show(conn, _params) do
    if Config.get([:instance, :export_prometheus_metrics], true) do
      conn
      |> text(TelemetryMetricsPrometheus.Core.scrape())
    else
      conn
      |> send_resp(404, "Not Found")
    end
  end
end
