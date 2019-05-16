# Configuration

This file describe the configuration, it is recommended to edit the relevant *.secret.exs file instead of the others founds in the ``config`` directory.
If you run Pleroma with ``MIX_ENV=prod`` the file is ``prod.secret.exs``, otherwise it is ``dev.secret.exs``.

## Pleroma.Upload
* `uploader`: Select which `Pleroma.Uploaders` to use
* `filters`: List of `Pleroma.Upload.Filter` to use.
* `link_name`: When enabled Pleroma will add a `name` parameter to the url of the upload, for example `https://instance.tld/media/corndog.png?name=corndog.png`. This is needed to provide the correct filename in Content-Disposition headers when using filters like `Pleroma.Upload.Filter.Dedupe`
* `base_url`: The base URL to access a user-uploaded file. Useful when you want to proxy the media files via another host.
* `proxy_remote`: If you\'re using a remote uploader, Pleroma will proxy media requests instead of redirecting to it.
* `proxy_opts`: Proxy options, see `Pleroma.ReverseProxy` documentation.

Note: `strip_exif` has been replaced by `Pleroma.Upload.Filter.Mogrify`.

## Pleroma.Uploaders.Local
* `uploads`: Which directory to store the user-uploads in, relative to pleroma’s working directory

## Pleroma.Upload.Filter.Mogrify

* `args`: List of actions for the `mogrify` command like `"strip"` or `["strip", "auto-orient", {"impode", "1"}]`.

## Pleroma.Upload.Filter.Dedupe

No specific configuration.

## Pleroma.Upload.Filter.AnonymizeFilename

This filter replaces the filename (not the path) of an upload. For complete obfuscation, add
`Pleroma.Upload.Filter.Dedupe` before AnonymizeFilename.

* `text`: Text to replace filenames in links. If empty, `{random}.extension` will be used.

