# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.OStatus.OStatusController do
  use Pleroma.Web, :controller

  alias Pleroma.Activity
  alias Pleroma.Object
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.ActivityPubController
  alias Pleroma.Web.ActivityPub.ObjectView
  alias Pleroma.Web.ActivityPub.Visibility
  alias Pleroma.Web.Federator
  alias Pleroma.Web.OStatus
  alias Pleroma.Web.OStatus.ActivityRepresenter
  alias Pleroma.Web.OStatus.FeedRepresenter
  alias Pleroma.Web.XML

  plug(Pleroma.Web.FederatingPlug when action in [:salmon_incoming])

  action_fallback(:errors)

  def feed_redirect(conn, %{"nickname" => nickname}) do
    case get_format(conn) do
      "html" ->
        with %User{} = user <- User.get_cached_by_nickname_or_id(nickname) do
          Fallback.RedirectController.redirector_with_meta(conn, %{user: user})
        else
          nil -> {:error, :not_found}
        end

      "activity+json" ->
        ActivityPubController.call(conn, :user)

      "json" ->
        ActivityPubController.call(conn, :user)

      _ ->
        with %User{} = user <- User.get_cached_by_nickname(nickname) do
          redirect(conn, external: OStatus.feed_path(user))
        else
          nil -> {:error, :not_found}
        end
    end
  end

  def feed(conn, %{"nickname" => nickname} = params) do
    with %User{} = user <- User.get_cached_by_nickname(nickname) do
      query_params =
        Map.take(params, ["max_id"])
        |> Map.merge(%{"whole_db" => true, "actor_id" => user.ap_id})

      activities =
        ActivityPub.fetch_public_activities(query_params)
        |> Enum.reverse()

      response =
        user
        |> FeedRepresenter.to_simple_form(activities, [user])
        |> :xmerl.export_simple(:xmerl_xml)
        |> to_string

      conn
      |> put_resp_content_type("application/atom+xml")
      |> send_resp(200, response)
    else
      nil -> {:error, :not_found}
    end
  end

  defp decode_or_retry(body) do
    with {:ok, magic_key} <- Pleroma.Web.Salmon.fetch_magic_key(body),
         {:ok, doc} <- Pleroma.Web.Salmon.decode_and_validate(magic_key, body) do
      {:ok, doc}
    else
      _e ->
        with [decoded | _] <- Pleroma.Web.Salmon.decode(body),
             doc <- XML.parse_document(decoded),
             uri when not is_nil(uri) <- XML.string_from_xpath("/entry/author[1]/uri", doc),
             {:ok, _} <- Pleroma.Web.OStatus.make_user(uri, true),
             {:ok, magic_key} <- Pleroma.Web.Salmon.fetch_magic_key(body),
             {:ok, doc} <- Pleroma.Web.Salmon.decode_and_validate(magic_key, body) do
          {:ok, doc}
        end
    end
  end

  def salmon_incoming(conn, _) do
    {:ok, body, _conn} = read_body(conn)
    {:ok, doc} = decode_or_retry(body)

    Federator.incoming_doc(doc)

    conn
    |> send_resp(200, "")
  end

  def object(conn, %{"uuid" => uuid}) do
    if get_format(conn) in ["activity+json", "json"] do
      ActivityPubController.call(conn, :object)
    else
      with id <- o_status_url(conn, :object, uuid),
           {_, %Activity{} = activity} <- {:activity, Activity.get_create_by_object_ap_id(id)},
           {_, true} <- {:public?, Visibility.is_public?(activity)},
           %User{} = user <- User.get_cached_by_ap_id(activity.data["actor"]) do
        case get_format(conn) do
          "html" -> redirect(conn, to: "/notice/#{activity.id}")
          _ -> represent_activity(conn, nil, activity, user)
        end
      else
        {:public?, false} ->
          {:error, :not_found}

        {:activity, nil} ->
          {:error, :not_found}

        e ->
          e
      end
    end
  end

  def activity(conn, %{"uuid" => uuid}) do
    if get_format(conn) in ["activity+json", "json"] do
      ActivityPubController.call(conn, :activity)
    else
      with id <- o_status_url(conn, :activity, uuid),
           {_, %Activity{} = activity} <- {:activity, Activity.normalize(id)},
           {_, true} <- {:public?, Visibility.is_public?(activity)},
           %User{} = user <- User.get_cached_by_ap_id(activity.data["actor"]) do
        case format = get_format(conn) do
          "html" -> redirect(conn, to: "/notice/#{activity.id}")
          _ -> represent_activity(conn, format, activity, user)
        end
      else
        {:public?, false} ->
          {:error, :not_found}

        {:activity, nil} ->
          {:error, :not_found}

        e ->
          e
      end
    end
  end

  def notice(conn, %{"id" => id}) do
    with {_, %Activity{} = activity} <- {:activity, Activity.get_by_id(id)},
         {_, true} <- {:public?, Visibility.is_public?(activity)},
         %User{} = user <- User.get_cached_by_ap_id(activity.data["actor"]) do
      case format = get_format(conn) do
        "html" ->
          if activity.data["type"] == "Create" do
            %Object{} = object = Object.normalize(activity.data["object"])

            Fallback.RedirectController.redirector_with_meta(conn, %{
              activity_id: activity.id,
              object: object,
              url:
                Pleroma.Web.Router.Helpers.o_status_url(
                  Pleroma.Web.Endpoint,
                  :notice,
                  activity.id
                ),
              user: user
            })
          else
            Fallback.RedirectController.redirector(conn, nil)
          end

        _ ->
          represent_activity(conn, format, activity, user)
      end
    else
      {:public?, false} ->
        conn
        |> put_status(404)
        |> Fallback.RedirectController.redirector(nil, 404)

      {:activity, nil} ->
        conn
        |> Fallback.RedirectController.redirector(nil, 404)

      e ->
        e
    end
  end

  # Returns an HTML embedded <audio> or <video> player suitable for embed iframes.
  def notice_player(conn, %{"id" => id}) do
    with %Activity{data: %{"type" => "Create"}} = activity <- Activity.get_by_id(id),
         true <- Visibility.is_public?(activity),
         %Object{} = object <- Object.normalize(activity.data["object"]),
         %{data: %{"attachment" => [%{"url" => [url | _]} | _]}} <- object,
         true <- String.starts_with?(url["mediaType"], ["audio", "video"]) do
      conn
      |> put_layout(:metadata_player)
      |> put_resp_header("x-frame-options", "ALLOW")
      |> put_resp_header(
        "content-security-policy",
        "default-src 'none';style-src 'self' 'unsafe-inline';img-src 'self' data: https:; media-src 'self' https:;"
      )
      |> put_view(Pleroma.Web.Metadata.PlayerView)
      |> render("player.html", url)
    else
      _error ->
        conn
        |> put_status(404)
        |> Fallback.RedirectController.redirector(nil, 404)
    end
  end

  defp represent_activity(
         conn,
         "activity+json",
         %Activity{data: %{"type" => "Create"}} = activity,
         _user
       ) do
    object = Object.normalize(activity.data["object"])

    conn
    |> put_resp_header("content-type", "application/activity+json")
    |> json(ObjectView.render("object.json", %{object: object}))
  end

  defp represent_activity(_conn, "activity+json", _, _) do
    {:error, :not_found}
  end

  defp represent_activity(conn, _, activity, user) do
    response =
      activity
      |> ActivityRepresenter.to_simple_form(user, true)
      |> ActivityRepresenter.wrap_with_entry()
      |> :xmerl.export_simple(:xmerl_xml)
      |> to_string

    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, response)
  end

  def errors(conn, {:error, :not_found}) do
    conn
    |> put_status(404)
    |> text("Not found")
  end

  def errors(conn, _) do
    conn
    |> put_status(500)
    |> text("Something went wrong")
  end
end
