# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP do
  @moduledoc """
    Wrapper for `Tesla.request/2`.
  """

  alias Pleroma.HTTP.AdapterHelper
  alias Tesla.Env

  require Logger

  @type t :: __MODULE__
  @type method() :: :get | :post | :put | :delete | :head

  @mix_env Mix.env()

  @doc """
  Performs GET request.

  See `Pleroma.HTTP.request/5`
  """
  @spec get(Request.url() | nil, Request.headers(), keyword()) ::
          nil | {:ok, Env.t()} | {:error, any()}
  def get(url, headers \\ [], options \\ [])
  def get(nil, _, _), do: nil
  def get(url, headers, options), do: request(:get, url, nil, headers, options)

  @spec head(Request.url(), Request.headers(), keyword()) :: {:ok, Env.t()} | {:error, any()}
  def head(url, headers \\ [], options \\ []), do: request(:head, url, nil, headers, options)

  @doc """
  Performs POST request.

  See `Pleroma.HTTP.request/5`
  """
  @spec post(Request.url(), String.t(), Request.headers(), keyword()) ::
          {:ok, Env.t()} | {:error, any()}
  def post(url, body, headers \\ [], options \\ []),
    do: request(:post, url, body, headers, options)

  @doc """
  Builds and performs http request.

  # Arguments:
  `method` - :get, :post, :put, :delete, :head
  `url` - full url
  `body` - request body
  `headers` - a keyworld list of headers, e.g. `[{"content-type", "text/plain"}]`
  `options` - custom, per-request middleware or adapter options

  # Returns:
  `{:ok, %Tesla.Env{}}` or `{:error, error}`

  """
  @spec request(method(), Request.url(), String.t(), Request.headers(), keyword()) ::
          {:ok, Env.t()} | {:error, any()}
  def request(method, url, body, headers, options) when is_binary(url) do
    uri = URI.parse(url)
    adapter_opts = AdapterHelper.options(options[:adapter] || [])

    adapter_opts =
      if uri.scheme == :https do
        AdapterHelper.maybe_add_cacerts(adapter_opts, :public_key.cacerts_get())
      else
        adapter_opts
      end

    options = put_in(options[:adapter], adapter_opts)
    params = options[:params] || []
    options = options |> Keyword.delete(:params)
    headers = maybe_add_user_agent(headers)

    client =
      Tesla.client([
        Tesla.Middleware.FollowRedirects,
        Pleroma.HTTP.Middleware.HTTPSignature,
        Tesla.Middleware.Telemetry
      ])

    Logger.debug("Outbound: #{method} #{url}")

    Tesla.request(client,
      method: method,
      url: url,
      query: params,
      headers: headers,
      body: body,
      opts: options
    )
  rescue
    e ->
      Logger.error("Failed to fetch #{url}: #{Exception.format(:error, e, __STACKTRACE__)}")
      {:error, :fetch_error}
  end

  if @mix_env == :test do
    defp maybe_add_user_agent(headers) do
      with true <- Pleroma.Config.get([:http, :send_user_agent]) do
        [{"user-agent", Pleroma.Application.user_agent()} | headers]
      else
        _ ->
          headers
      end
    end
  else
    defp maybe_add_user_agent(headers),
      do: [{"user-agent", Pleroma.Application.user_agent()} | headers]
  end
end
