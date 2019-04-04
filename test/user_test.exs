# Pleroma: A lightweight social networking server
# Copyright © 2017-2018 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.UserTest do
  alias Pleroma.Activity
  alias Pleroma.Builders.UserBuilder
  alias Pleroma.Repo
  alias Pleroma.User
  alias Pleroma.Web.CommonAPI

  use Pleroma.DataCase

  import Pleroma.Factory

  setup_all do
    Tesla.Mock.mock_global(fn env -> apply(HttpRequestMock, :request, [env]) end)
    :ok
  end

  describe "when tags are nil" do
    test "tagging a user" do
      user = insert(:user, %{tags: nil})
      user = User.tag(user, ["cool", "dude"])

      assert "cool" in user.tags
      assert "dude" in user.tags
    end

    test "untagging a user" do
      user = insert(:user, %{tags: nil})
      user = User.untag(user, ["cool", "dude"])

      assert user.tags == []
    end
  end

  test "ap_id returns the activity pub id for the user" do
    user = UserBuilder.build()

    expected_ap_id = "#{Pleroma.Web.base_url()}/users/#{user.nickname}"

    assert expected_ap_id == User.ap_id(user)
  end

  test "ap_followers returns the followers collection for the user" do
    user = UserBuilder.build()

    expected_followers_collection = "#{User.ap_id(user)}/followers"

    assert expected_followers_collection == User.ap_followers(user)
  end

  test "returns all pending follow requests" do
    unlocked = insert(:user)
    locked = insert(:user, %{info: %{locked: true}})
    follower = insert(:user)

    Pleroma.Web.TwitterAPI.TwitterAPI.follow(follower, %{"user_id" => unlocked.id})
    Pleroma.Web.TwitterAPI.TwitterAPI.follow(follower, %{"user_id" => locked.id})

    assert {:ok, []} = User.get_follow_requests(unlocked)
    assert {:ok, [activity]} = User.get_follow_requests(locked)

    assert activity
  end

  test "doesn't return already accepted or duplicate follow requests" do
    locked = insert(:user, %{info: %{locked: true}})
    pending_follower = insert(:user)
    accepted_follower = insert(:user)

    Pleroma.Web.TwitterAPI.TwitterAPI.follow(pending_follower, %{"user_id" => locked.id})
    Pleroma.Web.TwitterAPI.TwitterAPI.follow(pending_follower, %{"user_id" => locked.id})
    Pleroma.Web.TwitterAPI.TwitterAPI.follow(accepted_follower, %{"user_id" => locked.id})
    User.maybe_follow(accepted_follower, locked)

    assert {:ok, [activity]} = User.get_follow_requests(locked)
    assert activity
  end

  test "follow_all follows mutliple users" do
    user = insert(:user)
    followed_zero = insert(:user)
    followed_one = insert(:user)
    followed_two = insert(:user)
    blocked = insert(:user)
    not_followed = insert(:user)
    reverse_blocked = insert(:user)

    {:ok, user} = User.block(user, blocked)
    {:ok, reverse_blocked} = User.block(reverse_blocked, user)

    {:ok, user} = User.follow(user, followed_zero)

    {:ok, user} = User.follow_all(user, [followed_one, followed_two, blocked, reverse_blocked])

    assert User.following?(user, followed_one)
    assert User.following?(user, followed_two)
    assert User.following?(user, followed_zero)
    refute User.following?(user, not_followed)
    refute User.following?(user, blocked)
    refute User.following?(user, reverse_blocked)
  end

  test "follow_all follows mutliple users without duplicating" do
    user = insert(:user)
    followed_zero = insert(:user)
    followed_one = insert(:user)
    followed_two = insert(:user)

    {:ok, user} = User.follow_all(user, [followed_zero, followed_one])
    assert length(user.following) == 3

    {:ok, user} = User.follow_all(user, [followed_one, followed_two])
    assert length(user.following) == 4
  end

  test "follow takes a user and another user" do
    user = insert(:user)
    followed = insert(:user)

    {:ok, user} = User.follow(user, followed)

    user = User.get_by_id(user.id)

    followed = User.get_by_ap_id(followed.ap_id)
    assert followed.info.follower_count == 1

    assert User.ap_followers(followed) in user.following
  end

  test "can't follow a deactivated users" do
    user = insert(:user)
    followed = insert(:user, info: %{deactivated: true})

    {:error, _} = User.follow(user, followed)
  end

  test "can't follow a user who blocked us" do
    blocker = insert(:user)
    blockee = insert(:user)

    {:ok, blocker} = User.block(blocker, blockee)

    {:error, _} = User.follow(blockee, blocker)
  end

  test "local users do not automatically follow local locked accounts" do
    follower = insert(:user, info: %{locked: true})
    followed = insert(:user, info: %{locked: true})

    {:ok, follower} = User.maybe_direct_follow(follower, followed)

    refute User.following?(follower, followed)
  end

  # This is a somewhat useless test.
  # test "following a remote user will ensure a websub subscription is present" do
  #   user = insert(:user)
  #   {:ok, followed} = OStatus.make_user("shp@social.heldscal.la")

  #   assert followed.local == false

  #   {:ok, user} = User.follow(user, followed)
  #   assert User.ap_followers(followed) in user.following

  #   query = from w in WebsubClientSubscription,
  #   where: w.topic == ^followed.info["topic"]
  #   websub = Repo.one(query)

  #   assert websub
  # end

  test "unfollow takes a user and another user" do
    followed = insert(:user)
    user = insert(:user, %{following: [User.ap_followers(followed)]})

    {:ok, user, _activity} = User.unfollow(user, followed)

    user = User.get_by_id(user.id)

    assert user.following == []
  end

  test "unfollow doesn't unfollow yourself" do
    user = insert(:user)

    {:error, _} = User.unfollow(user, user)

    user = User.get_by_id(user.id)
    assert user.following == [user.ap_id]
  end

  test "test if a user is following another user" do
    followed = insert(:user)
    user = insert(:user, %{following: [User.ap_followers(followed)]})

    assert User.following?(user, followed)
    refute User.following?(followed, user)
  end

  test "fetches correct profile for nickname beginning with number" do
    # Use old-style integer ID to try to reproduce the problem
    user = insert(:user, %{id: 1080})
    userwithnumbers = insert(:user, %{nickname: "#{user.id}garbage"})
    assert userwithnumbers == User.get_cached_by_nickname_or_id(userwithnumbers.nickname)
  end

  describe "user registration" do
    @full_user_data %{
      bio: "A guy",
      name: "my name",
      nickname: "nick",
      password: "test",
      password_confirmation: "test",
      email: "email@example.com"
    }

    test "it autofollows accounts that are set for it" do
      user = insert(:user)
      remote_user = insert(:user, %{local: false})

      Pleroma.Config.put([:instance, :autofollowed_nicknames], [
        user.nickname,
        remote_user.nickname
      ])

      cng = User.register_changeset(%User{}, @full_user_data)

      {:ok, registered_user} = User.register(cng)

      assert User.following?(registered_user, user)
      refute User.following?(registered_user, remote_user)

      Pleroma.Config.put([:instance, :autofollowed_nicknames], [])
    end

    test "it sends a welcome message if it is set" do
      welcome_user = insert(:user)

      Pleroma.Config.put([:instance, :welcome_user_nickname], welcome_user.nickname)
      Pleroma.Config.put([:instance, :welcome_message], "Hello, this is a cool site")

      cng = User.register_changeset(%User{}, @full_user_data)
      {:ok, registered_user} = User.register(cng)

      activity = Repo.one(Pleroma.Activity)
      assert registered_user.ap_id in activity.recipients
      assert activity.data["object"]["content"] =~ "cool site"
      assert activity.actor == welcome_user.ap_id

      Pleroma.Config.put([:instance, :welcome_user_nickname], nil)
      Pleroma.Config.put([:instance, :welcome_message], nil)
    end

    test "it requires an email, name, nickname and password, bio is optional" do
      @full_user_data
      |> Map.keys()
      |> Enum.each(fn key ->
        params = Map.delete(@full_user_data, key)
        changeset = User.register_changeset(%User{}, params)

        assert if key == :bio, do: changeset.valid?, else: not changeset.valid?
      end)
    end

    test "it restricts certain nicknames" do
      [restricted_name | _] = Pleroma.Config.get([Pleroma.User, :restricted_nicknames])

      assert is_bitstring(restricted_name)

      params =
        @full_user_data
        |> Map.put(:nickname, restricted_name)

      changeset = User.register_changeset(%User{}, params)

      refute changeset.valid?
    end

    test "it sets the password_hash, ap_id and following fields" do
      changeset = User.register_changeset(%User{}, @full_user_data)

      assert changeset.valid?

      assert is_binary(changeset.changes[:password_hash])
      assert changeset.changes[:ap_id] == User.ap_id(%User{nickname: @full_user_data.nickname})

      assert changeset.changes[:following] == [
               User.ap_followers(%User{nickname: @full_user_data.nickname})
             ]

      assert changeset.changes.follower_address == "#{changeset.changes.ap_id}/followers"
    end

    test "it ensures info is not nil" do
      changeset = User.register_changeset(%User{}, @full_user_data)

      assert changeset.valid?

      {:ok, user} =
        changeset
        |> Repo.insert()

      refute is_nil(user.info)
    end
  end

  describe "user registration, with :account_activation_required" do
    @full_user_data %{
      bio: "A guy",
      name: "my name",
      nickname: "nick",
      password: "test",
      password_confirmation: "test",
      email: "email@example.com"
    }

    setup do
      setting = Pleroma.Config.get([:instance, :account_activation_required])

      unless setting do
        Pleroma.Config.put([:instance, :account_activation_required], true)
        on_exit(fn -> Pleroma.Config.put([:instance, :account_activation_required], setting) end)
      end

      :ok
    end

    test "it creates unconfirmed user" do
      changeset = User.register_changeset(%User{}, @full_user_data)
      assert changeset.valid?

      {:ok, user} = Repo.insert(changeset)

      assert user.info.confirmation_pending
      assert user.info.confirmation_token
    end

    test "it creates confirmed user if :confirmed option is given" do
      changeset = User.register_changeset(%User{}, @full_user_data, confirmed: true)
      assert changeset.valid?

      {:ok, user} = Repo.insert(changeset)

      refute user.info.confirmation_pending
      refute user.info.confirmation_token
    end
  end

  describe "get_or_fetch/1" do
    test "gets an existing user by nickname" do
      user = insert(:user)
      fetched_user = User.get_or_fetch(user.nickname)

      assert user == fetched_user
    end

    test "gets an existing user by ap_id" do
      ap_id = "http://mastodon.example.org/users/admin"

      user =
        insert(
          :user,
          local: false,
          nickname: "admin@mastodon.example.org",
          ap_id: ap_id,
          info: %{}
        )

      fetched_user = User.get_or_fetch(ap_id)
      freshed_user = refresh_record(user)
      assert freshed_user == fetched_user
    end
  end

  describe "fetching a user from nickname or trying to build one" do
    test "gets an existing user" do
      user = insert(:user)
      fetched_user = User.get_or_fetch_by_nickname(user.nickname)

      assert user == fetched_user
    end

    test "gets an existing user, case insensitive" do
      user = insert(:user, nickname: "nick")
      fetched_user = User.get_or_fetch_by_nickname("NICK")

      assert user == fetched_user
    end

    test "gets an existing user by fully qualified nickname" do
      user = insert(:user)

      fetched_user =
        User.get_or_fetch_by_nickname(user.nickname <> "@" <> Pleroma.Web.Endpoint.host())

      assert user == fetched_user
    end

    test "gets an existing user by fully qualified nickname, case insensitive" do
      user = insert(:user, nickname: "nick")
      casing_altered_fqn = String.upcase(user.nickname <> "@" <> Pleroma.Web.Endpoint.host())

      fetched_user = User.get_or_fetch_by_nickname(casing_altered_fqn)

      assert user == fetched_user
    end

    test "fetches an external user via ostatus if no user exists" do
      fetched_user = User.get_or_fetch_by_nickname("shp@social.heldscal.la")
      assert fetched_user.nickname == "shp@social.heldscal.la"
    end

    test "returns nil if no user could be fetched" do
      fetched_user = User.get_or_fetch_by_nickname("nonexistant@social.heldscal.la")
      assert fetched_user == nil
    end

    test "returns nil for nonexistant local user" do
      fetched_user = User.get_or_fetch_by_nickname("nonexistant")
      assert fetched_user == nil
    end

    test "updates an existing user, if stale" do
      a_week_ago = NaiveDateTime.add(NaiveDateTime.utc_now(), -604_800)

      orig_user =
        insert(
          :user,
          local: false,
          nickname: "admin@mastodon.example.org",
          ap_id: "http://mastodon.example.org/users/admin",
          last_refreshed_at: a_week_ago,
          info: %{}
        )

      assert orig_user.last_refreshed_at == a_week_ago

      user = User.get_or_fetch_by_ap_id("http://mastodon.example.org/users/admin")
      assert user.info.source_data["endpoints"]

      refute user.last_refreshed_at == orig_user.last_refreshed_at
    end
  end

  test "returns an ap_id for a user" do
    user = insert(:user)

    assert User.ap_id(user) ==
             Pleroma.Web.Router.Helpers.o_status_url(
               Pleroma.Web.Endpoint,
               :feed_redirect,
               user.nickname
             )
  end

  test "returns an ap_followers link for a user" do
    user = insert(:user)

    assert User.ap_followers(user) ==
             Pleroma.Web.Router.Helpers.o_status_url(
               Pleroma.Web.Endpoint,
               :feed_redirect,
               user.nickname
             ) <> "/followers"
  end

  describe "remote user creation changeset" do
    @valid_remote %{
      bio: "hello",
      name: "Someone",
      nickname: "a@b.de",
      ap_id: "http...",
      info: %{some: "info"},
      avatar: %{some: "avatar"}
    }

    test "it confirms validity" do
      cs = User.remote_user_creation(@valid_remote)
      assert cs.valid?
    end

    test "it sets the follower_adress" do
      cs = User.remote_user_creation(@valid_remote)
      # remote users get a fake local follower address
      assert cs.changes.follower_address ==
               User.ap_followers(%User{nickname: @valid_remote[:nickname]})
    end

    test "it enforces the fqn format for nicknames" do
      cs = User.remote_user_creation(%{@valid_remote | nickname: "bla"})
      assert cs.changes.local == false
      assert cs.changes.avatar
      refute cs.valid?
    end

    test "it has required fields" do
      [:name, :ap_id]
      |> Enum.each(fn field ->
        cs = User.remote_user_creation(Map.delete(@valid_remote, field))
        refute cs.valid?
      end)
    end

    test "it restricts some sizes" do
      [bio: 5000, name: 100]
      |> Enum.each(fn {field, size} ->
        string = String.pad_leading(".", size)
        cs = User.remote_user_creation(Map.put(@valid_remote, field, string))
        assert cs.valid?

        string = String.pad_leading(".", size + 1)
        cs = User.remote_user_creation(Map.put(@valid_remote, field, string))
        refute cs.valid?
      end)
    end
  end

  describe "followers and friends" do
    test "gets all followers for a given user" do
      user = insert(:user)
      follower_one = insert(:user)
      follower_two = insert(:user)
      not_follower = insert(:user)

      {:ok, follower_one} = User.follow(follower_one, user)
      {:ok, follower_two} = User.follow(follower_two, user)

      {:ok, res} = User.get_followers(user)

      assert Enum.member?(res, follower_one)
      assert Enum.member?(res, follower_two)
      refute Enum.member?(res, not_follower)
    end

    test "gets all friends (followed users) for a given user" do
      user = insert(:user)
      followed_one = insert(:user)
      followed_two = insert(:user)
      not_followed = insert(:user)

      {:ok, user} = User.follow(user, followed_one)
      {:ok, user} = User.follow(user, followed_two)

      {:ok, res} = User.get_friends(user)

      followed_one = User.get_by_ap_id(followed_one.ap_id)
      followed_two = User.get_by_ap_id(followed_two.ap_id)
      assert Enum.member?(res, followed_one)
      assert Enum.member?(res, followed_two)
      refute Enum.member?(res, not_followed)
    end
  end

  describe "updating note and follower count" do
    test "it sets the info->note_count property" do
      note = insert(:note)

      user = User.get_by_ap_id(note.data["actor"])

      assert user.info.note_count == 0

      {:ok, user} = User.update_note_count(user)

      assert user.info.note_count == 1
    end

    test "it increases the info->note_count property" do
      note = insert(:note)
      user = User.get_by_ap_id(note.data["actor"])

      assert user.info.note_count == 0

      {:ok, user} = User.increase_note_count(user)

      assert user.info.note_count == 1

      {:ok, user} = User.increase_note_count(user)

      assert user.info.note_count == 2
    end

    test "it decreases the info->note_count property" do
      note = insert(:note)
      user = User.get_by_ap_id(note.data["actor"])

      assert user.info.note_count == 0

      {:ok, user} = User.increase_note_count(user)

      assert user.info.note_count == 1

      {:ok, user} = User.decrease_note_count(user)

      assert user.info.note_count == 0

      {:ok, user} = User.decrease_note_count(user)

      assert user.info.note_count == 0
    end

    test "it sets the info->follower_count property" do
      user = insert(:user)
      follower = insert(:user)

      User.follow(follower, user)

      assert user.info.follower_count == 0

      {:ok, user} = User.update_follower_count(user)

      assert user.info.follower_count == 1
    end
  end

  describe "follow_import" do
    test "it imports user followings from list" do
      [user1, user2, user3] = insert_list(3, :user)

      identifiers = [
        user2.ap_id,
        user3.nickname
      ]

      result = User.follow_import(user1, identifiers)
      assert is_list(result)
      assert result == [user2, user3]
    end
  end

  describe "mutes" do
    test "it mutes people" do
      user = insert(:user)
      muted_user = insert(:user)

      refute User.mutes?(user, muted_user)

      {:ok, user} = User.mute(user, muted_user)

      assert User.mutes?(user, muted_user)
    end

    test "it unmutes users" do
      user = insert(:user)
      muted_user = insert(:user)

      {:ok, user} = User.mute(user, muted_user)
      {:ok, user} = User.unmute(user, muted_user)

      refute User.mutes?(user, muted_user)
    end
  end

  describe "blocks" do
    test "it blocks people" do
      user = insert(:user)
      blocked_user = insert(:user)

      refute User.blocks?(user, blocked_user)

      {:ok, user} = User.block(user, blocked_user)

      assert User.blocks?(user, blocked_user)
    end

    test "it unblocks users" do
      user = insert(:user)
      blocked_user = insert(:user)

      {:ok, user} = User.block(user, blocked_user)
      {:ok, user} = User.unblock(user, blocked_user)

      refute User.blocks?(user, blocked_user)
    end

    test "blocks tear down cyclical follow relationships" do
      blocker = insert(:user)
      blocked = insert(:user)

      {:ok, blocker} = User.follow(blocker, blocked)
      {:ok, blocked} = User.follow(blocked, blocker)

      assert User.following?(blocker, blocked)
      assert User.following?(blocked, blocker)

      {:ok, blocker} = User.block(blocker, blocked)
      blocked = User.get_by_id(blocked.id)

      assert User.blocks?(blocker, blocked)

      refute User.following?(blocker, blocked)
      refute User.following?(blocked, blocker)
    end

    test "blocks tear down blocker->blocked follow relationships" do
      blocker = insert(:user)
      blocked = insert(:user)

      {:ok, blocker} = User.follow(blocker, blocked)

      assert User.following?(blocker, blocked)
      refute User.following?(blocked, blocker)

      {:ok, blocker} = User.block(blocker, blocked)
      blocked = User.get_by_id(blocked.id)

      assert User.blocks?(blocker, blocked)

      refute User.following?(blocker, blocked)
      refute User.following?(blocked, blocker)
    end

    test "blocks tear down blocked->blocker follow relationships" do
      blocker = insert(:user)
      blocked = insert(:user)

      {:ok, blocked} = User.follow(blocked, blocker)

      refute User.following?(blocker, blocked)
      assert User.following?(blocked, blocker)

      {:ok, blocker} = User.block(blocker, blocked)
      blocked = User.get_by_id(blocked.id)

      assert User.blocks?(blocker, blocked)

      refute User.following?(blocker, blocked)
      refute User.following?(blocked, blocker)
    end
  end

  describe "domain blocking" do
    test "blocks domains" do
      user = insert(:user)
      collateral_user = insert(:user, %{ap_id: "https://awful-and-rude-instance.com/user/bully"})

      {:ok, user} = User.block_domain(user, "awful-and-rude-instance.com")

      assert User.blocks?(user, collateral_user)
    end

    test "unblocks domains" do
      user = insert(:user)
      collateral_user = insert(:user, %{ap_id: "https://awful-and-rude-instance.com/user/bully"})

      {:ok, user} = User.block_domain(user, "awful-and-rude-instance.com")
      {:ok, user} = User.unblock_domain(user, "awful-and-rude-instance.com")

      refute User.blocks?(user, collateral_user)
    end
  end

  describe "blocks_import" do
    test "it imports user blocks from list" do
      [user1, user2, user3] = insert_list(3, :user)

      identifiers = [
        user2.ap_id,
        user3.nickname
      ]

      result = User.blocks_import(user1, identifiers)
      assert is_list(result)
      assert result == [user2, user3]
    end
  end

  test "get recipients from activity" do
    actor = insert(:user)
    user = insert(:user, local: true)
    user_two = insert(:user, local: false)
    addressed = insert(:user, local: true)
    addressed_remote = insert(:user, local: false)

    {:ok, activity} =
      CommonAPI.post(actor, %{
        "status" => "hey @#{addressed.nickname} @#{addressed_remote.nickname}"
      })

    assert Enum.map([actor, addressed], & &1.ap_id) --
             Enum.map(User.get_recipients_from_activity(activity), & &1.ap_id) == []

    {:ok, user} = User.follow(user, actor)
    {:ok, _user_two} = User.follow(user_two, actor)
    recipients = User.get_recipients_from_activity(activity)
    assert length(recipients) == 3
    assert user in recipients
    assert addressed in recipients
  end

  test ".deactivate can de-activate then re-activate a user" do
    user = insert(:user)
    assert false == user.info.deactivated
    {:ok, user} = User.deactivate(user)
    assert true == user.info.deactivated
    {:ok, user} = User.deactivate(user, false)
    assert false == user.info.deactivated
  end

  test ".delete_user_activities deletes all create activities" do
    user = insert(:user)

    {:ok, activity} = CommonAPI.post(user, %{"status" => "2hu"})
    {:ok, _} = User.delete_user_activities(user)

    # TODO: Remove favorites, repeats, delete activities.
    refute Activity.get_by_id(activity.id)
  end

  test ".delete deactivates a user, all follow relationships and all create activities" do
    user = insert(:user)
    followed = insert(:user)
    follower = insert(:user)

    {:ok, user} = User.follow(user, followed)
    {:ok, follower} = User.follow(follower, user)

    {:ok, activity} = CommonAPI.post(user, %{"status" => "2hu"})
    {:ok, activity_two} = CommonAPI.post(follower, %{"status" => "3hu"})

    {:ok, _, _} = CommonAPI.favorite(activity_two.id, user)
    {:ok, _, _} = CommonAPI.favorite(activity.id, follower)
    {:ok, _, _} = CommonAPI.repeat(activity.id, follower)

    {:ok, _} = User.delete(user)

    followed = User.get_by_id(followed.id)
    follower = User.get_by_id(follower.id)
    user = User.get_by_id(user.id)

    assert user.info.deactivated

    refute User.following?(user, followed)
    refute User.following?(followed, follower)

    # TODO: Remove favorites, repeats, delete activities.

    refute Activity.get_by_id(activity.id)
  end

  test "get_public_key_for_ap_id fetches a user that's not in the db" do
    assert {:ok, _key} = User.get_public_key_for_ap_id("http://mastodon.example.org/users/admin")
  end

  test "insert or update a user from given data" do
    user = insert(:user, %{nickname: "nick@name.de"})
    data = %{ap_id: user.ap_id <> "xxx", name: user.name, nickname: user.nickname}

    assert {:ok, %User{}} = User.insert_or_update_user(data)
  end

  describe "per-user rich-text filtering" do
    test "html_filter_policy returns default policies, when rich-text is enabled" do
      user = insert(:user)

      assert Pleroma.Config.get([:markup, :scrub_policy]) == User.html_filter_policy(user)
    end

    test "html_filter_policy returns TwitterText scrubber when rich-text is disabled" do
      user = insert(:user, %{info: %{no_rich_text: true}})

      assert Pleroma.HTML.Scrubber.TwitterText == User.html_filter_policy(user)
    end
  end

  describe "caching" do
    test "invalidate_cache works" do
      user = insert(:user)
      _user_info = User.get_cached_user_info(user)

      User.invalidate_cache(user)

      {:ok, nil} = Cachex.get(:user_cache, "ap_id:#{user.ap_id}")
      {:ok, nil} = Cachex.get(:user_cache, "nickname:#{user.nickname}")
      {:ok, nil} = Cachex.get(:user_cache, "user_info:#{user.id}")
    end

    test "User.delete() plugs any possible zombie objects" do
      user = insert(:user)

      {:ok, _} = User.delete(user)

      {:ok, cached_user} = Cachex.get(:user_cache, "ap_id:#{user.ap_id}")

      assert cached_user != user

      {:ok, cached_user} = Cachex.get(:user_cache, "nickname:#{user.ap_id}")

      assert cached_user != user
    end
  end

  describe "User.search" do
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

      assert [u4.id, u3.id, u1.id] == Enum.map(User.search("lain@ple"), & &1.id)
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
      results = User.search("http://mastodon.example.org/users/admin", resolve: true)
      result = results |> List.first()

      user = User.get_by_ap_id("http://mastodon.example.org/users/admin")

      assert length(results) == 1
      assert user == result |> Map.put(:search_rank, nil) |> Map.put(:search_type, nil)
    end
  end

  test "auth_active?/1 works correctly" do
    Pleroma.Config.put([:instance, :account_activation_required], true)

    local_user = insert(:user, local: true, info: %{confirmation_pending: true})
    confirmed_user = insert(:user, local: true, info: %{confirmation_pending: false})
    remote_user = insert(:user, local: false)

    refute User.auth_active?(local_user)
    assert User.auth_active?(confirmed_user)
    assert User.auth_active?(remote_user)

    Pleroma.Config.put([:instance, :account_activation_required], false)
  end

  describe "superuser?/1" do
    test "returns false for unprivileged users" do
      user = insert(:user, local: true)

      refute User.superuser?(user)
    end

    test "returns false for remote users" do
      user = insert(:user, local: false)
      remote_admin_user = insert(:user, local: false, info: %{is_admin: true})

      refute User.superuser?(user)
      refute User.superuser?(remote_admin_user)
    end

    test "returns true for local moderators" do
      user = insert(:user, local: true, info: %{is_moderator: true})

      assert User.superuser?(user)
    end

    test "returns true for local admins" do
      user = insert(:user, local: true, info: %{is_admin: true})

      assert User.superuser?(user)
    end
  end

  describe "visible_for?/2" do
    test "returns true when the account is itself" do
      user = insert(:user, local: true)

      assert User.visible_for?(user, user)
    end

    test "returns false when the account is unauthenticated and auth is required" do
      Pleroma.Config.put([:instance, :account_activation_required], true)

      user = insert(:user, local: true, info: %{confirmation_pending: true})
      other_user = insert(:user, local: true)

      refute User.visible_for?(user, other_user)

      Pleroma.Config.put([:instance, :account_activation_required], false)
    end

    test "returns true when the account is unauthenticated and auth is not required" do
      user = insert(:user, local: true, info: %{confirmation_pending: true})
      other_user = insert(:user, local: true)

      assert User.visible_for?(user, other_user)
    end

    test "returns true when the account is unauthenticated and being viewed by a privileged account (auth required)" do
      Pleroma.Config.put([:instance, :account_activation_required], true)

      user = insert(:user, local: true, info: %{confirmation_pending: true})
      other_user = insert(:user, local: true, info: %{is_admin: true})

      assert User.visible_for?(user, other_user)

      Pleroma.Config.put([:instance, :account_activation_required], false)
    end
  end

  describe "parse_bio/2" do
    test "preserves hosts in user links text" do
      remote_user = insert(:user, local: false, nickname: "nick@domain.com")
      user = insert(:user)
      bio = "A.k.a. @nick@domain.com"

      expected_text =
        "A.k.a. <span class='h-card'><a data-user='#{remote_user.id}' class='u-url mention' href='#{
          remote_user.ap_id
        }'>" <> "@<span>nick@domain.com</span></a></span>"

      assert expected_text == User.parse_bio(bio, user)
    end

    test "Adds rel=me on linkbacked urls" do
      user = insert(:user, ap_id: "http://social.example.org/users/lain")

      bio = "http://example.org/rel_me/null"
      expected_text = "<a href=\"#{bio}\">#{bio}</a>"
      assert expected_text == User.parse_bio(bio, user)

      bio = "http://example.org/rel_me/link"
      expected_text = "<a href=\"#{bio}\">#{bio}</a>"
      assert expected_text == User.parse_bio(bio, user)

      bio = "http://example.org/rel_me/anchor"
      expected_text = "<a href=\"#{bio}\">#{bio}</a>"
      assert expected_text == User.parse_bio(bio, user)
    end
  end

  test "bookmarks" do
    user = insert(:user)

    {:ok, activity1} =
      CommonAPI.post(user, %{
        "status" => "heweoo!"
      })

    id1 = activity1.data["object"]["id"]

    {:ok, activity2} =
      CommonAPI.post(user, %{
        "status" => "heweoo!"
      })

    id2 = activity2.data["object"]["id"]

    assert {:ok, user_state1} = User.bookmark(user, id1)
    assert user_state1.bookmarks == [id1]

    assert {:ok, user_state2} = User.unbookmark(user, id1)
    assert user_state2.bookmarks == []

    assert {:ok, user_state3} = User.bookmark(user, id2)
    assert user_state3.bookmarks == [id2]
  end
end
