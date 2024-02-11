# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
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
    with :ok <- validate_page_url(url),
         {:ok, data} <- parse_url(url) do
      data = Map.put(data, "url", url)
      {:ok, data}
    end
  end

  defp parse_url(url) do
    with {:ok, %Tesla.Env{body: html}} <- Pleroma.Web.RichMedia.Helpers.rich_media_get(url),
         {:ok, html} <- Floki.parse_document(html) do
      html
      |> maybe_parse()
      |> clean_parsed_data()
      |> check_parsed_data()
    end
  end

  def parse_with_timeout(url) do
    try do
      task =
        Task.Supervisor.async_nolink(Pleroma.TaskSupervisor, fn ->
          parse_url(url)
        end)

      Task.await(task, 5000)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Timeout while fetching rich media for #{url}")
        {:error, :timeout}
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
end
