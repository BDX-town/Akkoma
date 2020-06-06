# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Helpers.UriHelper do
  def append_uri_params(uri, appended_params) do
    uri = URI.parse(uri)
    appended_params = for {k, v} <- appended_params, into: %{}, do: {to_string(k), v}
    existing_params = URI.query_decoder(uri.query || "") |> Enum.into(%{})
    updated_params_keys = Enum.uniq(Map.keys(existing_params) ++ Map.keys(appended_params))

    updated_params =
      for k <- updated_params_keys, do: {k, appended_params[k] || existing_params[k]}

    uri
    |> Map.put(:query, URI.encode_query(updated_params))
    |> URI.to_string()
  end

  def maybe_add_base("/" <> uri, base), do: Path.join([base, uri])
  def maybe_add_base(uri, _base), do: uri
end
