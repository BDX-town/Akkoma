defmodule Pleroma.HTTP.Backoff do
  alias Pleroma.HTTP
  require Logger

  @cachex Pleroma.Config.get([:cachex, :provider], Cachex)
  @backoff_cache :http_backoff_cache

  defp next_backoff_timestamp(%{headers: headers}) when is_list(headers) do
    # figure out from the 429 response when we can make the next request
    # mastodon uses the x-ratelimit-reset header, so we will use that!
    # other servers may not, so we'll default to 5 minutes from now if we can't find it
    default_5_minute_backoff =
      DateTime.utc_now()
      |> Timex.shift(seconds: 5 * 60)

    case Enum.find_value(headers, fn {"x-ratelimit-reset", value} -> value end) do
      nil ->
        Logger.error("Rate limited, but couldn't find timestamp! Using default 5 minute backoff until #{default_5_minute_backoff}")
        default_5_minute_backoff

      value ->
        with {:ok, stamp, _} <- DateTime.from_iso8601(value) do
          Logger.error("Rate limited until #{stamp}")
          stamp
        else
          _ ->
            Logger.error("Rate limited, but couldn't parse timestamp! Using default 5 minute backoff until #{default_5_minute_backoff}")
            default_5_minute_backoff
        end
    end
  end

  defp next_backoff_timestamp(_), do: DateTime.utc_now() |> Timex.shift(seconds: 5 * 60)

  def get(url, headers \\ [], options \\ []) do
    # this acts as a single throughput for all GET requests
    # we will check if the host is in the cache, and if it is, we will automatically fail the request
    # this ensures that we don't hammer the server with requests, and instead wait for the backoff to expire
    # this is a very simple implementation, and can be improved upon!
    %{host: host} = URI.parse(url)

    case @cachex.get(@backoff_cache, host) do
      {:ok, nil} ->
        case HTTP.get(url, headers, options) do
          {:ok, env} ->
            case env.status do
              429 ->
                Logger.error("Rate limited on #{host}! Backing off...")
                timestamp = next_backoff_timestamp(env)
                ttl = Timex.diff(timestamp, DateTime.utc_now(), :seconds)
                # we will cache the host for 5 minutes
                @cachex.put(@backoff_cache, host, true, ttl: ttl)
                {:error, :ratelimit}

              _ ->
                {:ok, env}
            end

          {:error, env} ->
            {:error, env}
        end

      _ ->
        {:error, :ratelimit}
    end
  end
end
