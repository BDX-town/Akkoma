defmodule Pleroma.Web.AkkomaAPI.MetricsControllerTest do
  use Pleroma.Web.ConnCase, async: true

  import Pleroma.Factory
  alias Pleroma.Akkoma.FrontendSettingsProfile

  describe "GET /api/v1/akkoma/metrics" do
    test "should return metrics when the user has admin:metrics" do
      %{conn: conn} = oauth_access(["admin:metrics"])
      resp = conn
      |> get("/api/v1/akkoma/metrics")
      |> text_response(200)

      assert resp =~ "# HELP"
    end

    test "should not allow users that do not have the admin:metrics scope" do
      %{conn: conn} = oauth_access(["read:metrics"])
      resp = conn
      |> get("/api/v1/akkoma/metrics")
      |> json_response(403)
    end
  end
end
