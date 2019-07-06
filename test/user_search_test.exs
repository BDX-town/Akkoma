# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.UserSearchTest do
  alias Pleroma.Repo
  alias Pleroma.User
  use Pleroma.DataCase

  import Pleroma.Factory

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  describe "User.search" do
    test "accepts limit parameter" do
      Enum.each(0..4, &insert(:user, %{nickname: "john#{&1}"}))
      assert length(User.search("john", limit: 3)) == 3
      assert length(User.search("john")) == 5
    end

    test "accepts offset parameter" do
      Enum.each(0..4, &insert(:user, %{nickname: "john#{&1}"}))
      assert length(User.search("john", limit: 3)) == 3
      assert length(User.search("john", limit: 3, offset: 3)) == 2
    end

    test "finds a user by full or partial nickname" do
      user = insert(:user, %{nickname: "john"})

      Enum.each(["john", "jo", "j"], fn query ->
        assert user ==
                 User.search(query)
                 |> List.first()
                 |> Map.put(:search_rank, nil)
                 |> Map.put(:search_type, nil)
      end)
    end

    test "finds a user by full or partial name" do
      user = insert(:user, %{name: "John Doe"})

      Enum.each(["John Doe", "JOHN", "doe", "j d", "j", "d"], fn query ->
        assert user ==
                 User.search(query)
                 |> List.first()
                 |> Map.put(:search_rank, nil)
                 |> Map.put(:search_type, nil)
      end)
    end

    test "finds users, preferring nickname matches over name matches" do
      u1 = insert(:user, %{name: "lain", nickname: "nick1"})
      u2 = insert(:user, %{nickname: "lain", name: "nick1"})

      assert [u2.id, u1.id] == Enum.map(User.search("lain"), & &1.id)
    end

    test "finds users, considering density of matched tokens" do
      u1 = insert(:user, %{name: "Bar Bar plus Word Word"})
      u2 = insert(:user, %{name: "Word Word Bar Bar Bar"})

      assert [u2.id, u1.id] == Enum.map(User.search("bar word"), & &1.id)
    end

    test "finds users, ranking by similarity" do
      u1 = insert(:user, %{name: "lain"})
      _u2 = insert(:user, %{name: "ean"})
      u3 = insert(:user, %{name: "ebn", nickname: "lain@mastodon.social"})
      u4 = insert(:user, %{nickname: "lain@pleroma.soykaf.com"})

      assert [u4.id, u3.id, u1.id] == Enum.map(User.search("lain@ple", for_user: u1), & &1.id)
    end

    test "finds users, handling misspelled requests" do
      u1 = insert(:user, %{name: "lain"})

      assert [u1.id] == Enum.map(User.search("laiin"), & &1.id)
    end

    test "finds users, boosting ranks of friends and followers" do
      u1 = insert(:user)
      u2 = insert(:user, %{name: "Doe"})
      follower = insert(:user, %{name: "Doe"})
      friend = insert(:user, %{name: "Doe"})

      {:ok, follower} = User.follow(follower, u1)
      {:ok, u1} = User.follow(u1, friend)

      assert [friend.id, follower.id, u2.id] --
               Enum.map(User.search("doe", resolve: false, for_user: u1), & &1.id) == []
    end

    test "finds followers of user by partial name" do
      u1 = insert(:user)
      u2 = insert(:user, %{name: "Jimi"})
      follower_jimi = insert(:user, %{name: "Jimi Hendrix"})
      follower_lizz = insert(:user, %{name: "Lizz Wright"})
      friend = insert(:user, %{name: "Jimi"})

      {:ok, follower_jimi} = User.follow(follower_jimi, u1)
      {:ok, _follower_lizz} = User.follow(follower_lizz, u2)
      {:ok, u1} = User.follow(u1, friend)

      assert Enum.map(User.search("jimi", following: true, for_user: u1), & &1.id) == [
               follower_jimi.id
             ]

      assert User.search("lizz", following: true, for_user: u1) == []
    end

    test "find local and remote users for authenticated users" do
      u1 = insert(:user, %{name: "lain"})
      u2 = insert(:user, %{name: "ebn", nickname: "lain@mastodon.social", local: false})
      u3 = insert(:user, %{nickname: "lain@pleroma.soykaf.com", local: false})

      results =
        "lain"
        |> User.search(for_user: u1)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert [u1.id, u2.id, u3.id] == results
    end

    test "find only local users for unauthenticated users" do
      %{id: id} = insert(:user, %{name: "lain"})
      insert(:user, %{name: "ebn", nickname: "lain@mastodon.social", local: false})
      insert(:user, %{nickname: "lain@pleroma.soykaf.com", local: false})

      assert [%{id: ^id}] = User.search("lain")
    end

    test "find only local users for authenticated users when `limit_to_local_content` is `:all`" do
      Pleroma.Config.put([:instance, :limit_to_local_content], :all)

      %{id: id} = insert(:user, %{name: "lain"})
      insert(:user, %{name: "ebn", nickname: "lain@mastodon.social", local: false})
      insert(:user, %{nickname: "lain@pleroma.soykaf.com", local: false})

      assert [%{id: ^id}] = User.search("lain")

      Pleroma.Config.put([:instance, :limit_to_local_content], :unauthenticated)
    end

    test "find all users for unauthenticated users when `limit_to_local_content` is `false`" do
      Pleroma.Config.put([:instance, :limit_to_local_content], false)

      u1 = insert(:user, %{name: "lain"})
      u2 = insert(:user, %{name: "ebn", nickname: "lain@mastodon.social", local: false})
      u3 = insert(:user, %{nickname: "lain@pleroma.soykaf.com", local: false})

      results =
        "lain"
        |> User.search()
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert [u1.id, u2.id, u3.id] == results

      Pleroma.Config.put([:instance, :limit_to_local_content], :unauthenticated)
    end

    test "finds a user whose name is nil" do
      _user = insert(:user, %{name: "notamatch", nickname: "testuser@pleroma.amplifie.red"})
      user_two = insert(:user, %{name: nil, nickname: "lain@pleroma.soykaf.com"})

      assert user_two ==
               User.search("lain@pleroma.soykaf.com")
               |> List.first()
               |> Map.put(:search_rank, nil)
               |> Map.put(:search_type, nil)
    end

    test "does not yield false-positive matches" do
      insert(:user, %{name: "John Doe"})

      Enum.each(["mary", "a", ""], fn query ->
        assert [] == User.search(query)
      end)
    end

    test "works with URIs" do
      user = insert(:user)

      results =
        User.search("http://mastodon.example.org/users/admin", resolve: true, for_user: user)

      result = results |> List.first()

      user = User.get_cached_by_ap_id("http://mastodon.example.org/users/admin")

      assert length(results) == 1
      assert user == result |> Map.put(:search_rank, nil) |> Map.put(:search_type, nil)
    end

    test "excludes a blocked users from search result" do
      user = insert(:user, %{nickname: "Bill"})

      [blocked_user | users] = Enum.map(0..3, &insert(:user, %{nickname: "john#{&1}"}))

      blocked_user2 =
        insert(
          :user,
          %{nickname: "john awful", ap_id: "https://awful-and-rude-instance.com/user/bully"}
        )

      User.block_domain(user, "awful-and-rude-instance.com")
      User.block(user, blocked_user)

      account_ids = User.search("john", for_user: refresh_record(user)) |> collect_ids

      assert account_ids == collect_ids(users)
      refute Enum.member?(account_ids, blocked_user.id)
      refute Enum.member?(account_ids, blocked_user2.id)
      assert length(account_ids) == 3
    end
  end
end
