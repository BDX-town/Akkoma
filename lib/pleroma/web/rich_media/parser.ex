# Pleroma: A lightweight social networking server
# Copyright © 2017-2022 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.RichMedia.Parser do
  require Logger

  @config_impl Application.compile_env(:pleroma, [__MODULE__, :config_impl], Pleroma.Config)

  defp parsers do
    Pleroma.Config.get([:rich_media, :parsers])
  end

  def parse(nil), do: nil

  @spec parse(String.t()) :: {:ok, map()} | {:error, any()}
  def parse(url) do
    with {_, true} <- {:config, @config_impl.get([:rich_media, :enabled])},
         {_, :ok} <- {:url, validate_page_url(url)},
         {:ok, data} <- parse_url(url) do
      data = Map.put(data, "url", url)
      {:ok, data}
    else
      {:config, _} -> {:error, :rich_media_disabled}
      {:url, {:error, reason}} -> {:error, {:url, reason}}
      e -> e
    end
  end

  defp parse_url(url) do
    try do
      with {:ok, %Tesla.Env{body: html}} <- Pleroma.Web.RichMedia.Helpers.rich_media_get(url),
          {:ok, html} <- Floki.parse_document(html) do
        html
        |> maybe_parse()
        |> clean_parsed_data()
        |> check_parsed_data()
      end
    rescue
      e -> Logger.warning("Fail while fetching rich media for #{url}: #{Exception.format(:error, e, __STACKTRACE__)}")
    end
  end

  defp maybe_parse(html) do
    Enum.reduce_while(parsers(), %{}, fn parser, acc ->
      case parser.parse(html, acc) do
        data when data != %{} -> {:halt, data}
        _ -> {:cont, acc}
      end
    end)
  end

  defp check_parsed_data(%{"title" => title} = data)
       when is_binary(title) and title != "" do
    {:ok, data}
  end

  defp check_parsed_data(data) do
    {:error, {:invalid_metadata, data}}
  end

  defp clean_parsed_data(data) do
    data
    |> Enum.reject(fn {key, val} ->
      not match?({:ok, _}, Jason.encode(%{key => val}))
    end)
    |> Map.new()
  end

  @spec validate_page_url(URI.t() | binary()) :: :ok | {:error, term()}
  defp validate_page_url(page_url) when is_binary(page_url) do
    validate_tld = @config_impl.get([Pleroma.Formatter, :validate_tld])

    page_url
    |> Linkify.Parser.url?(validate_tld: validate_tld)
    |> parse_uri(page_url)
  end

  defp validate_page_url(%URI{host: host, scheme: "https"}) do
    cond do
      Linkify.Parser.ip?(host) ->
        {:error, :ip}

      host in @config_impl.get([:rich_media, :ignore_hosts], []) ->
        {:error, :ignore_hosts}

      get_tld(host) in @config_impl.get([:rich_media, :ignore_tld], []) ->
        {:error, :ignore_tld}

      true ->
        :ok
    end
  end

  defp validate_page_url(_), do: {:error, "scheme mismatch"}

  defp parse_uri(true, url) do
    url
    |> URI.parse()
    |> validate_page_url
  end

  defp parse_uri(_, _), do: {:error, "not a URL"}

  defp get_tld(host) do
    host
    |> String.split(".")
    |> Enum.reverse()
    |> hd
  end
end
