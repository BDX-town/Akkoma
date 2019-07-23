# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.Publisher do
  alias Pleroma.Activity
  alias Pleroma.Config
  alias Pleroma.HTTP
  alias Pleroma.Instances
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Relay
  alias Pleroma.Web.ActivityPub.Transmogrifier

  import Pleroma.Web.ActivityPub.Visibility

  @behaviour Pleroma.Web.Federator.Publisher

  require Logger

  @moduledoc """
  ActivityPub outgoing federation module.
  """

  @doc """
  Determine if an activity can be represented by running it through Transmogrifier.
  """
  def is_representable?(%Activity{} = activity) do
    with {:ok, _data} <- Transmogrifier.prepare_outgoing(activity.data) do
      true
    else
      _e ->
        false
    end
  end

  @doc """
  Publish a single message to a peer.  Takes a struct with the following
  parameters set:

  * `inbox`: the inbox to publish to
  * `json`: the JSON message body representing the ActivityPub message
  * `actor`: the actor which is signing the message
  * `id`: the ActivityStreams URI of the message
  """
  def publish_one(%{inbox: inbox, json: json, actor: %User{} = actor, id: id} = params) do
    Logger.info("Federating #{id} to #{inbox}")
    host = URI.parse(inbox).host

    digest = "SHA-256=" <> (:crypto.hash(:sha256, json) |> Base.encode64())

    date =
      NaiveDateTime.utc_now()
      |> Timex.format!("{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} GMT")

    signature =
      Pleroma.Signature.sign(actor, %{
        host: host,
        "content-length": byte_size(json),
        digest: digest,
        date: date
      })

    with {:ok, %{status: code}} when code in 200..299 <-
           result =
             HTTP.post(
               inbox,
               json,
               [
                 {"Content-Type", "application/activity+json"},
                 {"Date", date},
                 {"signature", signature},
                 {"digest", digest}
               ]
             ) do
      if !Map.has_key?(params, :unreachable_since) || params[:unreachable_since],
        do: Instances.set_reachable(inbox)

      result
    else
      {_post_result, response} ->
        unless params[:unreachable_since], do: Instances.set_unreachable(inbox)
        {:error, response}
    end
  end

  defp should_federate?(inbox, public) do
    if public do
      true
    else
      %{host: host} = URI.parse(inbox)

      quarantined_instances =
        Config.get([:instance, :quarantined_instances], [])
        |> Pleroma.Web.ActivityPub.MRF.subdomains_regex()

      !Pleroma.Web.ActivityPub.MRF.subdomain_match?(quarantined_instances, host)
    end
  end

  @spec recipients(User.t(), Activity.t()) :: list(User.t()) | []
  defp recipients(actor, activity) do
    {:ok, followers} =
      if actor.follower_address in activity.recipients do
        User.get_external_followers(actor)
      else
        {:ok, []}
      end

    Pleroma.Web.Salmon.remote_users(actor, activity) ++ followers
  end

  defp get_cc_ap_ids(ap_id, recipients) do
    host = Map.get(URI.parse(ap_id), :host)

    recipients
    |> Enum.filter(fn %User{ap_id: ap_id} -> Map.get(URI.parse(ap_id), :host) == host end)
    |> Enum.map(& &1.ap_id)
  end

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  defp maybe_use_sharedinbox(%User{info: %{source_data: data}}),
    do: (is_map(data["endpoints"]) && Map.get(data["endpoints"], "sharedInbox")) || data["inbox"]

  @doc """
  Determine a user inbox to use based on heuristics.  These heuristics
  are based on an approximation of the ``sharedInbox`` rules in the
  [ActivityPub specification][ap-sharedinbox].

  Please do not edit this function (or its children) without reading
  the spec, as editing the code is likely to introduce some breakage
  without some familiarity.

     [ap-sharedinbox]: https://www.w3.org/TR/activitypub/#shared-inbox-delivery
  """
  def determine_inbox(
        %Activity{data: activity_data},
        %User{info: %{source_data: data}} = user
      ) do
    to = activity_data["to"] || []
    cc = activity_data["cc"] || []
    type = activity_data["type"]

    cond do
      type == "Delete" ->
        maybe_use_sharedinbox(user)

      @as_public in to || @as_public in cc ->
        maybe_use_sharedinbox(user)

      length(to) + length(cc) > 1 ->
        maybe_use_sharedinbox(user)

      true ->
        data["inbox"]
    end
  end

  @doc """
  Publishes an activity with BCC to all relevant peers.
  """

  def publish(actor, %{data: %{"bcc" => bcc}} = activity) when is_list(bcc) and bcc != [] do
    public = is_public?(activity)
    {:ok, data} = Transmogrifier.prepare_outgoing(activity.data)

    recipients = recipients(actor, activity)

    recipients
    |> Enum.filter(&User.ap_enabled?/1)
    |> Enum.map(fn %{info: %{source_data: data}} -> data["inbox"] end)
    |> Enum.filter(fn inbox -> should_federate?(inbox, public) end)
    |> Instances.filter_reachable()
    |> Enum.each(fn {inbox, unreachable_since} ->
      %User{ap_id: ap_id} =
        Enum.find(recipients, fn %{info: %{source_data: data}} -> data["inbox"] == inbox end)

      # Get all the recipients on the same host and add them to cc. Otherwise, a remote
      # instance would only accept a first message for the first recipient and ignore the rest.
      cc = get_cc_ap_ids(ap_id, recipients)

      json =
        data
        |> Map.put("cc", cc)
        |> Jason.encode!()

      Pleroma.Web.Federator.Publisher.enqueue_one(__MODULE__, %{
        inbox: inbox,
        json: json,
        actor: actor,
        id: activity.data["id"],
        unreachable_since: unreachable_since
      })
    end)
  end

  @doc """
  Publishes an activity to all relevant peers.
  """
  def publish(%User{} = actor, %Activity{} = activity) do
    public = is_public?(activity)

    if public && Config.get([:instance, :allow_relay]) do
      Logger.info(fn -> "Relaying #{activity.data["id"]} out" end)
      Relay.publish(activity)
    end

    {:ok, data} = Transmogrifier.prepare_outgoing(activity.data)
    json = Jason.encode!(data)

    recipients(actor, activity)
    |> Enum.filter(fn user -> User.ap_enabled?(user) end)
    |> Enum.map(fn %User{} = user ->
      determine_inbox(activity, user)
    end)
    |> Enum.uniq()
    |> Enum.filter(fn inbox -> should_federate?(inbox, public) end)
    |> Instances.filter_reachable()
    |> Enum.each(fn {inbox, unreachable_since} ->
      Pleroma.Web.Federator.Publisher.enqueue_one(
        __MODULE__,
        %{
          inbox: inbox,
          json: json,
          actor: actor,
          id: activity.data["id"],
          unreachable_since: unreachable_since
        }
      )
    end)
  end

  def gather_webfinger_links(%User{} = user) do
    [
      %{"rel" => "self", "type" => "application/activity+json", "href" => user.ap_id},
      %{
        "rel" => "self",
        "type" => "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\"",
        "href" => user.ap_id
      }
    ]
  end

  def gather_nodeinfo_protocol_names, do: ["activitypub"]
end
