defmodule Pleroma.HTTP.AdapterHelper.Hackney do
  @behaviour Pleroma.HTTP.AdapterHelper

  @defaults [
    connect_timeout: 10_000,
    recv_timeout: 20_000,
    follow_redirect: true,
    force_redirect: true,
    pool: :federation
  ]

  @spec options(keyword(), URI.t()) :: keyword()
  def options(connection_opts \\ [], %URI{} = uri) do
    proxy = Pleroma.Config.get([:http, :proxy_url])

    config_opts = Pleroma.Config.get([:http, :adapter], [])

    @defaults
    |> Keyword.merge(config_opts)
    |> Keyword.merge(connection_opts)
    |> add_scheme_opts(uri)
    |> Pleroma.HTTP.AdapterHelper.maybe_add_proxy(proxy)
  end

  defp add_scheme_opts(opts, _), do: opts

  def after_request(_), do: :ok
end
