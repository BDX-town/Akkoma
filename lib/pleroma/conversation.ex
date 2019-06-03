# Pleroma: A lightweight social networking server
# Copyright © 2017-2019 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Pleroma.Conversation do
  alias Pleroma.Conversation.Participation
  alias Pleroma.Repo
  alias Pleroma.User
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    # This is the context ap id.
    field(:ap_id, :string)
    has_many(:participations, Participation)
    has_many(:users, through: [:participations, :user])

    timestamps()
  end

  def creation_cng(struct, params) do
    struct
    |> cast(params, [:ap_id])
    |> validate_required([:ap_id])
    |> unique_constraint(:ap_id)
  end

  def create_for_ap_id(ap_id) do
    %__MODULE__{}
    |> creation_cng(%{ap_id: ap_id})
    |> Repo.insert(
      on_conflict: [set: [updated_at: NaiveDateTime.utc_now()]],
      returning: true,
      conflict_target: :ap_id
    )
  end

  def get_for_ap_id(ap_id) do
    Repo.get_by(__MODULE__, ap_id: ap_id)
  end

  @doc """
  This will
  1. Create a conversation if there isn't one already
  2. Create a participation for all the people involved who don't have one already
  3. Bump all relevant participations to 'unread'
  """
  def create_or_bump_for(activity, opts \\ []) do
    with true <- Pleroma.Web.ActivityPub.Visibility.is_direct?(activity),
         "Create" <- activity.data["type"],
         object <- Pleroma.Object.normalize(activity),
         true <- object.data["type"] in ["Note", "Question"],
         ap_id when is_binary(ap_id) and byte_size(ap_id) > 0 <- object.data["context"] do
      {:ok, conversation} = create_for_ap_id(ap_id)

      users = User.get_users_from_set(activity.recipients, false)

      participations =
        Enum.map(users, fn user ->
          {:ok, participation} =
            Participation.create_for_user_and_conversation(user, conversation, opts)

          participation
        end)

      {:ok,
       %{
         conversation
         | participations: participations
       }}
    else
      e -> {:error, e}
    end
  end

  @doc """
  This is only meant to be run by a mix task. It creates conversations/participations for all direct messages in the database.
  """
  def bump_for_all_activities do
    stream =
      Pleroma.Web.ActivityPub.ActivityPub.fetch_direct_messages_query()
      |> Repo.stream()

    Repo.transaction(
      fn ->
        stream
        |> Enum.each(fn a -> create_or_bump_for(a, read: true) end)
      end,
      timeout: :infinity
    )
  end
end
