# Optimizing PostgreSQL performance

Akkoma performance is largely dependent on performance of the underlying database. Better performance can be achieved by adjusting a few settings.

## PGTune

[PgTune](https://pgtune.leopard.in.ua) can be used to get recommended settings. Make sure to set the DB type to "Online transaction processing system" for optimal performance. Also set the number of connections to between 25 and 30. This will allow each connection to have access to more resources while still leaving some room for running maintenance tasks while the instance is still running. 

It is also recommended to not use "Network Storage" option.

If your server runs other services, you may want to take that into account. E.g. if you have 4G ram, but 1G of it is already used for other services, it may be better to tell PGTune you only have 3G.

In the end, PGTune only provides recomended settings, you can always try to finetune further.

## Disable generic query plans

When PostgreSQL receives a query, it decides on a strategy for searching the requested data, this is called a query plan. The query planner has two modes: generic and custom. Generic makes a plan for all queries of the same shape, ignoring the parameters, which is then cached and reused. Custom, on the contrary, generates a unique query plan based on query parameters.

By default PostgreSQL has an algorithm to decide which mode is more efficient for particular query, however this algorithm has been observed to be wrong on some of the queries Akkoma sends, leading to serious performance loss. Therefore, it is recommended to disable generic mode.


Akkoma already avoids generic query plans by default, however the method it uses is not the most efficient because it needs to be compatible with all supported PostgreSQL versions. For PostgreSQL 12 and higher additional performance can be gained by adding the following to Akkoma configuration:
```elixir
config :pleroma, Pleroma.Repo,
  prepare: :named,
  parameters: [
    plan_cache_mode: "force_custom_plan"
  ]
```

A more detailed explaination of the issue can be found at <https://blog.soykaf.com/post/postgresql-elixir-troubles/>.
