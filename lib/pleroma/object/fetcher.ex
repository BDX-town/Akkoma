# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Object.Fetcher do
  alias Pleroma.HTTP
  alias Pleroma.Object
  alias Pleroma.Object.Containment
  alias Pleroma.Signature
  alias Pleroma.Web.ActivityPub.InternalFetchActor
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.OStatus

  require Logger

  defp reinject_object(data) do
    Logger.debug("Reinjecting object #{data["id"]}")

    with data <- Transmogrifier.fix_object(data),
         {:ok, object} <- Object.create(data) do
      {:ok, object}
    else
      e ->
        Logger.error("Error while processing object: #{inspect(e)}")
        {:error, e}
    end
  end

  # TODO:
  # This will create a Create activity, which we need internally at the moment.
  def fetch_object_from_id(id, options \\ []) do
    if object = Object.get_cached_by_ap_id(id) do
      {:ok, object}
    else
      Logger.info("Fetching #{id} via AP")

      with {:fetch, {:ok, data}} <- {:fetch, fetch_and_contain_remote_object_from_id(id)},
           {:normalize, nil} <- {:normalize, Object.normalize(data, false)},
           params <- %{
             "type" => "Create",
             "to" => data["to"],
             "cc" => data["cc"],
             # Should we seriously keep this attributedTo thing?
             "actor" => data["actor"] || data["attributedTo"],
             "object" => data
           },
           {:containment, :ok} <- {:containment, Containment.contain_origin(id, params)},
           {:ok, activity} <- Transmogrifier.handle_incoming(params, options),
           {:object, _data, %Object{} = object} <-
             {:object, data, Object.normalize(activity, false)} do
        {:ok, object}
      else
        {:containment, _} ->
          {:error, "Object containment failed."}

        {:error, {:reject, nil}} ->
          {:reject, nil}

        {:object, data, nil} ->
          reinject_object(data)

        {:normalize, object = %Object{}} ->
          {:ok, object}

        _e ->
          # Only fallback when receiving a fetch/normalization error with ActivityPub
          Logger.info("Couldn't get object via AP, trying out OStatus fetching...")

          # FIXME: OStatus Object Containment?
          case OStatus.fetch_activity_from_url(id) do
            {:ok, [activity | _]} -> {:ok, Object.normalize(activity, false)}
            e -> e
          end
      end
    end
  end

  def fetch_object_from_id!(id, options \\ []) do
    with {:ok, object} <- fetch_object_from_id(id, options) do
      object
    else
      _e ->
        nil
    end
  end

  defp make_signature(id, date) do
    uri = URI.parse(id)

    signature =
      InternalFetchActor.get_actor()
      |> Signature.sign(%{
        "(request-target)": "get #{uri.path}",
        host: uri.host,
        date: date
      })

    [{:Signature, signature}]
  end

  defp sign_fetch(headers, id, date) do
    if Pleroma.Config.get([:activitypub, :sign_object_fetches]) do
      headers ++ make_signature(id, date)
    else
      headers
    end
  end

  defp maybe_date_fetch(headers, date) do
    if Pleroma.Config.get([:activitypub, :sign_object_fetches]) do
      headers ++ [{:Date, date}]
    else
      headers
    end
  end

  def fetch_and_contain_remote_object_from_id(id) do
    Logger.info("Fetching object #{id} via AP")

    date =
      NaiveDateTime.utc_now()
      |> Timex.format!("{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} GMT")

    headers =
      [{:Accept, "application/activity+json"}]
      |> maybe_date_fetch(date)
      |> sign_fetch(id, date)

    Logger.debug("Fetch headers: #{inspect(headers)}")

    with true <- String.starts_with?(id, "http"),
         {:ok, %{body: body, status: code}} when code in 200..299 <- HTTP.get(id, headers),
         {:ok, data} <- Jason.decode(body),
         :ok <- Containment.contain_origin_from_id(id, data) do
      {:ok, data}
    else
      {:ok, %{status: code}} when code in [404, 410] ->
        {:error, "Object has been deleted"}

      e ->
        {:error, e}
    end
  end
end
