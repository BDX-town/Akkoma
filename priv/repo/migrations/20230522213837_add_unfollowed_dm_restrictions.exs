defmodule Pleroma.Repo.Migrations.AddUnfollowedDmRestrictions do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:accepts_direct_messages_from_followed, :boolean, default: true)
      add(:accepts_direct_messages_from_not_followed, :boolean, default: true)
    end
  end
end
