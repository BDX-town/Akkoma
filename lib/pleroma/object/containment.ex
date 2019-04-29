defmodule Pleroma.Object.Containment do
  @moduledoc """
  # Object Containment

  This module contains some useful functions for containing objects to specific
  origins and determining those origins.  They previously lived in the
  ActivityPub `Transmogrifier` module.

  Object containment is an important step in validating remote objects to prevent
  spoofing, therefore removal of object containment functions is NOT recommended.
  """
  def get_actor(%{"actor" => actor}) when is_binary(actor) do
    actor
  end

  def get_actor(%{"actor" => actor}) when is_list(actor) do
    if is_binary(Enum.at(actor, 0)) do
      Enum.at(actor, 0)
    else
      Enum.find(actor, fn %{"type" => type} -> type in ["Person", "Service", "Application"] end)
      |> Map.get("id")
    end
  end

  def get_actor(%{"actor" => %{"id" => id}}) when is_bitstring(id) do
    id
  end

  def get_actor(%{"actor" => nil, "attributedTo" => actor}) when not is_nil(actor) do
    get_actor(%{"actor" => actor})
  end

  @doc """
  Checks that an imported AP object's actor matches the domain it came from.
  """
  def contain_origin(_id, %{"actor" => nil}), do: :error

  def contain_origin(id, %{"actor" => _actor} = params) do
    id_uri = URI.parse(id)
    actor_uri = URI.parse(get_actor(params))

    if id_uri.host == actor_uri.host do
      :ok
    else
      :error
    end
  end

  def contain_origin_from_id(_id, %{"id" => nil}), do: :error

  def contain_origin_from_id(id, %{"id" => other_id} = _params) do
    id_uri = URI.parse(id)
    other_uri = URI.parse(other_id)

    if id_uri.host == other_uri.host do
      :ok
    else
      :error
    end
  end
end
