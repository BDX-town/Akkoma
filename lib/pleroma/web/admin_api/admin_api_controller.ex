# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Web.AdminAPI.AdminAPIController do
  use Pleroma.Web, :controller
  alias Pleroma.Activity
  alias Pleroma.ModerationLog
  alias Pleroma.User
  alias Pleroma.UserInviteToken
  alias Pleroma.Web.ActivityPub.ActivityPub
  alias Pleroma.Web.ActivityPub.Relay
  alias Pleroma.Web.AdminAPI.AccountView
  alias Pleroma.Web.AdminAPI.Config
  alias Pleroma.Web.AdminAPI.ConfigView
  alias Pleroma.Web.AdminAPI.ModerationLogView
  alias Pleroma.Web.AdminAPI.Report
  alias Pleroma.Web.AdminAPI.ReportView
  alias Pleroma.Web.AdminAPI.Search
  alias Pleroma.Web.CommonAPI
  alias Pleroma.Web.MastodonAPI.StatusView

  import Pleroma.Web.ControllerHelper, only: [json_response: 3]

  require Logger

  @users_page_size 50

  action_fallback(:errors)

  def user_delete(%{assigns: %{user: admin}} = conn, %{"nickname" => nickname}) do
    user = User.get_cached_by_nickname(nickname)
    User.delete(user)

    ModerationLog.insert_log(%{
      actor: admin,
      subject: user,
      action: "delete"
    })

    conn
    |> json(nickname)
  end

  def user_follow(%{assigns: %{user: admin}} = conn, %{
        "follower" => follower_nick,
        "followed" => followed_nick
      }) do
    with %User{} = follower <- User.get_cached_by_nickname(follower_nick),
         %User{} = followed <- User.get_cached_by_nickname(followed_nick) do
      User.follow(follower, followed)

      ModerationLog.insert_log(%{
        actor: admin,
        followed: followed,
        follower: follower,
        action: "follow"
      })
    end

    conn
    |> json("ok")
  end

  def user_unfollow(%{assigns: %{user: admin}} = conn, %{
        "follower" => follower_nick,
        "followed" => followed_nick
      }) do
    with %User{} = follower <- User.get_cached_by_nickname(follower_nick),
         %User{} = followed <- User.get_cached_by_nickname(followed_nick) do
      User.unfollow(follower, followed)

      ModerationLog.insert_log(%{
        actor: admin,
        followed: followed,
        follower: follower,
        action: "unfollow"
      })
    end

    conn
    |> json("ok")
  end

  def users_create(%{assigns: %{user: admin}} = conn, %{"users" => users}) do
    changesets =
      Enum.map(users, fn %{"nickname" => nickname, "email" => email, "password" => password} ->
        user_data = %{
          nickname: nickname,
          name: nickname,
          email: email,
          password: password,
          password_confirmation: password,
          bio: "."
        }

        User.register_changeset(%User{}, user_data, need_confirmation: false)
      end)
      |> Enum.reduce(Ecto.Multi.new(), fn changeset, multi ->
        Ecto.Multi.insert(multi, Ecto.UUID.generate(), changeset)
      end)

    case Pleroma.Repo.transaction(changesets) do
      {:ok, users} ->
        res =
          users
          |> Map.values()
          |> Enum.map(fn user ->
            {:ok, user} = User.post_register_action(user)

            user
          end)
          |> Enum.map(&AccountView.render("created.json", %{user: &1}))

        ModerationLog.insert_log(%{
          actor: admin,
          subjects: Map.values(users),
          action: "create"
        })

        conn
        |> json(res)

      {:error, id, changeset, _} ->
        res =
          Enum.map(changesets.operations, fn
            {current_id, {:changeset, _current_changeset, _}} when current_id == id ->
              AccountView.render("create-error.json", %{changeset: changeset})

            {_, {:changeset, current_changeset, _}} ->
              AccountView.render("create-error.json", %{changeset: current_changeset})
          end)

        conn
        |> put_status(:conflict)
        |> json(res)
    end
  end

  def user_show(conn, %{"nickname" => nickname}) do
    with %User{} = user <- User.get_cached_by_nickname_or_id(nickname) do
      conn
      |> put_view(AccountView)
      |> render("show.json", %{user: user})
    else
      _ -> {:error, :not_found}
    end
  end

  def list_user_statuses(conn, %{"nickname" => nickname} = params) do
    godmode = params["godmode"] == "true" || params["godmode"] == true

    with %User{} = user <- User.get_cached_by_nickname_or_id(nickname) do
      {_, page_size} = page_params(params)

      activities =
        ActivityPub.fetch_user_activities(user, nil, %{
          "limit" => page_size,
          "godmode" => godmode
        })

      conn
      |> put_view(StatusView)
      |> render("index.json", %{activities: activities, as: :activity})
    else
      _ -> {:error, :not_found}
    end
  end

  def user_toggle_activation(%{assigns: %{user: admin}} = conn, %{"nickname" => nickname}) do
    user = User.get_cached_by_nickname(nickname)

    {:ok, updated_user} = User.deactivate(user, !user.info.deactivated)

    action = if user.info.deactivated, do: "activate", else: "deactivate"

    ModerationLog.insert_log(%{
      actor: admin,
      subject: user,
      action: action
    })

    conn
    |> put_view(AccountView)
    |> render("show.json", %{user: updated_user})
  end

  def tag_users(%{assigns: %{user: admin}} = conn, %{"nicknames" => nicknames, "tags" => tags}) do
    with {:ok, _} <- User.tag(nicknames, tags) do
      ModerationLog.insert_log(%{
        actor: admin,
        nicknames: nicknames,
        tags: tags,
        action: "tag"
      })

      json_response(conn, :no_content, "")
    end
  end

  def untag_users(%{assigns: %{user: admin}} = conn, %{"nicknames" => nicknames, "tags" => tags}) do
    with {:ok, _} <- User.untag(nicknames, tags) do
      ModerationLog.insert_log(%{
        actor: admin,
        nicknames: nicknames,
        tags: tags,
        action: "untag"
      })

      json_response(conn, :no_content, "")
    end
  end

  def list_users(conn, params) do
    {page, page_size} = page_params(params)
    filters = maybe_parse_filters(params["filters"])

    search_params = %{
      query: params["query"],
      page: page,
      page_size: page_size,
      tags: params["tags"],
      name: params["name"],
      email: params["email"]
    }

    with {:ok, users, count} <- Search.user(Map.merge(search_params, filters)),
         do:
           conn
           |> json(
             AccountView.render("index.json",
               users: users,
               count: count,
               page_size: page_size
             )
           )
  end

  @filters ~w(local external active deactivated is_admin is_moderator)

  @spec maybe_parse_filters(String.t()) :: %{required(String.t()) => true} | %{}
  defp maybe_parse_filters(filters) when is_nil(filters) or filters == "", do: %{}

  defp maybe_parse_filters(filters) do
    filters
    |> String.split(",")
    |> Enum.filter(&Enum.member?(@filters, &1))
    |> Enum.map(&String.to_atom(&1))
    |> Enum.into(%{}, &{&1, true})
  end

  def right_add(%{assigns: %{user: admin}} = conn, %{
        "permission_group" => permission_group,
        "nickname" => nickname
      })
      when permission_group in ["moderator", "admin"] do
    user = User.get_cached_by_nickname(nickname)

    info =
      %{}
      |> Map.put("is_" <> permission_group, true)

    info_cng = User.Info.admin_api_update(user.info, info)

    cng =
      user
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:info, info_cng)

    ModerationLog.insert_log(%{
      action: "grant",
      actor: admin,
      subject: user,
      permission: permission_group
    })

    {:ok, _user} = User.update_and_set_cache(cng)

    json(conn, info)
  end

  def right_add(conn, _) do
    render_error(conn, :not_found, "No such permission_group")
  end

  def right_get(conn, %{"nickname" => nickname}) do
    user = User.get_cached_by_nickname(nickname)

    conn
    |> json(%{
      is_moderator: user.info.is_moderator,
      is_admin: user.info.is_admin
    })
  end

  def right_delete(
        %{assigns: %{user: %User{:nickname => admin_nickname} = admin}} = conn,
        %{
          "permission_group" => permission_group,
          "nickname" => nickname
        }
      )
      when permission_group in ["moderator", "admin"] do
    if admin_nickname == nickname do
      render_error(conn, :forbidden, "You can't revoke your own admin status.")
    else
      user = User.get_cached_by_nickname(nickname)

      info =
        %{}
        |> Map.put("is_" <> permission_group, false)

      info_cng = User.Info.admin_api_update(user.info, info)

      cng =
        Ecto.Changeset.change(user)
        |> Ecto.Changeset.put_embed(:info, info_cng)

      {:ok, _user} = User.update_and_set_cache(cng)

      ModerationLog.insert_log(%{
        action: "revoke",
        actor: admin,
        subject: user,
        permission: permission_group
      })

      json(conn, info)
    end
  end

  def right_delete(conn, _) do
    render_error(conn, :not_found, "No such permission_group")
  end

  def set_activation_status(%{assigns: %{user: admin}} = conn, %{
        "nickname" => nickname,
        "status" => status
      }) do
    with {:ok, status} <- Ecto.Type.cast(:boolean, status),
         %User{} = user <- User.get_cached_by_nickname(nickname),
         {:ok, _} <- User.deactivate(user, !status) do
      action = if(user.info.deactivated, do: "activate", else: "deactivate")

      ModerationLog.insert_log(%{
        actor: admin,
        subject: user,
        action: action
      })

      json_response(conn, :no_content, "")
    end
  end

  def relay_follow(%{assigns: %{user: admin}} = conn, %{"relay_url" => target}) do
    with {:ok, _message} <- Relay.follow(target) do
      ModerationLog.insert_log(%{
        action: "relay_follow",
        actor: admin,
        target: target
      })

      json(conn, target)
    else
      _ ->
        conn
        |> put_status(500)
        |> json(target)
    end
  end

  def relay_unfollow(%{assigns: %{user: admin}} = conn, %{"relay_url" => target}) do
    with {:ok, _message} <- Relay.unfollow(target) do
      ModerationLog.insert_log(%{
        action: "relay_unfollow",
        actor: admin,
        target: target
      })

      json(conn, target)
    else
      _ ->
        conn
        |> put_status(500)
        |> json(target)
    end
  end

  @doc "Sends registration invite via email"
  def email_invite(%{assigns: %{user: user}} = conn, %{"email" => email} = params) do
    with true <-
           Pleroma.Config.get([:instance, :invites_enabled]) &&
             !Pleroma.Config.get([:instance, :registrations_open]),
         {:ok, invite_token} <- UserInviteToken.create_invite(),
         email <-
           Pleroma.Emails.UserEmail.user_invitation_email(
             user,
             invite_token,
             email,
             params["name"]
           ),
         {:ok, _} <- Pleroma.Emails.Mailer.deliver(email) do
      json_response(conn, :no_content, "")
    end
  end

  @doc "Create an account registration invite token"
  def create_invite_token(conn, params) do
    opts = %{}

    opts =
      if params["max_use"],
        do: Map.put(opts, :max_use, params["max_use"]),
        else: opts

    opts =
      if params["expires_at"],
        do: Map.put(opts, :expires_at, params["expires_at"]),
        else: opts

    {:ok, invite} = UserInviteToken.create_invite(opts)

    json(conn, AccountView.render("invite.json", %{invite: invite}))
  end

  @doc "Get list of created invites"
  def invites(conn, _params) do
    invites = UserInviteToken.list_invites()

    conn
    |> put_view(AccountView)
    |> render("invites.json", %{invites: invites})
  end

  @doc "Revokes invite by token"
  def revoke_invite(conn, %{"token" => token}) do
    with {:ok, invite} <- UserInviteToken.find_by_token(token),
         {:ok, updated_invite} = UserInviteToken.update_invite(invite, %{used: true}) do
      conn
      |> put_view(AccountView)
      |> render("invite.json", %{invite: updated_invite})
    else
      nil -> {:error, :not_found}
    end
  end

  @doc "Get a password reset token (base64 string) for given nickname"
  def get_password_reset(conn, %{"nickname" => nickname}) do
    (%User{local: true} = user) = User.get_cached_by_nickname(nickname)
    {:ok, token} = Pleroma.PasswordResetToken.create_token(user)

    conn
    |> json(token.token)
  end

  @doc "Force password reset for a given user"
  def force_password_reset(conn, %{"nickname" => nickname}) do
    (%User{local: true} = user) = User.get_cached_by_nickname(nickname)

    User.force_password_reset_async(user)

    json_response(conn, :no_content, "")
  end

  def list_reports(conn, params) do
    params =
      params
      |> Map.put("type", "Flag")
      |> Map.put("skip_preload", true)
      |> Map.put("total", true)

    reports = ActivityPub.fetch_activities([], params)

    conn
    |> put_view(ReportView)
    |> render("index.json", %{reports: reports})
  end

  def report_show(conn, %{"id" => id}) do
    with %Activity{} = report <- Activity.get_by_id(id) do
      conn
      |> put_view(ReportView)
      |> render("show.json", Report.extract_report_info(report))
    else
      _ -> {:error, :not_found}
    end
  end

  def report_update_state(%{assigns: %{user: admin}} = conn, %{"id" => id, "state" => state}) do
    with {:ok, report} <- CommonAPI.update_report_state(id, state) do
      ModerationLog.insert_log(%{
        action: "report_update",
        actor: admin,
        subject: report
      })

      conn
      |> put_view(ReportView)
      |> render("show.json", Report.extract_report_info(report))
    end
  end

  def report_respond(%{assigns: %{user: user}} = conn, %{"id" => id} = params) do
    with false <- is_nil(params["status"]),
         %Activity{} <- Activity.get_by_id(id) do
      params =
        params
        |> Map.put("in_reply_to_status_id", id)
        |> Map.put("visibility", "direct")

      {:ok, activity} = CommonAPI.post(user, params)

      ModerationLog.insert_log(%{
        action: "report_response",
        actor: user,
        subject: activity,
        text: params["status"]
      })

      conn
      |> put_view(StatusView)
      |> render("status.json", %{activity: activity})
    else
      true ->
        {:param_cast, nil}

      nil ->
        {:error, :not_found}
    end
  end

  def status_update(%{assigns: %{user: admin}} = conn, %{"id" => id} = params) do
    with {:ok, activity} <- CommonAPI.update_activity_scope(id, params) do
      {:ok, sensitive} = Ecto.Type.cast(:boolean, params["sensitive"])

      ModerationLog.insert_log(%{
        action: "status_update",
        actor: admin,
        subject: activity,
        sensitive: sensitive,
        visibility: params["visibility"]
      })

      conn
      |> put_view(StatusView)
      |> render("status.json", %{activity: activity})
    end
  end

  def status_delete(%{assigns: %{user: user}} = conn, %{"id" => id}) do
    with {:ok, %Activity{}} <- CommonAPI.delete(id, user) do
      ModerationLog.insert_log(%{
        action: "status_delete",
        actor: user,
        subject_id: id
      })

      json(conn, %{})
    end
  end

  def list_log(conn, params) do
    {page, page_size} = page_params(params)

    log = ModerationLog.get_all(page, page_size)

    conn
    |> put_view(ModerationLogView)
    |> render("index.json", %{log: log})
  end

  def migrate_to_db(conn, _params) do
    Mix.Tasks.Pleroma.Config.run(["migrate_to_db"])
    json(conn, %{})
  end

  def migrate_from_db(conn, _params) do
    Mix.Tasks.Pleroma.Config.run(["migrate_from_db", Pleroma.Config.get(:env), "true"])
    json(conn, %{})
  end

  def config_show(conn, _params) do
    configs = Pleroma.Repo.all(Config)

    conn
    |> put_view(ConfigView)
    |> render("index.json", %{configs: configs})
  end

  def config_update(conn, %{"configs" => configs}) do
    updated =
      if Pleroma.Config.get([:instance, :dynamic_configuration]) do
        updated =
          Enum.map(configs, fn
            %{"group" => group, "key" => key, "delete" => "true"} = params ->
              {:ok, config} = Config.delete(%{group: group, key: key, subkeys: params["subkeys"]})
              config

            %{"group" => group, "key" => key, "value" => value} ->
              {:ok, config} = Config.update_or_create(%{group: group, key: key, value: value})
              config
          end)
          |> Enum.reject(&is_nil(&1))

        Pleroma.Config.TransferTask.load_and_update_env()
        Mix.Tasks.Pleroma.Config.run(["migrate_from_db", Pleroma.Config.get(:env), "false"])
        updated
      else
        []
      end

    conn
    |> put_view(ConfigView)
    |> render("index.json", %{configs: updated})
  end

  def reload_emoji(conn, _params) do
    Pleroma.Emoji.reload()

    conn |> json("ok")
  end

  def errors(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(dgettext("errors", "Not found"))
  end

  def errors(conn, {:error, reason}) do
    conn
    |> put_status(:bad_request)
    |> json(reason)
  end

  def errors(conn, {:param_cast, _}) do
    conn
    |> put_status(:bad_request)
    |> json(dgettext("errors", "Invalid parameters"))
  end

  def errors(conn, _) do
    conn
    |> put_status(:internal_server_error)
    |> json(dgettext("errors", "Something went wrong"))
  end

  defp page_params(params) do
    {get_page(params["page"]), get_page_size(params["page_size"])}
  end

  defp get_page(page_string) when is_nil(page_string), do: 1

  defp get_page(page_string) do
    case Integer.parse(page_string) do
      {page, _} -> page
      :error -> 1
    end
  end

  defp get_page_size(page_size_string) when is_nil(page_size_string), do: @users_page_size

  defp get_page_size(page_size_string) do
    case Integer.parse(page_size_string) do
      {page_size, _} -> page_size
      :error -> @users_page_size
    end
  end
end
