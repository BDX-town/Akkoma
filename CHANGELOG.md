# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]
### Changed
- **Breaking:** Configuration: A setting to explicitly disable the mailer was added, defaulting to true, if you are using a mailer add `config :pleroma, Pleroma.Emails.Mailer, enabled: true` to your config
- Configuration: OpenGraph and TwitterCard providers enabled by default
- Configuration: Filter.AnonymizeFilename added ability to retain file extension with custom text
- Federation: Return 403 errors when trying to request pages from a user's follower/following collections if they have `hide_followers`/`hide_follows` set
- NodeInfo: Return `skipThreadContainment` in `metadata` for the `skip_thread_containment` option
- Mastodon API: Unsubscribe followers when they unfollow a user
- AdminAPI: Add "godmode" while fetching user statuses (i.e. admin can see private statuses)

### Fixed
- Not being able to pin unlisted posts
- Metadata rendering errors resulting in the entire page being inaccessible
- Federation/MediaProxy not working with instances that have wrong certificate order
- Mastodon API: Handling of search timeouts (`/api/v1/search` and `/api/v2/search`)
- Mastodon API: Embedded relationships not being properly rendered in the Account entity of Status entity
- Mastodon API: Add `account_id`, `type`, `offset`, and `limit` to search API (`/api/v1/search` and `/api/v2/search`)
- Mastodon API, streaming: Fix filtering of notifications based on blocks/mutes/thread mutes
- ActivityPub C2S: follower/following collection pages being inaccessible even when authentifucated if `hide_followers`/ `hide_follows` was set
- Existing user id not being preserved on insert conflict
- Rich Media: Parser failing when no TTL can be found by image TTL setters
- Rich Media: The crawled URL is now spliced into the rich media data.
- ActivityPub S2S: sharedInbox usage has been mostly aligned with the rules in the AP specification.

