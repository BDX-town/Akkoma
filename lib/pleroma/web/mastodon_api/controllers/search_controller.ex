# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.SearchController do
  use Pleroma.Web, :controller

  alias Pleroma.Activity
  alias Pleroma.Plugs.OAuthScopesPlug
  alias Pleroma.Plugs.RateLimiter
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web
  alias Pleroma.Web.ControllerHelper
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.MastodonAPI.StatusView

  require Logger

  plug(Pleroma.Web.ApiSpec.CastAndValidate)

  # Note: Mastodon doesn't allow unauthenticated access (requires read:accounts / read:search)
  plug(OAuthScopesPlug, %{scopes: ["read:search"], fallback: :proceed_unauthenticated})

  # Note: on private instances auth is required (EnsurePublicOrAuthenticatedPlug is not skipped)

  plug(RateLimiter, [name: :search] when action in [:search, :search2, :account_search])

  defdelegate open_api_operation(action), to: Pleroma.Web.ApiSpec.SearchOperation

  def account_search(%{assigns: %{user: user}} = conn, %{q: query} = params) do
    accounts = User.search(query, search_options(params, user))

    conn
    |> put_view(AccountView)
    |> render("index.json",
      users: accounts,
      for: user,
      as: :user
    )
  end

  def search2(conn, params), do: do_search(:v2, conn, params)
  def search(conn, params), do: do_search(:v1, conn, params)

  defp do_search(version, %{assigns: %{user: user}} = conn, %{q: query} = params) do
    options = search_options(params, user)
    timeout = Keyword.get(Repo.config(), :timeout, 15_000)
    default_values = %{"statuses" => [], "accounts" => [], "hashtags" => []}

    result =
      default_values
      |> Enum.map(fn {resource, default_value} ->
        if params[:type] in [nil, resource] do
          {resource, fn -> resource_search(version, resource, query, options) end}
        else
          {resource, fn -> default_value end}
        end
      end)
      |> Task.async_stream(fn {resource, f} -> {resource, with_fallback(f)} end,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce(default_values, fn
        {:ok, {resource, result}}, acc ->
          Map.put(acc, resource, result)

        _error, acc ->
          acc
      end)

    json(conn, result)
  end

  defp search_options(params, user) do
    [
      resolve: params[:resolve],
      following: params[:following],
      limit: params[:limit],
      offset: params[:offset],
      type: params[:type],
      author: get_author(params),
      embed_relationships: ControllerHelper.embed_relationships?(params),
      for_user: user
    ]
    |> Enum.filter(&elem(&1, 1))
  end

  defp resource_search(_, "accounts", query, options) do
    accounts = with_fallback(fn -> User.search(query, options) end)

    AccountView.render("index.json",
      users: accounts,
      for: options[:for_user],
      as: :user,
      embed_relationships: options[:embed_relationships]
    )
  end

  defp resource_search(_, "statuses", query, options) do
    statuses = with_fallback(fn -> Activity.search(options[:for_user], query, options) end)

    StatusView.render("index.json",
      activities: statuses,
      for: options[:for_user],
      as: :activity
    )
  end

  defp resource_search(:v2, "hashtags", query, _options) do
    tags_path = Web.base_url() <> "/tag/"

    query
    |> prepare_tags()
    |> Enum.map(fn tag ->
      %{name: tag, url: tags_path <> tag}
    end)
  end

  defp resource_search(:v1, "hashtags", query, _options) do
    prepare_tags(query)
  end

  defp prepare_tags(query, add_joined_tag \\ true) do
    tags =
      query
      |> String.split(~r/[^#\w]+/u, trim: true)
      |> Enum.uniq_by(&String.downcase/1)

    explicit_tags = Enum.filter(tags, fn tag -> String.starts_with?(tag, "#") end)

    tags =
      if Enum.any?(explicit_tags) do
        explicit_tags
      else
        tags
      end

    tags = Enum.map(tags, fn tag -> String.trim_leading(tag, "#") end)

    if Enum.empty?(explicit_tags) && add_joined_tag do
      tags
      |> Kernel.++([joined_tag(tags)])
      |> Enum.uniq_by(&String.downcase/1)
    else
      tags
    end
  end

  defp joined_tag(tags) do
    tags
    |> Enum.map(fn tag -> String.capitalize(tag) end)
    |> Enum.join()
  end

  defp with_fallback(f, fallback \\ []) do
    try do
      f.()
    rescue
      error ->
        Logger.error("#{__MODULE__} search error: #{inspect(error)}")
        fallback
    end
  end

  defp get_author(%{account_id: account_id}) when is_binary(account_id),
    do: User.get_cached_by_id(account_id)

  defp get_author(_params), do: nil
end
