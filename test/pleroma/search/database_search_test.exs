# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Search.DatabaseSearchTest do
  alias Pleroma.Search.DatabaseSearch
  alias Pleroma.Web.CommonAPI
  import Pleroma.Factory

  use Pleroma.DataCase, async: false

  test "it finds something" do
    user = insert(:user)
    {:ok, post} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})

    [result] = DatabaseSearch.search(nil, "wednesday")

    assert result.id == post.id
  end

  test "doesn’t explode with gin fuzzy limit set" do
    clear_config([Pleroma.Search.DatabaseSearch, :gin_fuzzy_search_limit], 10_000)

    user = insert(:user)
    {:ok, post} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})

    [result] = DatabaseSearch.search(nil, "wednesday")

    assert result.id == post.id
  end

  test "using websearch_to_tsquery" do
    user = insert(:user)
    {:ok, _post} = CommonAPI.post(user, %{status: "it's wednesday my dudes"})
    {:ok, other_post} = CommonAPI.post(user, %{status: "it's wednesday my bros"})

    assert [result] = DatabaseSearch.search(nil, "wednesday -dudes")

    assert result.id == other_post.id
  end
end
