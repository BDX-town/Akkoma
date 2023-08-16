defmodule Pleroma.Repo.Migrations.RemoveUserApEnabled do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove(:ap_enabled, :boolean, default: false, null: false)
    end
  end
end
