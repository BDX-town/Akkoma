# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.MastodonAPI.AccountViewTest do
  use Pleroma.DataCase
  import Pleroma.Factory
  alias Pleroma.User
  alias Pleroma.Web.MastodonAPI.AccountView

  test "Represent a user account" do
    source_data = %{
      "tag" => [
        %{
          "type" => "Emoji",
          "icon" => %{"url" => "/file.png"},
          "name" => ":karjalanpiirakka:"
        }
      ]
    }

    user =
      insert(:user, %{
        info: %{note_count: 5, follower_count: 3, source_data: source_data},
        nickname: "shp@shitposter.club",
        name: ":karjalanpiirakka: shp",
        bio: "<script src=\"invalid-html\"></script><span>valid html</span>",
        inserted_at: ~N[2017-08-15 15:47:06.597036]
      })

    expected = %{
      id: to_string(user.id),
      username: "shp",
      acct: user.nickname,
      display_name: user.name,
      locked: false,
      created_at: "2017-08-15T15:47:06.000Z",
      followers_count: 3,
      following_count: 0,
      statuses_count: 5,
      note: "<span>valid html</span>",
      url: user.ap_id,
      avatar: "http://localhost:4001/images/avi.png",
      avatar_static: "http://localhost:4001/images/avi.png",
      header: "http://localhost:4001/images/banner.png",
      header_static: "http://localhost:4001/images/banner.png",
      emojis: [
        %{
          "static_url" => "/file.png",
          "url" => "/file.png",
          "shortcode" => "karjalanpiirakka",
          "visible_in_picker" => false
        }
      ],
      fields: [],
      bot: false,
      source: %{
        note: "",
        privacy: "public",
        sensitive: false
      },
      pleroma: %{
        confirmation_pending: false,
        tags: [],
        is_admin: false,
        is_moderator: false,
        relationship: %{}
      }
    }

    assert expected == AccountView.render("account.json", %{user: user})
  end

  test "Represent a Service(bot) account" do
    user =
      insert(:user, %{
        info: %{note_count: 5, follower_count: 3, source_data: %{"type" => "Service"}},
        nickname: "shp@shitposter.club",
        inserted_at: ~N[2017-08-15 15:47:06.597036]
      })

    expected = %{
      id: to_string(user.id),
      username: "shp",
      acct: user.nickname,
      display_name: user.name,
      locked: false,
      created_at: "2017-08-15T15:47:06.000Z",
      followers_count: 3,
      following_count: 0,
      statuses_count: 5,
      note: user.bio,
      url: user.ap_id,
      avatar: "http://localhost:4001/images/avi.png",
      avatar_static: "http://localhost:4001/images/avi.png",
      header: "http://localhost:4001/images/banner.png",
      header_static: "http://localhost:4001/images/banner.png",
      emojis: [],
      fields: [],
      bot: true,
      source: %{
        note: "",
        privacy: "public",
        sensitive: false
      },
      pleroma: %{
        confirmation_pending: false,
        tags: [],
        is_admin: false,
        is_moderator: false,
        relationship: %{}
      }
    }

    assert expected == AccountView.render("account.json", %{user: user})
  end

  test "Represent a smaller mention" do
    user = insert(:user)

    expected = %{
      id: to_string(user.id),
      acct: user.nickname,
      username: user.nickname,
      url: user.ap_id
    }

    assert expected == AccountView.render("mention.json", %{user: user})
  end

  test "represent a relationship" do
    user = insert(:user)
    other_user = insert(:user)

    {:ok, user} = User.follow(user, other_user)
    {:ok, user} = User.block(user, other_user)

    expected = %{
      id: to_string(other_user.id),
      following: false,
      followed_by: false,
      blocking: true,
      muting: false,
      muting_notifications: false,
      requested: false,
      domain_blocking: false,
      showing_reblogs: true,
      endorsed: false
    }

    assert expected == AccountView.render("relationship.json", %{user: user, target: other_user})
  end

  test "represent an embedded relationship" do
    user =
      insert(:user, %{
        info: %{note_count: 5, follower_count: 3, source_data: %{"type" => "Service"}},
        nickname: "shp@shitposter.club",
        inserted_at: ~N[2017-08-15 15:47:06.597036]
      })

    other_user = insert(:user)

    {:ok, other_user} = User.follow(other_user, user)
    {:ok, other_user} = User.block(other_user, user)

    expected = %{
      id: to_string(user.id),
      username: "shp",
      acct: user.nickname,
      display_name: user.name,
      locked: false,
      created_at: "2017-08-15T15:47:06.000Z",
      followers_count: 3,
      following_count: 0,
      statuses_count: 5,
      note: user.bio,
      url: user.ap_id,
      avatar: "http://localhost:4001/images/avi.png",
      avatar_static: "http://localhost:4001/images/avi.png",
      header: "http://localhost:4001/images/banner.png",
      header_static: "http://localhost:4001/images/banner.png",
      emojis: [],
      fields: [],
      bot: true,
      source: %{
        note: "",
        privacy: "public",
        sensitive: false
      },
      pleroma: %{
        confirmation_pending: false,
        tags: [],
        is_admin: false,
        is_moderator: false,
        relationship: %{
          id: to_string(user.id),
          following: false,
          followed_by: false,
          blocking: true,
          muting: false,
          muting_notifications: false,
          requested: false,
          domain_blocking: false,
          showing_reblogs: true,
          endorsed: false
        }
      }
    }

    assert expected == AccountView.render("account.json", %{user: user, for: other_user})
  end
end
