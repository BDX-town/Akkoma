defmodule Pleroma.HTTP.BackoffTest do
  @backoff_cache :http_backoff_cache
  use Pleroma.DataCase, async: false
  alias Pleroma.HTTP.Backoff

  describe "get/3" do
    test "should return {:ok, env} when not rate limited" do
      Tesla.Mock.mock_global(fn
        %Tesla.Env{url: "https://akkoma.dev/api/v1/instance"} ->
          {:ok, %Tesla.Env{status: 200, body: "ok"}}
      end)
      assert {:ok, env} = Backoff.get("https://akkoma.dev/api/v1/instance")
      assert env.status == 200
    end

    test "should return {:error, env} when rate limited" do
      # Shove a value into the cache to simulate a rate limit
      Cachex.put(@backoff_cache, "akkoma.dev", true)
      assert {:error, env} = Backoff.get("https://akkoma.dev/api/v1/instance")
      assert env.status == 429
    end

    test "should insert a value into the cache when rate limited" do
      Tesla.Mock.mock_global(fn
        %Tesla.Env{url: "https://ratelimited.dev/api/v1/instance"} ->
          {:ok, %Tesla.Env{status: 429, body: "Rate limited"}}
      end)

      assert {:error, env} = Backoff.get("https://ratelimited.dev/api/v1/instance")
      assert env.status == 429
      assert {:ok, true} = Cachex.get(@backoff_cache, "ratelimited.dev")
  end
  end
end
