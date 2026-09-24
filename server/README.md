# Nexora mobile server update

This update is based on nexora-code.tar.gz uploaded on 24 September 2026.
It adds a separate mobile API and corrects catalogue handling for long/ongoing series.
It does not add KickAssAnime, AllManga, Animepahe, HIDIVE or Tubi adapters.
No server deployment or live playback verification has been performed.

## Guarded application

Upload nexora_mobile_patch.py to /root, then inspect before applying:

    python3 /root/nexora_mobile_patch.py /root/nexora --dry-run

To install only the ongoing-series corrections, without mobile accounts/API:

    python3 /root/nexora_mobile_patch.py /root/nexora --episodes-only --dry-run
    python3 /root/nexora_mobile_patch.py /root/nexora --episodes-only

Full mobile update:

    python3 /root/nexora_mobile_patch.py /root/nexora

The installer validates every target before writing, rejects unknown changes, and backs up modified files.
Do not bypass a hash mismatch. Supply the current file for a minimal merge instead.

Rebuild the backend using the same Compose overrides already used on the server.
For example, with the existing AniWorld and community setup:

    cd /root/nexora
    docker compose -f docker-compose.yml -f docker-compose.aniworld.yml -f docker-compose.community.yml build backend
    docker compose -f docker-compose.yml -f docker-compose.aniworld.yml -f docker-compose.community.yml run --rm backend python -m pytest tests/test_mobile_release.py -q
    docker compose -f docker-compose.yml -f docker-compose.aniworld.yml -f docker-compose.community.yml up -d backend

For an episodes-only installation the mobile test file is not installed; omit that test invocation.
Full installations add migration 0005_mobile; the existing backend startup runs `alembic upgrade head`.
Back up PostgreSQL before the full deployment using your existing backup procedure.
Check migration startup logs and `/health/ready` before using the app.

Optional docker-compose.mobile.yml forwards the iOS release variables to the backend.
Include it alongside all existing overrides when configuring release announcements.
Never omit an existing providers override if it is already part of your real deployment.
No command registration is needed for this patch.

## Verification and limits

- Original archive test suite: 99 passed, 5 failed.
- Patched suite: 107 passed, same 5 failed. No new failure in that suite.
- 8 new tests cover password verification, anonymous-access rejection, session ownership,
  ongoing-series episode menus/neighbours, targeted canonical pagination and search response shape.
- Existing failures concern previous provider error semantics and outdated public search labels/options.
- No real PostgreSQL migration/auth lifecycle test or iPhone build was possible in this environment.
- Playback for One Piece, every other anime, and all languages is NOT guaranteed by these tests.
- Newly displayed metadata episodes may not yet be available at a playback source.
- Sources with incompatible/ambiguous episode titles can still fail exact mapping.
- Credentials are hashed with scrypt; random mobile tokens are stored only as hashes server-side.
- Mobile account IDs are namespaced, separate from Discord snowflakes. Login does not open Discord.
- The existing media relay still requires the server's existing signing secret; this is not sent to iOS.
- Downloads/offline playback, previews, password recovery and Discord account linking are not implemented.

## Update compatibility

Keep `/api/mobile` API version 1 additive. Do not rename response fields that older IPAs use.
Add migration 0006 for future schema changes; do not edit already deployed migration 0005.
For native changes, build a new IPA with a higher semantic version and build number.
Keep bundle identifier and signing team stable when updating the installed app.
Server-side account data remains independent of IPA versions.

## Follow-up verification
113 local tests pass after updating five stale assertions to the already-requested neutral search UI and current provider-error semantics. Production provider behavior was not changed to satisfy those assertions.
Added explicit absolute-episode mapping for directly matched ongoing series with no final episode count. Real One Piece season 1 HTML yields 61 mappings. This verifies metadata mapping, not media playback.
Native Xcode build and device acceptance still blocked; not a release-ready IPA.

Live catalogue check: all 23 One Piece season pages fetched; 1,172 unique explicit episode mappings parsed (number range 1–1179, seven numbers absent). Episodes 1, 61, 62, 100 and 1000 map to unambiguous season/local-episode pairs. This is not a stream test.
