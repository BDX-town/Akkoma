# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.HTTP.AdapterHelper do
  @moduledoc """
  Configure Tesla.Client with default and customized adapter options.
  """
  @defaults [pool: :federation]

  @type proxy_type() :: :socks4 | :socks5
  @type host() :: charlist() | :inet.ip_address()

  alias Pleroma.Config
  alias Pleroma.HTTP.AdapterHelper
  require Logger

  @type proxy ::
          {Connection.host(), pos_integer()}
          | {Connection.proxy_type(), Connection.host(), pos_integer()}

  @callback options(keyword(), URI.t()) :: keyword()
  @callback get_conn(URI.t(), keyword()) :: {:ok, term()} | {:error, term()}

  @spec format_proxy(String.t() | tuple() | nil) :: proxy() | nil
  def format_proxy(nil), do: nil

  def format_proxy(proxy_url) do
    case parse_proxy(proxy_url) do
      {:ok, host, port} -> {host, port}
      {:ok, type, host, port} -> {type, host, port}
      _ -> nil
    end
  end

  @spec maybe_add_proxy(keyword(), proxy() | nil) :: keyword()
  def maybe_add_proxy(opts, nil), do: opts
  def maybe_add_proxy(opts, proxy), do: Keyword.put_new(opts, :proxy, proxy)

  @doc """
  Merge default connection & adapter options with received ones.
  """

  @spec options(URI.t(), keyword()) :: keyword()
  def options(%URI{} = uri, opts \\ []) do
    @defaults
    |> put_timeout()
    |> Keyword.merge(opts)
    |> adapter_helper().options(uri)
  end

  # For Hackney, this is the time a connection can stay idle in the pool.
  # For Gun, this is the timeout to receive a message from Gun.
  defp put_timeout(opts) do
    {config_key, default} =
      if adapter() == Tesla.Adapter.Gun do
        {:pools, Config.get([:pools, :default, :timeout], 5_000)}
      else
        {:hackney_pools, 10_000}
      end

    timeout = Config.get([config_key, opts[:pool], :timeout], default)

    Keyword.merge(opts, timeout: timeout)
  end

  def get_conn(uri, opts), do: adapter_helper().get_conn(uri, opts)
  defp adapter, do: Application.get_env(:tesla, :adapter)

  defp adapter_helper do
    case adapter() do
      Tesla.Adapter.Gun -> AdapterHelper.Gun
      Tesla.Adapter.Hackney -> AdapterHelper.Hackney
      _ -> AdapterHelper.Default
    end
  end

  @spec parse_proxy(String.t() | tuple() | nil) ::
          {:ok, host(), pos_integer()}
          | {:ok, proxy_type(), host(), pos_integer()}
          | {:error, atom()}
          | nil

  def parse_proxy(nil), do: nil

  def parse_proxy(proxy) when is_binary(proxy) do
    with [host, port] <- String.split(proxy, ":"),
         {port, ""} <- Integer.parse(port) do
      {:ok, parse_host(host), port}
    else
      {_, _} ->
        Logger.warn("Parsing port failed #{inspect(proxy)}")
        {:error, :invalid_proxy_port}

      :error ->
        Logger.warn("Parsing port failed #{inspect(proxy)}")
        {:error, :invalid_proxy_port}

      _ ->
        Logger.warn("Parsing proxy failed #{inspect(proxy)}")
        {:error, :invalid_proxy}
    end
  end

  def parse_proxy(proxy) when is_tuple(proxy) do
    with {type, host, port} <- proxy do
      {:ok, type, parse_host(host), port}
    else
      _ ->
        Logger.warn("Parsing proxy failed #{inspect(proxy)}")
        {:error, :invalid_proxy}
    end
  end

  @spec parse_host(String.t() | atom() | charlist()) :: charlist() | :inet.ip_address()
  def parse_host(host) when is_list(host), do: host
  def parse_host(host) when is_atom(host), do: to_charlist(host)

  def parse_host(host) when is_binary(host) do
    host = to_charlist(host)

    case :inet.parse_address(host) do
      {:error, :einval} -> host
      {:ok, ip} -> ip
    end
  end

  @spec format_host(String.t()) :: charlist()
  def format_host(host) do
    host_charlist = to_charlist(host)

    case :inet.parse_address(host_charlist) do
      {:error, :einval} ->
        :idna.encode(host_charlist)

      {:ok, _ip} ->
        host_charlist
    end
  end
end
