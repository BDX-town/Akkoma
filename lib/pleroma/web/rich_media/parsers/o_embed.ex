# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.RichMedia.Parsers.OEmbed do
  def parse(html, data) do
    with elements = [_ | _] <- get_discovery_data(html),
         oembed_url when is_binary(oembed_url) <- get_oembed_url(elements),
         {:ok, oembed_data} <- get_oembed_data(oembed_url) do
      Map.put(data, :oembed, oembed_data)
    else
      _e -> data
    end
  end

  defp get_discovery_data(html) do
    html |> Floki.find("link[type='application/json+oembed']")
  end

  defp get_oembed_url([{"link", attributes, _children} | _]) do
    Enum.find_value(attributes, fn {k, v} -> if k == "href", do: v end)
  end

  defp get_oembed_data(url) do
    with {:ok, %Tesla.Env{body: json}} <- Pleroma.Web.RichMedia.Helpers.oembed_get(url) do
      Jason.decode(json)
    end
  end
end
