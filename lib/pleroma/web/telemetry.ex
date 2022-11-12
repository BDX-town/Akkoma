defmodule Pleroma.Web.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()},
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      distribution(
        "phoenix.router_dispatch.stop.duration",
        # event_name: [:pleroma, :repo, :query, :total_time],
        measurement: :duration,
        unit: {:native, :second},
        tags: [:route],
        reporter_options: [
          buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1, 2.5, 5, 10]
        ]
      ),

      # Database Time Metrics
      distribution(
        "pleroma.repo.query.total_time",
        # event_name: [:pleroma, :repo, :query, :total_time],
        measurement: :total_time,
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1, 2.5, 5, 10]
        ]
      ),
      distribution(
        "pleroma.repo.query.queue_time",
        # event_name: [:pleroma, :repo, :query, :total_time],
        measurement: :queue_time,
        unit: {:native, :millisecond},
        reporter_options: [
          buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1, 2.5, 5, 10]
        ]
      ),
      summary("pleroma.repo.query.total_time", unit: {:native, :millisecond}),
      summary("pleroma.repo.query.decode_time", unit: {:native, :millisecond}),
      summary("pleroma.repo.query.query_time", unit: {:native, :millisecond}),
      summary("pleroma.repo.query.queue_time", unit: {:native, :millisecond}),
      summary("pleroma.repo.query.idle_time", unit: {:native, :millisecond}),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),
      distribution(
        "oban.job.stop",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        tags: [:job],
        unit: {:native, :second},
        reporter_options: [
          buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.5, 1, 2.5, 5, 10]
        ]
      )
    ]
  end

  defp periodic_measurements do
    []
  end
end