### Added
- MRF: Support for priming the mediaproxy cache (`Pleroma.Web.ActivityPub.MRF.MediaProxyWarmingPolicy`)
- MRF: Support for excluding specific domains from Transparency.
- MRF: Support for filtering posts based on who they mention (`Pleroma.Web.ActivityPub.MRF.MentionPolicy`)
- MRF (Simple Policy): Support for wildcard domains.
- Support for wildcard domains in user domain blocks setting.
- Configuration: `quarantined_instances` support wildcard domains.
- Configuration: `federation_incoming_replies_max_depth` option
- Mastodon API: Support for the [`tagged` filter](https://github.com/tootsuite/mastodon/pull/9755) in [`GET /api/v1/accounts/:id/statuses`](https://docs.joinmastodon.org/api/rest/accounts/#get-api-v1-accounts-id-statuses)
- Mastodon API, streaming: Add support for passing the token in the `Sec-WebSocket-Protocol` header
- Mastodon API, extension: Ability to reset avatar, profile banner, and background
- Mastodon API: Add support for categories for custom emojis by reusing the group feature. <https://github.com/tootsuite/mastodon/pull/11196>
- Mastodon API: Add support for muting/unmuting notifications
- Mastodon API: Add support for the `blocked_by` attribute in the relationship API (`GET /api/v1/accounts/relationships`). <https://github.com/tootsuite/mastodon/pull/10373>
- Mastodon API: Add `pleroma.deactivated` to the Account entity
- Mastodon API: added `/auth/password` endpoint for password reset with rate limit.
- Mastodon API: /api/v1/accounts/:id/statuses now supports nicknames or user id
- Admin API: Return users' tags when querying reports
- Admin API: Return avatar and display name when querying users
- Admin API: Allow querying user by ID
- Admin API: Added support for `tuples`.
- Added synchronization of following/followers counters for external users
- Configuration: `enabled` option for `Pleroma.Emails.Mailer`, defaulting to `false`.
- Configuration: Pleroma.Plugs.RateLimiter `bucket_name`, `params` options.
- Addressable lists
- Twitter API: added rate limit for `/api/account/password_reset` endpoint.
- ActivityPub: Add an internal service actor for fetching ActivityPub objects.
- ActivityPub: Optional signing of ActivityPub object fetches.
- Admin API: Endpoint for fetching latest user's statuses

### Changed
- Configuration: Filter.AnonymizeFilename added ability to retain file extension with custom text
- Admin API: changed json structure for saving config settings.
- RichMedia: parsers and their order are configured in `rich_media` config.
- RichMedia: add the rich media ttl based on image expiration time.

## [1.0.1] - 2019-07-14
### Security
- OStatus: fix an object spoofing vulnerability.

## [1.0.0] - 2019-06-29
### Security
- Mastodon API: Fix display names not being sanitized
- Rich media: Do not crawl private IP ranges

### Added
- Add a generic settings store for frontends / clients to use.
- Explicit addressing option for posting.
- Optional SSH access mode. (Needs `erlang-ssh` package on some distributions).
- [MongooseIM](https://github.com/esl/MongooseIM) http authentication support.
- LDAP authentication
- External OAuth provider authentication
- Support for building a release using [`mix release`](https://hexdocs.pm/mix/master/Mix.Tasks.Release.html)
- A [job queue](https://git.pleroma.social/pleroma/pleroma_job_queue) for federation, emails, web push, etc.
- [Prometheus](https://prometheus.io/) metrics
- Support for Mastodon's remote interaction
- Mix Tasks: `mix pleroma.database bump_all_conversations`
- Mix Tasks: `mix pleroma.database remove_embedded_objects`
- Mix Tasks: `mix pleroma.database update_users_following_followers_counts`
- Mix Tasks: `mix pleroma.user toggle_confirmed`
- Mix Tasks: `mix pleroma.config migrate_to_db`
- Mix Tasks: `mix pleroma.config migrate_from_db`
- Federation: Support for `Question` and `Answer` objects
- Federation: Support for reports
- Configuration: `poll_limits` option
- Configuration: `pack_extensions` option
- Configuration: `safe_dm_mentions` option
- Configuration: `link_name` option
- Configuration: `fetch_initial_posts` option
- Configuration: `notify_email` option
- Configuration: Media proxy `whitelist` option
- Configuration: `report_uri` option
- Configuration: `limit_to_local_content` option
- Pleroma API: User subscriptions
- Pleroma API: Healthcheck endpoint
- Pleroma API: `/api/v1/pleroma/mascot` per-user frontend mascot configuration endpoints
- Admin API: Endpoints for listing/revoking invite tokens
- Admin API: Endpoints for making users follow/unfollow each other
- Admin API: added filters (role, tags, email, name) for users endpoint
- Admin API: Endpoints for managing reports
- Admin API: Endpoints for deleting and changing the scope of individual reported statuses
- Admin API: Endpoints to view and change config settings.
- AdminFE: initial release with basic user management accessible at /pleroma/admin/
- Mastodon API: Add chat token to `verify_credentials` response
- Mastodon API: Add background image setting to `update_credentials`
- Mastodon API: [Scheduled statuses](https://docs.joinmastodon.org/api/rest/scheduled-statuses/)
- Mastodon API: `/api/v1/notifications/destroy_multiple` (glitch-soc extension)
- Mastodon API: `/api/v1/pleroma/accounts/:id/favourites` (API extension)
- Mastodon API: [Reports](https://docs.joinmastodon.org/api/rest/reports/)
- Mastodon API: `POST /api/v1/accounts` (account creation API)
- Mastodon API: [Polls](https://docs.joinmastodon.org/api/rest/polls/)
- ActivityPub C2S: OAuth endpoints
- Metadata: RelMe provider
- OAuth: added support for refresh tokens
- Emoji packs and emoji pack manager
- Object pruning (`mix pleroma.database prune_objects`)
- OAuth: added job to clean expired access tokens
- MRF: Support for rejecting reports from specific instances (`mrf_simple`)
- MRF: Support for stripping avatars and banner images from specific instances (`mrf_simple`)
- MRF: Support for running subchains.
- Configuration: `skip_thread_containment` option
- Configuration: `rate_limit` option. See `Pleroma.Plugs.RateLimiter` documentation for details.
- MRF: Support for filtering out likely spam messages by rejecting posts from new users that contain links.
- Configuration: `ignore_hosts` option
- Configuration: `ignore_tld` option
- Configuration: default syslog tag "Pleroma" is now lowercased to "pleroma"

### Changed
- **Breaking:** bind to 127.0.0.1 instead of 0.0.0.0 by default
- **Breaking:** Configuration: move from Pleroma.Mailer to Pleroma.Emails.Mailer
- Thread containment / test for complete visibility will be skipped by default.
- Enforcement of OAuth scopes
- Add multiple use/time expiring invite token
- Restyled OAuth pages to fit with Pleroma's default theme
- Link/mention/hashtag detection is now handled by [auto_linker](https://git.pleroma.social/pleroma/auto_linker)
- NodeInfo: Return `safe_dm_mentions` feature flag
- Federation: Expand the audience of delete activities to all recipients of the deleted object
- Federation: Removed `inReplyToStatusId` from objects
- Configuration: Dedupe enabled by default
- Configuration: Default log level in `prod` environment is now set to `warn`
- Configuration: Added `extra_cookie_attrs` for setting non-standard cookie attributes. Defaults to ["SameSite=Lax"] so that remote follows work.
- Timelines: Messages involving people you have blocked will be excluded from the timeline in all cases instead of just repeats.
- Admin API: Move the user related API to `api/pleroma/admin/users`
- Pleroma API: Support for emoji tags in `/api/pleroma/emoji` resulting in a breaking API change
- Mastodon API: Support for `exclude_types`, `limit` and `min_id` in `/api/v1/notifications`
- Mastodon API: Add `languages` and `registrations` to `/api/v1/instance`
- Mastodon API: Provide plaintext versions of cw/content in the Status entity
- Mastodon API: Add `pleroma.conversation_id`, `pleroma.in_reply_to_account_acct` fields to the Status entity
- Mastodon API: Add `pleroma.tags`, `pleroma.relationship{}`, `pleroma.is_moderator`, `pleroma.is_admin`, `pleroma.confirmation_pending`, `pleroma.hide_followers`, `pleroma.hide_follows`, `pleroma.hide_favorites` fields to the User entity
- Mastodon API: Add `pleroma.show_role`, `pleroma.no_rich_text` fields to the Source subentity
- Mastodon API: Add support for updating `no_rich_text`, `hide_followers`, `hide_follows`, `hide_favorites`, `show_role` in `PATCH /api/v1/update_credentials`
- Mastodon API: Add `pleroma.is_seen` to the Notification entity
- Mastodon API: Add `pleroma.local` to the Status entity
- Mastodon API: Add `preview` parameter to `POST /api/v1/statuses`
- Mastodon API: Add `with_muted` parameter to timeline endpoints
- Mastodon API: Actual reblog hiding instead of a dummy
- Mastodon API: Remove attachment limit in the Status entity
- Mastodon API: Added support max_id & since_id for bookmark timeline endpoints.
- Deps: Updated Cowboy to 2.6
- Deps: Updated Ecto to 3.0.7
- Don't ship finmoji by default, they can be installed as an emoji pack
- Hide deactivated users and their statuses
- Posts which are marked sensitive or tagged nsfw no longer have link previews.
- HTTP connection timeout is now set to 10 seconds.
- Respond with a 404 Not implemented JSON error message when requested API is not implemented
- Rich Media: crawl only https URLs.

### Fixed
- Follow requests don't get 'stuck' anymore.
- Added an FTS index on objects. Running `vacuum analyze` and setting a larger `work_mem` is recommended.
- Followers counter not being updated when a follower is blocked
- Deactivated users being able to request an access token
- Limit on request body in rich media/relme parsers being ignored resulting in a possible memory leak
- Proper Twitter Card generation instead of a dummy
- Deletions failing for users with a large number of posts
- NodeInfo: Include admins in `staffAccounts`
- ActivityPub: Crashing when requesting empty local user's outbox
- Federation: Handling of objects without `summary` property
- Federation: Add a language tag to activities as required by ActivityStreams 2.0
- Federation: Do not federate avatar/banner if set to default allowing other servers/clients to use their defaults
- Federation: Cope with missing or explicitly nulled address lists
- Federation: Explicitly ensure activities addressed to `as:Public` become addressed to the followers collection
- Federation: Better cope with actors which do not declare a followers collection and use `as:Public` with these semantics
- Federation: Follow requests from remote users who have been blocked will be automatically rejected if appropriate
- MediaProxy: Parse name from content disposition headers even for non-whitelisted types
- MediaProxy: S3 link encoding
- Rich Media: Reject any data which cannot be explicitly encoded into JSON
- Pleroma API: Importing follows from Mastodon 2.8+
- Twitter API: Exposing default scope, `no_rich_text` of the user to anyone
- Twitter API: Returning the `role` object in user entity despite `show_role = false`
- Mastodon API: `/api/v1/favourites` serving only public activities
- Mastodon API: Reblogs having `in_reply_to_id` - `null` even when they are replies
- Mastodon API: Streaming API broadcasting wrong activity id
- Mastodon API: 500 errors when requesting a card for a private conversation
- Mastodon API: Handling of `reblogs` in `/api/v1/accounts/:id/follow`
- Mastodon API: Correct `reblogged`, `favourited`, and `bookmarked` values in the reblog status JSON
- Mastodon API: Exposing default scope of the user to anyone
- Mastodon API: Make `irreversible` field default to `false` [`POST /api/v1/filters`]
- Mastodon API: Replace missing non-nullable Card attributes with empty strings
- User-Agent is now sent correctly for all HTTP requests.
- MRF: Simple policy now properly delists imported or relayed statuses

## Removed
- Configuration: `config :pleroma, :fe` in favor of the more flexible `config :pleroma, :frontend_configurations`

## [0.9.99999] - 2019-05-31
### Security
- Mastodon API: Fix lists leaking private posts

## [0.9.9999] - 2019-04-05
### Security
- Mastodon API: Fix content warnings skipping HTML sanitization

## [0.9.999] - 2019-03-13
Frontend changes only.
### Added
- Added floating action button for posting status on mobile
### Changed
- Changed user-settings icon to a pencil
### Fixed
- Keyboard shortcuts activating when typing a message
- Gaps when scrolling down on a timeline after showing new

## [0.9.99] - 2019-03-08
### Changed
- Update the frontend to the 0.9.99 tag
### Fixed
- Sign the date header in federation to fix Mastodon federation.

## [0.9.9] - 2019-02-22
This is our first stable release.
