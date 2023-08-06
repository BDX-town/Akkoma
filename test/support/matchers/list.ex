defmodule Pleroma.Test.Matchers.List do
  import ExUnit.Assertions

  def assert_unordered_list_equal(list_a, list_b) when is_list(list_a) and is_list(list_b) do
    assert Enum.sort(list_a) == Enum.sort(list_b)
  end
end
