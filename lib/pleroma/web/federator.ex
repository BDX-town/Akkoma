# Pleroma: A lightweight social networking server
# Copyright © 2017-2021 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Federator do
  alias Pleroma.Activity
  alias Pleroma.Object.Containment
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.Federator.Publisher
  alias Pleroma.Workers.PublisherWorker
  alias Pleroma.Workers.ReceiverWorker

  require Logger

  @behaviour Pleroma.Web.Federator.Publishing

  @doc """
  Returns `true` if the distance to target object does not exceed max configured value.
  Serves to prevent fetching of very long threads, especially useful on smaller instances.
  Addresses [memory leaks on recursive replies fetching](https://git.pleroma.social/pleroma/pleroma/issues/161).
  Applies to fetching of both ancestor (reply-to) and child (reply) objects.
  """
  # credo:disable-for-previous-line Credo.Check.Readability.MaxLineLength
  def allowed_thread_distance?(distance) do
    max_distance = Pleroma.Config.get([:instance, :federation_incoming_replies_max_depth])

    if max_distance && max_distance >= 0 do
      # Default depth is 0 (an object has zero distance from itself in its thread)
      (distance || 0) <= max_distance
    else
      true
    end
  end

  # Client API

  def incoming_ap_doc(params) do
    ReceiverWorker.enqueue("incoming_ap_doc", %{"params" => params})
  end

  @impl true
  def publish(%{id: "pleroma:fakeid"} = activity) do
    perform(:publish, activity)
  end

  @impl true
  def publish(%{data: %{"object" => object}} = activity) when is_binary(object) do
    PublisherWorker.enqueue("publish", %{"activity_id" => activity.id, "object_data" => nil},
      priority: publish_priority(activity)
    )
  end

  @impl true
  def publish(%{data: %{"object" => object}} = activity) when is_map(object) or is_list(object) do
    PublisherWorker.enqueue(
      "publish",
      %{
        "activity_id" => activity.id,
        "object_data" => Jason.encode!(object)
      },
      priority: publish_priority(activity)
    )
  end

  defp publish_priority(%{data: %{"type" => "Delete"}}), do: 3
  defp publish_priority(_), do: 0

  # Job Worker Callbacks

  @spec perform(atom(), module(), any()) :: {:ok, any()} | {:error, any()}
  def perform(:publish_one, module, params) do
    apply(module, :publish_one, [params])
  end

  def perform(:publish, activity) do
    Logger.debug(fn -> "Running publish for #{activity.data["id"]}" end)

    %User{} = actor = User.get_cached_by_ap_id(activity.data["actor"])
    Publisher.publish(actor, activity)
  end

  def perform(:incoming_ap_doc, params) do
    Logger.debug("Handling incoming AP activity")

    actor =
      params
      |> Map.get("actor")
      |> Utils.get_ap_id()

    # NOTE: we use the actor ID to do the containment, this is fine because an
    # actor shouldn't be acting on objects outside their own AP server.
    with nil <- Activity.normalize(params["id"]),
         {_, :ok} <-
           {:correct_origin?, Containment.contain_origin_from_id(actor, params)},
         {_, :ok, _} <- {:local, Containment.contain_local_fetch(actor), actor},
         {:ok, activity} <- Transmogrifier.handle_incoming(params) do
      {:ok, activity}
    else
      {:correct_origin?, _} ->
        Logger.debug("Origin containment failure for #{params["id"]}")
        {:error, :origin_containment_failed}

      {:local, _, actor} ->
        Logger.alert(
          "Received incoming AP doc with valid signature for local actor #{actor}! Likely key leak!\n#{inspect(params)}"
        )

        {:error, :origin_containment_failed}

      %Activity{} ->
        Logger.debug("Already had #{params["id"]}")
        {:error, :already_present}

      {:actor, e} ->
        Logger.debug("Unhandled actor #{actor}, #{inspect(e)}")
        {:error, e}

      {:error, {:validate_object, _}} = e ->
        Logger.error("Incoming AP doc validation error: #{inspect(e)}")
        Logger.debug(Jason.encode!(params, pretty: true))
        e

      e ->
        # Just drop those for now
        Logger.debug(fn -> "Unhandled activity\n" <> Jason.encode!(params, pretty: true) end)

        case e do
          {:error, _} -> e
          _ -> {:error, e}
        end
    end
  end
end
