# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.ActivityPub.UserView do
  use Pleroma.Web, :view

  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Transmogrifier
  alias Pleroma.Web.ActivityPub.Utils
  alias Pleroma.Web.Endpoint
  alias Pleroma.Web.Router.Helpers
  alias Pleroma.Web.Salmon
  alias Pleroma.Web.WebFinger

  import Ecto.Query

  def render("endpoints.json", %{user: %User{nickname: nil, local: true} = _user}) do
    %{"sharedInbox" => Helpers.activity_pub_url(Endpoint, :inbox)}
  end

  def render("endpoints.json", %{user: %User{local: true} = _user}) do
    %{
      "oauthAuthorizationEndpoint" => Helpers.o_auth_url(Endpoint, :authorize),
      "oauthRegistrationEndpoint" => Helpers.mastodon_api_url(Endpoint, :create_app),
      "oauthTokenEndpoint" => Helpers.o_auth_url(Endpoint, :token_exchange),
      "sharedInbox" => Helpers.activity_pub_url(Endpoint, :inbox)
    }
  end

  def render("endpoints.json", _), do: %{}

  # the instance itself is not a Person, but instead an Application
  def render("user.json", %{user: %{nickname: nil} = user}) do
    {:ok, user} = WebFinger.ensure_keys_present(user)
    {:ok, _, public_key} = Salmon.keys_from_pem(user.info.keys)
    public_key = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
    public_key = :public_key.pem_encode([public_key])

    endpoints = render("endpoints.json", %{user: user})

    %{
      "id" => user.ap_id,
      "type" => "Application",
      "following" => "#{user.ap_id}/following",
      "followers" => "#{user.ap_id}/followers",
      "inbox" => "#{user.ap_id}/inbox",
      "name" => "Pleroma",
      "summary" => "Virtual actor for Pleroma relay",
      "url" => user.ap_id,
      "manuallyApprovesFollowers" => false,
      "publicKey" => %{
        "id" => "#{user.ap_id}#main-key",
        "owner" => user.ap_id,
        "publicKeyPem" => public_key
      },
      "endpoints" => endpoints
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("user.json", %{user: user}) do
    {:ok, user} = WebFinger.ensure_keys_present(user)
    {:ok, _, public_key} = Salmon.keys_from_pem(user.info.keys)
    public_key = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
    public_key = :public_key.pem_encode([public_key])

    endpoints = render("endpoints.json", %{user: user})

    %{
      "id" => user.ap_id,
      "type" => "Person",
      "following" => "#{user.ap_id}/following",
      "followers" => "#{user.ap_id}/followers",
      "inbox" => "#{user.ap_id}/inbox",
      "outbox" => "#{user.ap_id}/outbox",
      "preferredUsername" => user.nickname,
      "name" => user.name,
      "summary" => user.bio,
      "url" => user.ap_id,
      "manuallyApprovesFollowers" => user.info.locked,
      "publicKey" => %{
        "id" => "#{user.ap_id}#main-key",
        "owner" => user.ap_id,
        "publicKeyPem" => public_key
      },
      "endpoints" => endpoints,
      "icon" => %{
        "type" => "Image",
        "url" => User.avatar_url(user)
      },
      "image" => %{
        "type" => "Image",
        "url" => User.banner_url(user)
      },
      "tag" => user.info.source_data["tag"] || []
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("following.json", %{user: user, page: page}) do
    query = User.get_friends_query(user)
    query = from(user in query, select: [:ap_id])
    following = Repo.all(query)

    total =
      if !user.info.hide_follows do
        length(following)
      else
        0
      end

    collection(following, "#{user.ap_id}/following", page, !user.info.hide_follows, total)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("following.json", %{user: user}) do
    query = User.get_friends_query(user)
    query = from(user in query, select: [:ap_id])
    following = Repo.all(query)

    total =
      if !user.info.hide_follows do
        length(following)
      else
        0
      end

    %{
      "id" => "#{user.ap_id}/following",
      "type" => "OrderedCollection",
      "totalItems" => total,
      "first" => collection(following, "#{user.ap_id}/following", 1, !user.info.hide_follows)
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("followers.json", %{user: user, page: page}) do
    query = User.get_followers_query(user)
    query = from(user in query, select: [:ap_id])
    followers = Repo.all(query)

    total =
      if !user.info.hide_followers do
        length(followers)
      else
        0
      end

    collection(followers, "#{user.ap_id}/followers", page, !user.info.hide_followers, total)
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("followers.json", %{user: user}) do
    query = User.get_followers_query(user)
    query = from(user in query, select: [:ap_id])
    followers = Repo.all(query)

    total =
      if !user.info.hide_followers do
        length(followers)
      else
        0
      end

    %{
      "id" => "#{user.ap_id}/followers",
      "type" => "OrderedCollection",
      "totalItems" => total,
      "first" =>
        collection(followers, "#{user.ap_id}/followers", 1, !user.info.hide_followers, total)
    }
    |> Map.merge(Utils.make_json_ld_header())
  end

  def render("outbox.json", %{user: user, max_id: max_qid}) do
    params = %{
      "limit" => "10"
    }

    params =
      if max_qid != nil do
        Map.put(params, "max_id", max_qid)
      else
        params
      end

    activities = ActivityPub.fetch_user_activities(user, nil, params)

    {max_id, min_id, collection} =
      if length(activities) > 0 do
        {
          Enum.at(Enum.reverse(activities), 0).id,
          Enum.at(activities, 0).id,
          Enum.map(activities, fn act ->
            {:ok, data} = Transmogrifier.prepare_outgoing(act.data)
            data
          end)
        }
      else
        {
          0,
          0,
          []
        }
      end

    iri = "#{user.ap_id}/outbox"

    page = %{
      "id" => "#{iri}?max_id=#{max_id}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "orderedItems" => collection,
      "next" => "#{iri}?max_id=#{min_id}"
    }

    if max_qid == nil do
      %{
        "id" => iri,
        "type" => "OrderedCollection",
        "first" => page
      }
      |> Map.merge(Utils.make_json_ld_header())
    else
      page |> Map.merge(Utils.make_json_ld_header())
    end
  end

  def render("inbox.json", %{user: user, max_id: max_qid}) do
    params = %{
      "limit" => "10"
    }

    params =
      if max_qid != nil do
        Map.put(params, "max_id", max_qid)
      else
        params
      end

    activities = ActivityPub.fetch_activities([user.ap_id | user.following], params)

    min_id = Enum.at(Enum.reverse(activities), 0).id
    max_id = Enum.at(activities, 0).id

    collection =
      Enum.map(activities, fn act ->
        {:ok, data} = Transmogrifier.prepare_outgoing(act.data)
        data
      end)

    iri = "#{user.ap_id}/inbox"

    page = %{
      "id" => "#{iri}?max_id=#{max_id}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "orderedItems" => collection,
      "next" => "#{iri}?max_id=#{min_id}"
    }

    if max_qid == nil do
      %{
        "id" => iri,
        "type" => "OrderedCollection",
        "first" => page
      }
      |> Map.merge(Utils.make_json_ld_header())
    else
      page |> Map.merge(Utils.make_json_ld_header())
    end
  end

  def collection(collection, iri, page, show_items \\ true, total \\ nil) do
    offset = (page - 1) * 10
    items = Enum.slice(collection, offset, 10)
    items = Enum.map(items, fn user -> user.ap_id end)
    total = total || length(collection)

    map = %{
      "id" => "#{iri}?page=#{page}",
      "type" => "OrderedCollectionPage",
      "partOf" => iri,
      "totalItems" => total,
      "orderedItems" => if(show_items, do: items, else: [])
    }

    if offset < total do
      Map.put(map, "next", "#{iri}?page=#{page + 1}")
    else
      map
    end
  end
end