## Pleroma.Emails.Mailer
* `adapter`: one of the mail adapters listed in [Swoosh readme](https://github.com/swoosh/swoosh#adapters), or `Swoosh.Adapters.Local` for in-memory mailbox.
* `api_key` / `password` and / or other adapter-specific settings, per the above documentation.

An example for Sendgrid adapter:

```elixir
config :pleroma, Pleroma.Emails.Mailer,
  adapter: Swoosh.Adapters.Sendgrid,
  api_key: "YOUR_API_KEY"
```

An example for SMTP adapter:

```elixir
config :pleroma, Pleroma.Emails.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: "smtp.gmail.com",
  username: "YOUR_USERNAME@gmail.com",
  password: "YOUR_SMTP_PASSWORD",
  port: 465,
  ssl: true,
  tls: :always,
  auth: :always
```

## :uri_schemes
* `valid_schemes`: List of the scheme part that is considered valid to be an URL

## :instance
* `name`: The instance’s name
* `email`: Email used to reach an Administrator/Moderator of the instance
* `notify_email`: Email used for notifications.
* `description`: The instance’s description, can be seen in nodeinfo and ``/api/v1/instance``
* `limit`: Posts character limit (CW/Subject included in the counter)
* `remote_limit`: Hard character limit beyond which remote posts will be dropped.
* `upload_limit`: File size limit of uploads (except for avatar, background, banner)
* `avatar_upload_limit`: File size limit of user’s profile avatars
* `background_upload_limit`: File size limit of user’s profile backgrounds
* `banner_upload_limit`: File size limit of user’s profile banners
* `registrations_open`: Enable registrations for anyone, invitations can be enabled when false.
* `invites_enabled`: Enable user invitations for admins (depends on `registrations_open: false`).
* `account_activation_required`: Require users to confirm their emails before signing in.
* `federating`: Enable federation with other instances
* `federation_reachability_timeout_days`: Timeout (in days) of each external federation target being unreachable prior to pausing federating to it.
* `allow_relay`: Enable Pleroma’s Relay, which makes it possible to follow a whole instance
* `rewrite_policy`: Message Rewrite Policy, either one or a list. Here are the ones available by default:
  * `Pleroma.Web.ActivityPub.MRF.NoOpPolicy`: Doesn’t modify activities (default)
  * `Pleroma.Web.ActivityPub.MRF.DropPolicy`: Drops all activities. It generally doesn’t makes sense to use in production
  * `Pleroma.Web.ActivityPub.MRF.SimplePolicy`: Restrict the visibility of activities from certains instances (See ``:mrf_simple`` section)
  * `Pleroma.Web.ActivityPub.MRF.RejectNonPublic`: Drops posts with non-public visibility settings (See ``:mrf_rejectnonpublic`` section)
  * `Pleroma.Web.ActivityPub.MRF.EnsureRePrepended`: Rewrites posts to ensure that replies to posts with subjects do not have an identical subject and instead begin with re:.
* `public`: Makes the client API in authentificated mode-only except for user-profiles. Useful for disabling the Local Timeline and The Whole Known Network.
* `quarantined_instances`: List of ActivityPub instances where private(DMs, followers-only) activities will not be send.
* `managed_config`: Whenether the config for pleroma-fe is configured in this config or in ``static/config.json``
* `allowed_post_formats`: MIME-type list of formats allowed to be posted (transformed into HTML)
* `mrf_transparency`: Make the content of your Message Rewrite Facility settings public (via nodeinfo).
* `scope_copy`: Copy the scope (private/unlisted/public) in replies to posts by default.
* `subject_line_behavior`: Allows changing the default behaviour of subject lines in replies. Valid values:
  * "email": Copy and preprend re:, as in email.
  * "masto": Copy verbatim, as in Mastodon.
  * "noop": Don't copy the subject.
* `always_show_subject_input`: When set to false, auto-hide the subject field when it's empty.
* `extended_nickname_format`: Set to `true` to use extended local nicknames format (allows underscores/dashes). This will break federation with
    older software for theses nicknames.
* `max_pinned_statuses`: The maximum number of pinned statuses. `0` will disable the feature.
* `autofollowed_nicknames`: Set to nicknames of (local) users that every new user should automatically follow.
* `no_attachment_links`: Set to true to disable automatically adding attachment link text to statuses
* `welcome_message`: A message that will be send to a newly registered users as a direct message.
* `welcome_user_nickname`: The nickname of the local user that sends the welcome message.
* `max_report_comment_size`: The maximum size of the report comment (Default: `1000`)
* `safe_dm_mentions`: If set to true, only mentions at the beginning of a post will be used to address people in direct messages. This is to prevent accidental mentioning of people when talking about them (e.g. "@friend hey i really don't like @enemy"). (Default: `false`)
* `healthcheck`: if set to true, system data will be shown on ``/api/pleroma/healthcheck``.

## :app_account_creation
REST API for creating an account settings
* `enabled`: Enable/disable registration
* `max_requests`: Number of requests allowed for creating accounts
* `interval`: Interval for restricting requests for one ip (seconds)

## :logger
* `backends`: `:console` is used to send logs to stdout, `{ExSyslogger, :ex_syslogger}` to log to syslog, and `Quack.Logger` to log to Slack

An example to enable ONLY ExSyslogger (f/ex in ``prod.secret.exs``) with info and debug suppressed:
```elixir
config :logger,
  backends: [{ExSyslogger, :ex_syslogger}]

config :logger, :ex_syslogger,
  level: :warn
```

Another example, keeping console output and adding the pid to syslog output:
```elixir
config :logger,
  backends: [:console, {ExSyslogger, :ex_syslogger}]

config :logger, :ex_syslogger,
  level: :warn,
  option: [:pid, :ndelay]
```

See: [logger’s documentation](https://hexdocs.pm/logger/Logger.html) and [ex_syslogger’s documentation](https://hexdocs.pm/ex_syslogger/)

An example of logging info to local syslog, but warn to a Slack channel:
```elixir
config :logger,
  backends: [ {ExSyslogger, :ex_syslogger}, Quack.Logger ],
  level: :info

config :logger, :ex_syslogger,
  level: :info,
  ident: "pleroma",
  format: "$metadata[$level] $message"

config :quack,
  level: :warn,
  meta: [:all],
  webhook_url: "https://hooks.slack.com/services/YOUR-API-KEY-HERE"
```

See the [Quack Github](https://github.com/azohra/quack) for more details

## :frontend_configurations

This can be used to configure a keyword list that keeps the configuration data for any kind of frontend. By default, settings for `pleroma_fe` and `masto_fe` are configured.

Frontends can access these settings at `/api/pleroma/frontend_configurations`

To add your own configuration for PleromaFE, use it like this:

```elixir
config :pleroma, :frontend_configurations,
  pleroma_fe: %{
    theme: "pleroma-dark",
    # ... see /priv/static/static/config.json for the available keys.
},
  masto_fe: %{
    showInstanceSpecificPanel: true
  }
```

These settings **need to be complete**, they will override the defaults.

NOTE: for versions < 1.0, you need to set [`:fe`](#fe) to false, as shown a few lines below.

## :fe
__THIS IS DEPRECATED__

If you are using this method, please change it to the [`frontend_configurations`](#frontend_configurations) method.
Please **set this option to false** in your config like this:

```elixir
config :pleroma, :fe, false
```

This section is used to configure Pleroma-FE, unless ``:managed_config`` in ``:instance`` is set to false.

* `theme`: Which theme to use, they are defined in ``styles.json``
* `logo`: URL of the logo, defaults to Pleroma’s logo
* `logo_mask`: Whether to use only the logo's shape as a mask (true) or as a regular image (false)
* `logo_margin`: What margin to use around the logo
* `background`: URL of the background, unless viewing a user profile with a background that is set
* `redirect_root_no_login`: relative URL which indicates where to redirect when a user isn’t logged in.
* `redirect_root_login`: relative URL which indicates where to redirect when a user is logged in.
* `show_instance_panel`: Whenether to show the instance’s specific panel.
* `scope_options_enabled`: Enable setting an notice visibility and subject/CW when posting
* `formatting_options_enabled`: Enable setting a formatting different than plain-text (ie. HTML, Markdown) when posting, relates to ``:instance, allowed_post_formats``
* `collapse_message_with_subjects`: When a message has a subject(aka Content Warning), collapse it by default
* `hide_post_stats`: Hide notices statistics(repeats, favorites, …)
* `hide_user_stats`: Hide profile statistics(posts, posts per day, followers, followings, …)

## :mrf_simple
* `media_removal`: List of instances to remove medias from
* `media_nsfw`: List of instances to put medias as NSFW(sensitive) from
* `federated_timeline_removal`: List of instances to remove from Federated (aka The Whole Known Network) Timeline
* `reject`: List of instances to reject any activities from
* `accept`: List of instances to accept any activities from

## :mrf_rejectnonpublic
* `allow_followersonly`: whether to allow followers-only posts
* `allow_direct`: whether to allow direct messages

## :mrf_hellthread
* `delist_threshold`: Number of mentioned users after which the message gets delisted (the message can still be seen, but it will not show up in public timelines and mentioned users won't get notifications about it). Set to 0 to disable.
* `reject_threshold`: Number of mentioned users after which the messaged gets rejected. Set to 0 to disable.

## :mrf_keyword
* `reject`: A list of patterns which result in message being rejected, each pattern can be a string or a [regular expression](https://hexdocs.pm/elixir/Regex.html)
* `federated_timeline_removal`: A list of patterns which result in message being removed from federated timelines (a.k.a unlisted), each pattern can be a string or a [regular expression](https://hexdocs.pm/elixir/Regex.html)
* `replace`: A list of tuples containing `{pattern, replacement}`, `pattern` can be a string or a [regular expression](https://hexdocs.pm/elixir/Regex.html)

## :media_proxy
* `enabled`: Enables proxying of remote media to the instance’s proxy
* `base_url`: The base URL to access a user-uploaded file. Useful when you want to proxy the media files via another host/CDN fronts.
* `proxy_opts`: All options defined in `Pleroma.ReverseProxy` documentation, defaults to `[max_body_length: (25*1_048_576)]`.
* `whitelist`: List of domains to bypass the mediaproxy

## :gopher
* `enabled`: Enables the gopher interface
* `ip`: IP address to bind to
* `port`: Port to bind to
* `dstport`: Port advertised in urls (optional, defaults to `port`)

## Pleroma.Web.Endpoint
`Phoenix` endpoint configuration, all configuration options can be viewed [here](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#module-dynamic-configuration), only common options are listed here
* `http` - a list containing http protocol configuration, all configuration options can be viewed [here](https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html#module-options), only common options are listed here
  - `ip` - a tuple consisting of 4 integers
  - `port`
* `url` - a list containing the configuration for generating urls, accepts
  - `host` - the host without the scheme and a post (e.g `example.com`, not `https://example.com:2020`)
  - `scheme` - e.g `http`, `https`
  - `port`
  - `path`
* `extra_cookie_attrs` - a list of `Key=Value` strings to be added as non-standard cookie attributes. Defaults to `["SameSite=Lax"]`. See the [SameSite article](https://www.owasp.org/index.php/SameSite) on OWASP for more info.



**Important note**: if you modify anything inside these lists, default `config.exs` values will be overwritten, which may result in breakage, to make sure this does not happen please copy the default value for the list from `config.exs` and modify/add only what you need

Example:
```elixir
config :pleroma, Pleroma.Web.Endpoint,
  url: [host: "example.com", port: 2020, scheme: "https"],
  http: [
    # start copied from config.exs
    dispatch: [
      {:_,
       [
         {"/api/v1/streaming", Pleroma.Web.MastodonAPI.WebsocketHandler, []},
         {"/websocket", Phoenix.Endpoint.CowboyWebSocket,
          {Phoenix.Transports.WebSocket,
           {Pleroma.Web.Endpoint, Pleroma.Web.UserSocket, websocket_config}}},
         {:_, Phoenix.Endpoint.Cowboy2Handler, {Pleroma.Web.Endpoint, []}}
       ]}
    # end copied from config.exs
    ],
    port: 8080,
    ip: {127, 0, 0, 1}
  ]
```

This will make Pleroma listen on `127.0.0.1` port `8080` and generate urls starting with `https://example.com:2020`

## :activitypub
* ``accept_blocks``: Whether to accept incoming block activities from other instances
* ``unfollow_blocked``: Whether blocks result in people getting unfollowed
* ``outgoing_blocks``: Whether to federate blocks to other instances
* ``deny_follow_blocked``: Whether to disallow following an account that has blocked the user in question

## :http_security
* ``enabled``: Whether the managed content security policy is enabled
* ``sts``: Whether to additionally send a `Strict-Transport-Security` header
* ``sts_max_age``: The maximum age for the `Strict-Transport-Security` header if sent
* ``ct_max_age``: The maximum age for the `Expect-CT` header if sent
* ``referrer_policy``: The referrer policy to use, either `"same-origin"` or `"no-referrer"`.

## :mrf_user_allowlist

The keys in this section are the domain names that the policy should apply to.
Each key should be assigned a list of users that should be allowed through by
their ActivityPub ID.

An example:

```elixir
config :pleroma, :mrf_user_allowlist,
  "example.org": ["https://example.org/users/admin"]
```

## :web_push_encryption, :vapid_details

Web Push Notifications configuration. You can use the mix task `mix web_push.gen.keypair` to generate it.

* ``subject``: a mailto link for the administrative contact. It’s best if this email is not a personal email address, but rather a group email so that if a person leaves an organization, is unavailable for an extended period, or otherwise can’t respond, someone else on the list can.
* ``public_key``: VAPID public key
* ``private_key``: VAPID private key

## Pleroma.Captcha
* `enabled`: Whether the captcha should be shown on registration
* `method`: The method/service to use for captcha
* `seconds_valid`: The time in seconds for which the captcha is valid

### Pleroma.Captcha.Kocaptcha
Kocaptcha is a very simple captcha service with a single API endpoint,
the source code is here: https://github.com/koto-bank/kocaptcha. The default endpoint
`https://captcha.kotobank.ch` is hosted by the developer.

* `endpoint`: the kocaptcha endpoint to use

## :admin_token

Allows to set a token that can be used to authenticate with the admin api without using an actual user by giving it as the 'admin_token' parameter. Example:

```elixir
config :pleroma, :admin_token, "somerandomtoken"
```

You can then do

```sh
curl "http://localhost:4000/api/pleroma/admin/invite_token?admin_token=somerandomtoken"
```

## :pleroma_job_queue

[Pleroma Job Queue](https://git.pleroma.social/pleroma/pleroma_job_queue) configuration: a list of queues with maximum concurrent jobs.

Pleroma has the following queues:

* `federator_outgoing` - Outgoing federation
* `federator_incoming` - Incoming federation
* `mailer` - Email sender, see [`Pleroma.Emails.Mailer`](#pleroma-emails-mailer)
* `transmogrifier` - Transmogrifier
* `web_push` - Web push notifications
* `scheduled_activities` - Scheduled activities, see [`Pleroma.ScheduledActivities`](#pleromascheduledactivity)

Example:

```elixir
config :pleroma_job_queue, :queues,
  federator_incoming: 50,
  federator_outgoing: 50
```

This config contains two queues: `federator_incoming` and `federator_outgoing`. Both have the `max_jobs` set to `50`.

## Pleroma.Web.Federator.RetryQueue

* `enabled`: If set to `true`, failed federation jobs will be retried
* `max_jobs`: The maximum amount of parallel federation jobs running at the same time.
* `initial_timeout`: The initial timeout in seconds
* `max_retries`: The maximum number of times a federation job is retried

## Pleroma.Web.Metadata
* `providers`: a list of metadata providers to enable. Providers available:
  * Pleroma.Web.Metadata.Providers.OpenGraph
  * Pleroma.Web.Metadata.Providers.TwitterCard
  * Pleroma.Web.Metadata.Providers.RelMe - add links from user bio with rel=me into the `<header>` as `<link rel=me>`
* `unfurl_nsfw`: If set to `true` nsfw attachments will be shown in previews

## :rich_media
* `enabled`: if enabled the instance will parse metadata from attached links to generate link previews

## :fetch_initial_posts
* `enabled`: if enabled, when a new user is federated with, fetch some of their latest posts
* `pages`: the amount of pages to fetch

## :hackney_pools

Advanced. Tweaks Hackney (http client) connections pools.

There's three pools used:

* `:federation` for the federation jobs.
  You may want this pool max_connections to be at least equal to the number of federator jobs + retry queue jobs.
* `:media` for rich media, media proxy
* `:upload` for uploaded media (if using a remote uploader and `proxy_remote: true`)

For each pool, the options are:

* `max_connections` - how much connections a pool can hold
* `timeout` - retention duration for connections

## :auto_linker

Configuration for the `auto_linker` library:

* `class: "auto-linker"` - specify the class to be added to the generated link. false to clear
* `rel: "noopener noreferrer"` - override the rel attribute. false to clear
* `new_window: true` - set to false to remove `target='_blank'` attribute
* `scheme: false` - Set to true to link urls with schema `http://google.com`
* `truncate: false` - Set to a number to truncate urls longer then the number. Truncated urls will end in `..`
* `strip_prefix: true` - Strip the scheme prefix
* `extra: false` - link urls with rarely used schemes (magnet, ipfs, irc, etc.)

Example:

```elixir
config :auto_linker,
  opts: [
    scheme: true,
    extra: true,
    class: false,
    strip_prefix: false,
    new_window: false,
    rel: false
  ]
```

## Pleroma.ScheduledActivity

* `daily_user_limit`: the number of scheduled activities a user is allowed to create in a single day (Default: `25`)
* `total_user_limit`: the number of scheduled activities a user is allowed to create in total (Default: `300`)
* `enabled`: whether scheduled activities are sent to the job queue to be executed

## Pleroma.Web.Auth.Authenticator

* `Pleroma.Web.Auth.PleromaAuthenticator`: default database authenticator
* `Pleroma.Web.Auth.LDAPAuthenticator`: LDAP authentication

## :ldap

Use LDAP for user authentication.  When a user logs in to the Pleroma
instance, the name and password will be verified by trying to authenticate
(bind) to an LDAP server.  If a user exists in the LDAP directory but there
is no account with the same name yet on the Pleroma instance then a new
Pleroma account will be created with the same name as the LDAP user name.

* `enabled`: enables LDAP authentication
* `host`: LDAP server hostname
* `port`: LDAP port, e.g. 389 or 636
* `ssl`: true to use SSL, usually implies the port 636
* `sslopts`: additional SSL options
* `tls`: true to start TLS, usually implies the port 389
* `tlsopts`: additional TLS options
* `base`: LDAP base, e.g. "dc=example,dc=com"
* `uid`: LDAP attribute name to authenticate the user, e.g. when "cn", the filter will be "cn=username,base"

## BBS / SSH access

To enable simple command line interface accessible over ssh, add a setting like this to your configuration file:

```exs
app_dir = File.cwd!
priv_dir = Path.join([app_dir, "priv/ssh_keys"])

config :esshd,
  enabled: true,
  priv_dir: priv_dir,
  handler: "Pleroma.BBS.Handler",
  port: 10_022,
  password_authenticator: "Pleroma.BBS.Authenticator"
```

Feel free to adjust the priv_dir and port number. Then you will have to create the key for the keys (in the example `priv/ssh_keys`) and create the host keys with `ssh-keygen -N "" -b 2048 -t rsa -f ssh_host_rsa_key`. After restarting, you should be able to connect to your Pleroma instance with `ssh username@server -p $PORT`

## :auth

* `Pleroma.Web.Auth.PleromaAuthenticator`: default database authenticator
* `Pleroma.Web.Auth.LDAPAuthenticator`: LDAP authentication

Authentication / authorization settings.

* `auth_template`: authentication form template. By default it's `show.html` which corresponds to `lib/pleroma/web/templates/o_auth/o_auth/show.html.eex`.
* `oauth_consumer_template`: OAuth consumer mode authentication form template. By default it's `consumer.html` which corresponds to `lib/pleroma/web/templates/o_auth/o_auth/consumer.html.eex`.
* `oauth_consumer_strategies`: the list of enabled OAuth consumer strategies; by default it's set by OAUTH_CONSUMER_STRATEGIES environment variable.

## OAuth consumer mode

OAuth consumer mode allows sign in / sign up via external OAuth providers (e.g. Twitter, Facebook, Google, Microsoft, etc.).
Implementation is based on Ueberauth; see the list of [available strategies](https://github.com/ueberauth/ueberauth/wiki/List-of-Strategies).

Note: each strategy is shipped as a separate dependency; in order to get the strategies, run `OAUTH_CONSUMER_STRATEGIES="..." mix deps.get`,
e.g. `OAUTH_CONSUMER_STRATEGIES="twitter facebook google microsoft" mix deps.get`.
The server should also be started with `OAUTH_CONSUMER_STRATEGIES="..." mix phx.server` in case you enable any strategies.

Note: each strategy requires separate setup (on external provider side and Pleroma side). Below are the guidelines on setting up most popular strategies.

Note: make sure that `"SameSite=Lax"` is set in `extra_cookie_attrs` when you have this feature enabled. OAuth consumer mode will not work with `"SameSite=Strict"`

* For Twitter, [register an app](https://developer.twitter.com/en/apps), configure callback URL to https://<your_host>/oauth/twitter/callback

* For Facebook, [register an app](https://developers.facebook.com/apps), configure callback URL to https://<your_host>/oauth/facebook/callback, enable Facebook Login service at https://developers.facebook.com/apps/<app_id>/fb-login/settings/

* For Google, [register an app](https://console.developers.google.com), configure callback URL to https://<your_host>/oauth/google/callback

* For Microsoft, [register an app](https://portal.azure.com), configure callback URL to https://<your_host>/oauth/microsoft/callback

Once the app is configured on external OAuth provider side, add app's credentials and strategy-specific settings (if any — e.g. see Microsoft below) to `config/prod.secret.exs`,
per strategy's documentation (e.g. [ueberauth_twitter](https://github.com/ueberauth/ueberauth_twitter)). Example config basing on environment variables:

```elixir
# Twitter
config :ueberauth, Ueberauth.Strategy.Twitter.OAuth,
  consumer_key: System.get_env("TWITTER_CONSUMER_KEY"),
  consumer_secret: System.get_env("TWITTER_CONSUMER_SECRET")

# Facebook
config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
  client_id: System.get_env("FACEBOOK_APP_ID"),
  client_secret: System.get_env("FACEBOOK_APP_SECRET"),
  redirect_uri: System.get_env("FACEBOOK_REDIRECT_URI")

# Google
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
  redirect_uri: System.get_env("GOOGLE_REDIRECT_URI")

# Microsoft
config :ueberauth, Ueberauth.Strategy.Microsoft.OAuth,
  client_id: System.get_env("MICROSOFT_CLIENT_ID"),
  client_secret: System.get_env("MICROSOFT_CLIENT_SECRET")

config :ueberauth, Ueberauth,
  providers: [
    microsoft: {Ueberauth.Strategy.Microsoft, [callback_params: []]}
  ]
```

## OAuth 2.0 provider - :oauth2

Configure OAuth 2 provider capabilities:

* `token_expires_in` - The lifetime in seconds of the access token.
* `issue_new_refresh_token` - Keeps old refresh token or generate new refresh token when to obtain an access token.

## :emoji
* `shortcode_globs`: Location of custom emoji files. `*` can be used as a wildcard. Example `["/emoji/custom/**/*.png"]`
* `groups`: Emojis are ordered in groups (tags). This is an array of key-value pairs where the key is the groupname and the value the location or array of locations. `*` can be used as a wildcard. Example `[Custom: ["/emoji/*.png", "/emoji/custom/*.png"]]`
* `default_manifest`: Location of the JSON-manifest. This manifest contains information about the emoji-packs you can download. Currently only one manifest can be added (no arrays).
