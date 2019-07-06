# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.ReportViewTest do
  use Pleroma.DataCase
  import Pleroma.Factory
  alias Pleroma.Web.AdminAPI.ReportView
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.MastodonAPI.StatusView

  test "renders a report" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, activity} = CommonAPI.report(user, %{"account_id" => other_user.id})

    expected = %{
      content: nil,
      actor:
        Map.merge(
          AccountView.render("account.json", %{user: user}),
          Pleroma.Web.AdminAPI.AccountView.render("show.json", %{user: user})
        ),
      account:
        Map.merge(
          AccountView.render("account.json", %{user: other_user}),
          Pleroma.Web.AdminAPI.AccountView.render("show.json", %{user: other_user})
        ),
      statuses: [],
      state: "open",
      id: activity.id
    }

    result =
      ReportView.render("show.json", %{report: activity})
      |> Map.delete(:created_at)

    assert result == expected
  end

  test "includes reported statuses" do
    user = insert(:user)
    other_user = insert(:user)
    {:ok, activity} = CommonAPI.post(other_user, %{"status" => "toot"})

    {:ok, report_activity} =
      CommonAPI.report(user, %{"account_id" => other_user.id, "status_ids" => [activity.id]})

    expected = %{
      content: nil,
      actor:
        Map.merge(
          AccountView.render("account.json", %{user: user}),
          Pleroma.Web.AdminAPI.AccountView.render("show.json", %{user: user})
        ),
      account:
        Map.merge(
          AccountView.render("account.json", %{user: other_user}),
          Pleroma.Web.AdminAPI.AccountView.render("show.json", %{user: other_user})
        ),
      statuses: [StatusView.render("status.json", %{activity: activity})],
      state: "open",
      id: report_activity.id
    }

    result =
      ReportView.render("show.json", %{report: report_activity})
      |> Map.delete(:created_at)

    assert result == expected
  end

  test "renders report's state" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, activity} = CommonAPI.report(user, %{"account_id" => other_user.id})
    {:ok, activity} = CommonAPI.update_report_state(activity.id, "closed")
    assert %{state: "closed"} = ReportView.render("show.json", %{report: activity})
  end

  test "renders report description" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, activity} =
      CommonAPI.report(user, %{
        "account_id" => other_user.id,
        "comment" => "posts are too good for this instance"
      })

    assert %{content: "posts are too good for this instance"} =
             ReportView.render("show.json", %{report: activity})
  end

  test "sanitizes report description" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, activity} =
      CommonAPI.report(user, %{
        "account_id" => other_user.id,
        "comment" => ""
      })

    data = Map.put(activity.data, "content", "<script> alert('hecked :D:D:D:D:D:D:D') </script>")
    activity = Map.put(activity, :data, data)

    refute "<script> alert('hecked :D:D:D:D:D:D:D') </script>" ==
             ReportView.render("show.json", %{report: activity})[:content]
  end

  test "doesn't error out when the user doesn't exists" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, activity} =
      CommonAPI.report(user, %{
        "account_id" => other_user.id,
        "comment" => ""
      })

    Pleroma.User.delete(other_user)
    Pleroma.User.invalidate_cache(other_user)

    assert %{} = ReportView.render("show.json", %{report: activity})
  end
end
