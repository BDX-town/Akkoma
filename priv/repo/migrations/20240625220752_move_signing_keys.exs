defmodule Pleroma.Repo.Migrations.MoveSigningKeys do
  use Ecto.Migration
  alias Pleroma.User
  alias Pleroma.Repo
  import Ecto.Query

  def up do
    # we do not handle remote users here!
    # because we want to store a key id -> user id mapping, and we don't
    # currently store key ids for remote users...
    query =
      from(u in User)
      |> where(local: true)

    Repo.stream(query, timeout: :infinity)
    |> Enum.each(fn
      %User{id: user_id, keys: private_key, local: true} ->
        # we can precompute the public key here...
        # we do use it on every user view which makes it a bit of a dos attack vector
        # so we should probably cache it
        {:ok, public_key} = User.SigningKey.private_pem_to_public_pem(private_key)

        key = %User.SigningKey{
          user_id: user_id,
          public_key: public_key,
          private_key: private_key
        }

        {:ok, _} = Repo.insert(key)
    end)
  end

  # no need to rollback
  def down, do: :ok
end
