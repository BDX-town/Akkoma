# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.RichMedia.Parser.Card do
  alias Pleroma.Web.RichMedia.Parser.Card
  alias Pleroma.Web.RichMedia.Parser.Embed

  @types ["link", "photo", "video"]

  # https://docs.joinmastodon.org/entities/card/
  defstruct url: nil,
            title: nil,
            description: "",
            type: "link",
            author_name: "",
            author_url: "",
            provider_name: "",
            provider_url: "",
            html: "",
            width: 0,
            height: 0,
            image: nil,
            embed_url: "",
            blurhash: nil

  def parse(%Embed{url: url, oembed: %{"type" => type, "title" => title} = oembed} = embed)
      when type in @types and is_binary(url) do
    uri = URI.parse(url)

    html =
      case FastSanitize.Sanitizer.scrub(oembed["html"], Pleroma.HTML.Scrubber.OEmbed) do
        {:ok, html} -> html
        _ -> ""
      end

    %Card{
      url: url,
      title: title,
      description: get_description(embed),
      type: oembed["type"],
      author_name: oembed["author_name"],
      author_url: oembed["author_url"],
      provider_name: oembed["provider_name"] || uri.host,
      provider_url: oembed["provider_url"] || "#{uri.scheme}://#{uri.host}",
      html: html,
      width: oembed["width"],
      height: oembed["height"],
      image: oembed["thumbnail_url"] |> proxy(),
      embed_url: oembed["url"] |> proxy()
    }
    |> validate()
  end

  def parse(%Embed{url: url} = embed) when is_binary(url) do
    uri = URI.parse(url)

    %Card{
      url: url,
      title: get_title(embed),
      description: get_description(embed),
      type: "link",
      provider_name: uri.host,
      provider_url: "#{uri.scheme}://#{uri.host}",
      image: get_image(embed) |> proxy()
    }
    |> validate()
  end

  def parse(card), do: {:error, {:invalid_metadata, card}}

  defp get_title(embed) do
    case embed do
      %{meta: %{"twitter:title" => title}} when is_binary(title) and title != "" -> title
      %{meta: %{"og:title" => title}} when is_binary(title) and title != "" -> title
      %{title: title} when is_binary(title) and title != "" -> title
      _ -> nil
    end
  end

  defp get_description(%{meta: meta}) do
    case meta do
      %{"twitter:description" => desc} when is_binary(desc) and desc != "" -> desc
      %{"og:description" => desc} when is_binary(desc) and desc != "" -> desc
      %{"description" => desc} when is_binary(desc) and desc != "" -> desc
      _ -> ""
    end
  end

  defp get_image(%{meta: meta}) do
    case meta do
      %{"twitter:image" => image} when is_binary(image) and image != "" -> image
      %{"og:image" => image} when is_binary(image) and image != "" -> image
      _ -> ""
    end
  end

  def to_map(%Card{} = card) do
    card
    |> Map.from_struct()
    |> stringify_keys()
  end

  def to_map(%{} = card), do: stringify_keys(card)

  defp stringify_keys(%{} = map), do: Map.new(map, fn {k, v} -> {Atom.to_string(k), v} end)

  defp proxy(url) when is_binary(url), do: Pleroma.Web.MediaProxy.url(url)
  defp proxy(_), do: nil

  def validate(%Card{type: type, title: title} = card)
      when type in @types and is_binary(title) and title != "" do
    {:ok, card}
  end

  def validate(%Embed{} = embed) do
    case Card.parse(embed) do
      {:ok, %Card{} = card} -> validate(card)
      card -> {:error, {:invalid_metadata, card}}
    end
  end

  def validate(card), do: {:error, {:invalid_metadata, card}}
end
