defmodule Pleroma.Web.ActivityPub.MRF.DirectMessageDisabledPolicy do
  @behaviour Pleroma.Web.ActivityPub.MRF.Policy

  alias Pleroma.User
  alias Pleroma.Web.ActivityPub.Visibility

  @moduledoc """
  Removes entries from the "To" field from direct messages if the user has requested to not
  allow direct messages
  """

  @impl true
  def filter(
        %{
          "type" => "Create",
          "actor" => actor
        } = activity
      ) do
    with true <- Visibility.is_direct?(%{data: activity}),
         recipients <- Map.get(activity, "to"),
         sender <- User.get_cached_by_ap_id(actor) do
      new_to =
        Enum.filter(recipients, fn recv ->
          should_filter?(sender, recv)
        end)

      {:ok,
       activity
       |> Map.put("to", new_to)
       |> maybe_replace_object_to(new_to)}
    else
      _ ->
        {:ok, activity}
    end
  end

  @impl true
  def filter(object), do: {:ok, object}

  @impl true
  def describe, do: {:ok, %{}}

  defp should_filter?(sender, receiver_ap_id) do
    with %User{local: true} = receiver <- User.get_cached_by_ap_id(receiver_ap_id) do
      User.accepts_direct_messages?(receiver, sender)
    else
      _ -> false
    end
  end

  defp maybe_replace_object_to(%{"object" => %{"to" => _}} = activity, to) do
    Kernel.put_in(activity, ["object", "to"], to)
  end

  defp maybe_replace_object_to(other, _), do: other
end
