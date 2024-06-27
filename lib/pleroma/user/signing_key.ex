defmodule Pleroma.User.SigningKey do
  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset
  alias Pleroma.User
  alias Pleroma.Repo
  alias Pleroma.HTTP

  require Logger

  @primary_key false
  schema "signing_keys" do
    belongs_to(:user, Pleroma.User, type: FlakeId.Ecto.CompatType)
    field :public_key, :string
    field :private_key, :string
    # This is an arbitrary field given by the remote instance
    field :key_id, :string, primary_key: true
    timestamps()
  end

  def key_id_of_local_user(%User{local: true, signing_key: %__MODULE__{key_id: key_id}}),
    do: key_id

  @spec remote_changeset(__MODULE__, map) :: Changeset.t()
  def remote_changeset(%__MODULE__{} = signing_key, attrs) do
    signing_key
    |> cast(attrs, [:public_key, :key_id])
    |> validate_required([:public_key, :key_id])
  end

  @spec key_id_to_user_id(String.t()) :: String.t() | nil
  @doc """
  Given a key ID, return the user ID associated with that key.
  Returns nil if the key ID is not found.
  """
  def key_id_to_user_id(key_id) do
    from(sk in __MODULE__, where: sk.key_id == ^key_id)
    |> select([sk], sk.user_id)
    |> Repo.one()
  end

  @spec key_id_to_ap_id(String.t()) :: String.t() | nil
  @doc """
  Given a key ID, return the AP ID associated with that key.
  Returns nil if the key ID is not found.
  """
  def key_id_to_ap_id(key_id) do
    Logger.debug("Looking up key ID: #{key_id}")

    result =
      from(sk in __MODULE__, where: sk.key_id == ^key_id)
      |> join(:inner, [sk], u in User, on: sk.user_id == u.id)
      |> select([sk, u], %{user: u})
      |> Repo.one()

    case result do
      %{user: %User{ap_id: ap_id}} -> ap_id
      _ -> nil
    end
  end

  @spec generate_rsa_pem() :: {:ok, binary()}
  @doc """
  Generate a new RSA private key and return it as a PEM-encoded string.
  """
  def generate_rsa_pem do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    pem = :public_key.pem_encode([entry]) |> String.trim_trailing()
    {:ok, pem}
  end

  @spec generate_local_keys(String.t()) :: {:ok, Changeset.t()} | {:error, String.t()}
  @doc """
  Generate a new RSA key pair and create a changeset for it
  """
  def generate_local_keys(ap_id) do
    {:ok, private_pem} = generate_rsa_pem()
    {:ok, local_pem} = private_pem_to_public_pem(private_pem)

    %__MODULE__{}
    |> change()
    |> put_change(:public_key, local_pem)
    |> put_change(:private_key, private_pem)
    |> put_change(:key_id, ap_id <> "#main-key")
  end

  @spec private_pem_to_public_pem(binary) :: {:ok, binary()} | {:error, String.t()}
  @doc """
  Given a private key in PEM format, return the corresponding public key in PEM format.
  """
  def private_pem_to_public_pem(private_pem) do
    [private_key_code] = :public_key.pem_decode(private_pem)
    private_key = :public_key.pem_entry_decode(private_key_code)
    {:RSAPrivateKey, _, modulus, exponent, _, _, _, _, _, _, _} = private_key
    public_key = {:RSAPublicKey, modulus, exponent}
    public_key = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
    {:ok, :public_key.pem_encode([public_key])}
  end

  @spec public_key(User.t()) :: {:ok, binary()} | {:error, String.t()}
  @doc """
  Given a user, return the public key for that user in binary format.
  """
  def public_key(%User{signing_key: %__MODULE__{public_key: public_key_pem}}) do
    key =
      public_key_pem
      |> :public_key.pem_decode()
      |> hd()
      |> :public_key.pem_entry_decode()

    {:ok, key}
  end

  def public_key(_), do: {:error, "key not found"}

  def public_key_pem(%User{signing_key: %__MODULE__{public_key: public_key_pem}}),
    do: public_key_pem

  @spec private_key(User.t()) :: {:ok, binary()} | {:error, String.t()}
  @doc """
  Given a user, return the private key for that user in binary format.
  """
  def private_key(%User{signing_key: %__MODULE__{private_key: private_key_pem}}) do
    key =
      private_key_pem
      |> :public_key.pem_decode()
      |> hd()
      |> :public_key.pem_entry_decode()

    {:ok, key}
  end

  @spec fetch_remote_key(String.t()) :: {:ok, __MODULE__} | {:error, String.t()}
  @doc """
  Fetch a remote key by key ID.
  Will send a request to the remote instance to get the key ID.
  This request should, at the very least, return a user ID and a public key object.
  Though bear in mind that some implementations (looking at you, pleroma) may require a signature for this request.
  This has the potential to create an infinite loop if the remote instance requires a signature to fetch the key...
  So if we're rejected, we should probably just give up.
  """
  def fetch_remote_key(key_id) do
    resp = HTTP.Backoff.get(key_id)

    case handle_signature_response(resp) do
      {:ok, ap_id, public_key_pem} ->
        # fetch the user
        user = User.get_or_fetch_by_ap_id(ap_id)
        # store the key
        key = %__MODULE__{
          user_id: user.id,
          public_key: public_key_pem,
          key_id: key_id
        }

        Repo.insert(key)

      _ ->
        {:error, "Could not fetch key"}
    end
  end

  # Take the response from the remote instance and extract the key details
  # will check if the key ID matches the owner of the key, if not, error
  defp extract_key_details(%{"id" => ap_id, "publicKey" => public_key}) do
    if ap_id !== public_key["owner"] do
      {:error, "Key ID does not match owner"}
    else
      %{"publicKeyPem" => public_key_pem} = public_key
      {:ok, ap_id, public_key_pem}
    end
  end

  defp handle_signature_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    case Jason.decode(body) do
      {:ok, %{"id" => _user_id, "publicKey" => _public_key} = body} ->
        extract_key_details(body)

      {:ok, %{"error" => error}} ->
        {:error, error}

      {:error, _} ->
        {:error, "Could not parse key"}
    end
  end

  defp handle_signature_response({:error, e}), do: {:error, e}
  defp handle_signature_response(other), do: {:error, "Could not fetch key: #{inspect(other)}"}
end
