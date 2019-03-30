defmodule Pleroma.Pagination do
  @moduledoc """
  Implements Mastodon-compatible pagination.
  """

  import Ecto.Query
  import Ecto.Changeset

  alias Pleroma.Repo

  @default_limit 20

  def fetch_paginated(query, params) do
    options = cast_params(params)

    query
    |> paginate(options)
    |> Repo.all()
    |> enforce_order(options)
  end

  def paginate(query, options) do
    query
    |> restrict(:min_id, options)
    |> restrict(:since_id, options)
    |> restrict(:max_id, options)
    |> restrict(:order, options)
    |> restrict(:limit, options)
  end

  defp cast_params(params) do
    param_types = %{
      min_id: :string,
      since_id: :string,
      max_id: :string,
      limit: :integer
    }

    changeset = cast({%{}, param_types}, params, Map.keys(param_types))
    changeset.changes
  end

  defp restrict(query, :min_id, %{min_id: min_id}) do
    where(query, [q], q.id > ^min_id)
  end

  defp restrict(query, :since_id, %{since_id: since_id}) do
    where(query, [q], q.id > ^since_id)
  end

  defp restrict(query, :max_id, %{max_id: max_id}) do
    where(query, [q], q.id < ^max_id)
  end

  defp restrict(query, :order, %{min_id: _}) do
    order_by(query, [u], fragment("? asc nulls last", u.id))
  end

  defp restrict(query, :order, _options) do
    order_by(query, [u], fragment("? desc nulls last", u.id))
  end

  defp restrict(query, :limit, options) do
    limit = Map.get(options, :limit, @default_limit)

    query
    |> limit(^limit)
  end

  defp restrict(query, _, _), do: query

  defp enforce_order(result, %{min_id: _}) do
    result
    |> Enum.reverse()
  end

  defp enforce_order(result, _), do: result
end
