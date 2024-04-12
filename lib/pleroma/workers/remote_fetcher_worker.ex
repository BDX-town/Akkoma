# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Workers.RemoteFetcherWorker do
  alias Pleroma.Instances
  alias Pleroma.Object.Fetcher

  use Pleroma.Workers.WorkerHelper, queue: "remote_fetcher"

  @impl Oban.Worker
  def perform(%Job{args: %{"op" => "fetch_remote", "id" => id} = args}) do
    if Instances.reachable?(id) do
      case Fetcher.fetch_object_from_id(id, depth: args["depth"]) do
        {:ok, _object} ->
          :ok

        {:error, :forbidden} ->
          {:cancel, :forbidden}

        {:error, :not_found} ->
          {:cancel, :not_found}

        {:error, :allowed_depth} ->
          {:cancel, :allowed_depth}

        _ ->
          :error
      end
    else
      {:cancel, "Unreachable instance"}
    end
  end
end
