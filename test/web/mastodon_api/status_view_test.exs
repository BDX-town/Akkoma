# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.StatusViewTest do
  use Pleroma.DataCase

  alias Pleroma.Activity
  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.CommonAPI.Utils
  alias Pleroma.Web.MastodonAPI.AccountView
  alias Pleroma.Web.MastodonAPI.StatusView
  alias Pleroma.Web.OStatus
  import Pleroma.Factory
  import Tesla.Mock

  setup do
    mock(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  test "returns a temporary ap_id based user for activities missing db users" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{"status" => "Hey @shp!", "visibility" => "direct"})

    Repo.delete(user)
    Cachex.clear(:user_cache)

    %{account: ms_user} = StatusView.render("status.json", activity: activity)

    assert ms_user.acct == "erroruser@example.com"
  end

  test "tries to get a user by nickname if fetching by ap_id doesn't work" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{"status" => "Hey @shp!", "visibility" => "direct"})

    {:ok, user} =
      user
      |> Ecto.Changeset.change(%{ap_id: "#{user.ap_id}/extension/#{user.nickname}"})
      |> Repo.update()

    Cachex.clear(:user_cache)

    result = StatusView.render("status.json", activity: activity)

    assert result[:account][:id] == to_string(user.id)
  end

  test "a note with null content" do
    note = insert(:note_activity)

    data =
      note.data
      |> put_in(["object", "content"], nil)

    note =
      note
      |> Map.put(:data, data)

    User.get_cached_by_ap_id(note.data["actor"])

    status = StatusView.render("status.json", %{activity: note})

    assert status.content == ""
  end

  test "a note activity" do
    note = insert(:note_activity)
    user = User.get_cached_by_ap_id(note.data["actor"])

    convo_id = Utils.context_to_conversation_id(note.data["object"]["context"])

    status = StatusView.render("status.json", %{activity: note})

    created_at =
      (note.data["object"]["published"] || "")
      |> String.replace(~r/\.\d+Z/, ".000Z")

    expected = %{
      id: to_string(note.id),
      uri: note.data["object"]["id"],
      url: Pleroma.Web.Router.Helpers.o_status_url(Pleroma.Web.Endpoint, :notice, note),
      account: AccountView.render("account.json", %{user: user}),
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      card: nil,
      reblog: nil,
      content: HtmlSanitizeEx.basic_html(note.data["object"]["content"]),
      created_at: created_at,
      reblogs_count: 0,
      replies_count: 0,
      favourites_count: 0,
      reblogged: false,
      bookmarked: false,
      favourited: false,
      muted: false,
      pinned: false,
      sensitive: false,
      spoiler_text: note.data["object"]["summary"],
      visibility: "public",
      media_attachments: [],
      mentions: [],
      tags: [
        %{
          name: "#{note.data["object"]["tag"]}",
          url: "/tag/#{note.data["object"]["tag"]}"
        }
      ],
      application: %{
        name: "Web",
        website: nil
      },
      language: nil,
      emojis: [
        %{
          shortcode: "2hu",
          url: "corndog.png",
          static_url: "corndog.png",
          visible_in_picker: false
        }
      ],
      pleroma: %{
        local: true,
        conversation_id: convo_id
      }
    }

    assert status == expected
  end

  test "tells if the message is muted for some reason" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, user} = User.mute(user, other_user)

    {:ok, activity} = CommonAPI.post(other_user, %{"status" => "test"})
    status = StatusView.render("status.json", %{activity: activity})

    assert status.muted == false

    status = StatusView.render("status.json", %{activity: activity, for: user})

    assert status.muted == true
  end

  test "a reply" do
    note = insert(:note_activity)
    user = insert(:user)

    {:ok, activity} =
      CommonAPI.post(user, %{"status" => "he", "in_reply_to_status_id" => note.id})

    status = StatusView.render("status.json", %{activity: activity})

    assert status.in_reply_to_id == to_string(note.id)

    [status] = StatusView.render("index.json", %{activities: [activity], as: :activity})

    assert status.in_reply_to_id == to_string(note.id)
  end

  test "contains mentions" do
    incoming = File.read!("test/fixtures/incoming_reply_mastodon.xml")
    # a user with this ap id might be in the cache.
    recipient = "https://pleroma.soykaf.com/users/lain"
    user = insert(:user, %{ap_id: recipient})

    {:ok, [activity]} = OStatus.handle_incoming(incoming)

    status = StatusView.render("status.json", %{activity: activity})

    actor = User.get_by_ap_id(activity.actor)

    assert status.mentions ==
             Enum.map([user, actor], fn u -> AccountView.render("mention.json", %{user: u}) end)
  end

  test "attachments" do
    object = %{
      "type" => "Image",
      "url" => [
        %{
          "mediaType" => "image/png",
          "href" => "someurl"
        }
      ],
      "uuid" => 6
    }

    expected = %{
      id: "1638338801",
      type: "image",
      url: "someurl",
      remote_url: "someurl",
      preview_url: "someurl",
      text_url: "someurl",
      description: nil,
      pleroma: %{mime_type: "image/png"}
    }

    assert expected == StatusView.render("attachment.json", %{attachment: object})

    # If theres a "id", use that instead of the generated one
    object = Map.put(object, "id", 2)
    assert %{id: "2"} = StatusView.render("attachment.json", %{attachment: object})
  end

  test "a reblog" do
    user = insert(:user)
    activity = insert(:note_activity)

    {:ok, reblog, _} = CommonAPI.repeat(activity.id, user)

    represented = StatusView.render("status.json", %{for: user, activity: reblog})

    assert represented[:id] == to_string(reblog.id)
    assert represented[:reblog][:id] == to_string(activity.id)
    assert represented[:emojis] == []
  end

  test "a peertube video" do
    user = insert(:user)

    {:ok, object} =
      ActivityPub.fetch_object_from_id(
        "https://peertube.moe/videos/watch/df5f464b-be8d-46fb-ad81-2d4c2d1630e3"
      )

    %Activity{} = activity = Activity.get_create_by_object_ap_id(object.data["id"])

    represented = StatusView.render("status.json", %{for: user, activity: activity})

    assert represented[:id] == to_string(activity.id)
    assert length(represented[:media_attachments]) == 1
  end

  describe "build_tags/1" do
    test "it returns a a dictionary tags" do
      object_tags = [
        "fediverse",
        "mastodon",
        "nextcloud",
        %{
          "href" => "https://kawen.space/users/lain",
          "name" => "@lain@kawen.space",
          "type" => "Mention"
        }
      ]

      assert StatusView.build_tags(object_tags) == [
               %{name: "fediverse", url: "/tag/fediverse"},
               %{name: "mastodon", url: "/tag/mastodon"},
               %{name: "nextcloud", url: "/tag/nextcloud"}
             ]
    end
  end

  describe "rich media cards" do
    test "a rich media card without a site name renders correctly" do
      page_url = "http://example.com"

      card = %{
        url: page_url,
        image: page_url <> "/example.jpg",
        title: "Example website"
      }

      %{provider_name: "example.com"} =
        StatusView.render("card.json", %{page_url: page_url, rich_media: card})
    end

    test "a rich media card without a site name or image renders correctly" do
      page_url = "http://example.com"

      card = %{
        url: page_url,
        title: "Example website"
      }

      %{provider_name: "example.com"} =
        StatusView.render("card.json", %{page_url: page_url, rich_media: card})
    end

    test "a rich media card without an image renders correctly" do
      page_url = "http://example.com"

      card = %{
        url: page_url,
        site_name: "Example site name",
        title: "Example website"
      }

      %{provider_name: "Example site name"} =
        StatusView.render("card.json", %{page_url: page_url, rich_media: card})
    end

    test "a rich media card with all relevant data renders correctly" do
      page_url = "http://example.com"

      card = %{
        url: page_url,
        site_name: "Example site name",
        title: "Example website",
        image: page_url <> "/example.jpg",
        description: "Example description"
      }

      %{provider_name: "Example site name"} =
        StatusView.render("card.json", %{page_url: page_url, rich_media: card})
    end
  end
end
