# Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ApiSpec.Helpers do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema

  def request_body(description, schema_ref, opts \\ []) do
    media_types = ["application/json", "multipart/form-data", "application/x-www-form-urlencoded"]

    content =
      media_types
      |> Enum.map(fn type ->
        {type,
         %OpenApiSpex.MediaType{
           schema: schema_ref,
           example: opts[:example],
           examples: opts[:examples]
         }}
      end)
      |> Enum.into(%{})

    %OpenApiSpex.RequestBody{
      description: description,
      content: content,
      required: opts[:required] || false
    }
  end

  def pagination_params do
    [
      Operation.parameter(:max_id, :query, :string, "Return items older than this ID"),
      Operation.parameter(:min_id, :query, :string, "Return the oldest items newer than this ID"),
      Operation.parameter(
        :since_id,
        :query,
        :string,
        "Return the newest items newer than this ID"
      ),
      Operation.parameter(
        :limit,
        :query,
        %Schema{type: :integer, default: 20, maximum: 40},
        "Limit"
      )
    ]
  end
end
