# General Performance and Optimisation Notes

# Oban Web

The built-in Oban Web dashboard has a seemingly constant'ish overhead
irrelevant to large instances but potentially
noticeable for small instances on low power systems.
Thus if the latter applies to your case, you might want to disable it;
see [the cheatsheet](../cheatsheet.md#oban-web).

# Relays

Subscribing to relays exposes your instance to a high volume flood of incoming activities.
This does not just incur the cost of processing those activities themselves, but typically
each activity may trigger additional work, like fetching ancestors and child posts to
complete the thread, refreshing user profiles, etc.  
Furthermore the larger the count of activities and objects in your database the costlier
all database operations on these (highly important) tables get.

Carefully consider whether this is worth the cost
and if you experience performance issues unsubscribe from relays.

Regularly pruning old remote posts and orphaned activities is also especially important
when following relays or just having unfollowed relays for performance reasons.

# Pruning old remote data

Over time your instance accumulates more and more remote data, mainly in form of posts and activities.
Chances are you and your local users do not actually care for the vast majority of those.
Consider regularly *(frequency highly dependent on your individual setup)* pruning such old and irrelevant remote data; see
[the corresponding `mix` tasks](../../../administration/CLI_tasks/database#prune-old-remote-posts-from-the-database).

# Database Maintenance

Akkoma’s performance is highly dependent on and often bottle-necked by the database.
Taking good care of it pays off!
See the dedicated [PostgreSQL page](../postgresql.md).

# HTTP Request Cache

If your instance is frequently getting _many_ `GET` requests from external 
actors *(i.e. everyone except logged-in local users)* an additional
*(Akkoma already has some caching built-in and so might your reverse proxy)*
caching layer as described in the [Varnish Cache guide](varnish_cache.md)
might help alleviate the impact.

If this condition does **not** hold though,
setting up such a cache likely only worsens latency and wastes memory.
