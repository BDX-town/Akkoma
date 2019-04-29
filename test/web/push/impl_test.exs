# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.Push.ImplTest do
  use Pleroma.DataCase

  alias Pleroma.Web.Push.Impl
  alias Pleroma.Web.Push.Subscription

  import Pleroma.Factory

  setup_all do
    Tesla.Mock.mock_global(fn
      %{method: :post, url: "https://example.com/example/1234"} ->
        %Tesla.Env{status: 200}

      %{method: :post, url: "https://example.com/example/not_found"} ->
        %Tesla.Env{status: 400}

      %{method: :post, url: "https://example.com/example/bad"} ->
        %Tesla.Env{status: 100}
    end)

    :ok
  end

  @sub %{
    endpoint: "https://example.com/example/1234",
    keys: %{
      auth: "8eDyX_uCN0XRhSbY5hs7Hg==",
      p256dh:
        "BCIWgsnyXDv1VkhqL2P7YRBvdeuDnlwAPT2guNhdIoW3IP7GmHh1SMKPLxRf7x8vJy6ZFK3ol2ohgn_-0yP7QQA="
    }
  }
  @api_key "BASgACIHpN1GYgzSRp"
  @message "@Bob: Lorem ipsum dolor sit amet, consectetur  adipiscing elit. Fusce sagittis fini..."

  test "performs sending notifications" do
    user = insert(:user)
    user2 = insert(:user)
    insert(:push_subscription, user: user, data: %{alerts: %{"mention" => true}})
    insert(:push_subscription, user: user2, data: %{alerts: %{"mention" => true}})

    insert(:push_subscription,
      user: user,
      data: %{alerts: %{"follow" => true, "mention" => true}}
    )

    insert(:push_subscription,
      user: user,
      data: %{alerts: %{"follow" => true, "mention" => false}}
    )

    notif =
      insert(:notification,
        user: user,
        activity: %Pleroma.Activity{
          data: %{
            "type" => "Create",
            "actor" => user.ap_id,
            "object" => %{"content" => "<Lorem ipsum dolor sit amet."}
          }
        }
      )

    assert Impl.perform(notif) == [:ok, :ok]
  end

  @tag capture_log: true
  test "returns error if notif does not match " do
    assert Impl.perform(%{}) == :error
  end

  test "successful message sending" do
    assert Impl.push_message(@message, @sub, @api_key, %Subscription{}) == :ok
  end

  @tag capture_log: true
  test "fail message sending" do
    assert Impl.push_message(
             @message,
             Map.merge(@sub, %{endpoint: "https://example.com/example/bad"}),
             @api_key,
             %Subscription{}
           ) == :error
  end

  test "delete subsciption if restult send message between 400..500" do
    subscription = insert(:push_subscription)

    assert Impl.push_message(
             @message,
             Map.merge(@sub, %{endpoint: "https://example.com/example/not_found"}),
             @api_key,
             subscription
           ) == :ok

    refute Pleroma.Repo.get(Subscription, subscription.id)
  end

  test "renders body for create activity" do
    assert Impl.format_body(
             %{
               activity: %{
                 data: %{
                   "type" => "Create",
                   "object" => %{
                     "content" =>
                       "<span>Lorem ipsum dolor sit amet</span>, consectetur :firefox: adipiscing elit. Fusce sagittis finibus turpis."
                   }
                 }
               }
             },
             %{nickname: "Bob"}
           ) ==
             "@Bob: Lorem ipsum dolor sit amet, consectetur  adipiscing elit. Fusce sagittis fini..."
  end

  test "renders body for follow activity" do
    assert Impl.format_body(%{activity: %{data: %{"type" => "Follow"}}}, %{nickname: "Bob"}) ==
             "@Bob has followed you"
  end

  test "renders body for announce activity" do
    user = insert(:user)

    note =
      insert(:note, %{
        data: %{
          "content" =>
            "<span>Lorem ipsum dolor sit amet</span>, consectetur :firefox: adipiscing elit. Fusce sagittis finibus turpis."
        }
      })

    note_activity = insert(:note_activity, %{note: note})
    announce_activity = insert(:announce_activity, %{user: user, note_activity: note_activity})

    assert Impl.format_body(%{activity: announce_activity}, user) ==
             "@#{user.nickname} repeated: Lorem ipsum dolor sit amet, consectetur  adipiscing elit. Fusce sagittis fini..."
  end

  test "renders body for like activity" do
    assert Impl.format_body(%{activity: %{data: %{"type" => "Like"}}}, %{nickname: "Bob"}) ==
             "@Bob has favorited your post"
  end
end
