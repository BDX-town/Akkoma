defmodule Pleroma.Search.SearchBackend do
  @doc """
  Add the object associated with the activity to the search index.

  The whole activity is passed, to allow filtering on things such as scope.
  """
  @callback add_to_index(activity :: Pleroma.Activity.t()) :: {:ok, any()} | {:error, any()}

  @doc """
  Remove the object from the index.

  Just the object, as opposed to the whole activity, is passed, since the object
  is what contains the actual content and there is no need for fitlering when removing
  from index.
  """
  @callback remove_from_index(object :: Pleroma.Object.t()) :: {:ok, any()} | {:error, any()}

  @optional_callbacks add_to_index: 1, remove_from_index: 1
end
