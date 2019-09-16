# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Federator do
  alias Pleroma.Activity
  alias Pleroma.Object.Containment
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.Federator.Publisher
  alias Pleroma.Web.OStatus
  alias Pleroma.Web.Websub
  alias Pleroma.Workers.PublisherWorker
  alias Pleroma.Workers.ReceiverWorker
  alias Pleroma.Workers.SubscriberWorker

  require Logger

  def init do
    # To do: consider removing this call in favor of scheduled execution (`quantum`-based)
    refresh_subscriptions(schedule_in: 60)
  end

  @doc "Addresses [memory leaks on recursive replies fetching](https://git.pleroma.social/pleroma/pleroma/issues/161)"
  # credo:disable-for-previous-line Credo.Check.Readability.MaxLineLength
  def allowed_incoming_reply_depth?(depth) do
    max_replies_depth = Pleroma.Config.get([:instance, :federation_incoming_replies_max_depth])

    if max_replies_depth do
      (depth || 1) <= max_replies_depth
    else
      true
    end
  end

  # Client API

  def incoming_doc(doc) do
    ReceiverWorker.enqueue("incoming_doc", %{"body" => doc})
  end

  def incoming_ap_doc(params) do
    ReceiverWorker.enqueue("incoming_ap_doc", %{"params" => params})
  end

  def publish(%{id: "pleroma:fakeid"} = activity) do
    perform(:publish, activity)
  end

  def publish(activity) do
    PublisherWorker.enqueue("publish", %{"activity_id" => activity.id})
  end

  def verify_websub(websub) do
    SubscriberWorker.enqueue("verify_websub", %{"websub_id" => websub.id})
  end

  def request_subscription(websub) do
    SubscriberWorker.enqueue("request_subscription", %{"websub_id" => websub.id})
  end

  def refresh_subscriptions(worker_args \\ []) do
    SubscriberWorker.enqueue("refresh_subscriptions", %{}, worker_args ++ [max_attempts: 1])
  end

  # Job Worker Callbacks

  @spec perform(atom(), module(), any()) :: {:ok, any()} | {:error, any()}
  def perform(:publish_one, module, params) do
    apply(module, :publish_one, [params])
  end

  def perform(:publish, activity) do
    Logger.debug(fn -> "Running publish for #{activity.data["id"]}" end)

    with %User{} = actor <- User.get_cached_by_ap_id(activity.data["actor"]),
         {:ok, actor} <- User.ensure_keys_present(actor) do
      Publisher.publish(actor, activity)
    end
  end

  def perform(:incoming_doc, doc) do
    Logger.info("Got document, trying to parse")
    OStatus.handle_incoming(doc)
  end

  def perform(:incoming_ap_doc, params) do
    Logger.info("Handling incoming AP activity")

    params = Utils.normalize_params(params)

    # NOTE: we use the actor ID to do the containment, this is fine because an
    # actor shouldn't be acting on objects outside their own AP server.
    with {:ok, _user} <- ap_enabled_actor(params["actor"]),
         nil <- Activity.normalize(params["id"]),
         :ok <- Containment.contain_origin_from_id(params["actor"], params),
         {:ok, activity} <- Transmogrifier.handle_incoming(params) do
      {:ok, activity}
    else
      %Activity{} ->
        Logger.info("Already had #{params["id"]}")
        :error

      _e ->
        # Just drop those for now
        Logger.info("Unhandled activity")
        Logger.info(Jason.encode!(params, pretty: true))
        :error
    end
  end

  def perform(:request_subscription, websub) do
    Logger.debug("Refreshing #{websub.topic}")

    with {:ok, websub} <- Websub.request_subscription(websub) do
      Logger.debug("Successfully refreshed #{websub.topic}")
    else
      _e -> Logger.debug("Couldn't refresh #{websub.topic}")
    end
  end

  def perform(:verify_websub, websub) do
    Logger.debug(fn ->
      "Running WebSub verification for #{websub.id} (#{websub.topic}, #{websub.callback})"
    end)

    Websub.verify(websub)
  end

  def perform(:refresh_subscriptions) do
    Logger.debug("Federator running refresh subscriptions")
    Websub.refresh_subscriptions()
  end

  def ap_enabled_actor(id) do
    user = User.get_cached_by_ap_id(id)

    if User.ap_enabled?(user) do
      {:ok, user}
    else
      ActivityPub.make_user_from_ap_id(id)
    end
  end
end
