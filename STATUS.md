# Nexora iOS / ongoing-series work — 24 September 2026

On-disk base: supplied nexora-code.tar.gz. Preserve existing server features and minimal guarded diffs.
Latest requests: stable iOS updates; Support Discord https://discord.gg/BU5xTMu9QE in Settings.

Implemented source: mobile API/accounts, calendar, SwiftUI client core flows, icon asset, unsigned IPA build workflow,
version endpoint/banner and support link. Server patch includes general ongoing/long-series corrections.

NOT COMPLETE: no Xcode build/IPA artifact, no iPhone acceptance test, no PostgreSQL lifecycle test, no live provider verification.
GitHub list_repositories returned an empty list; need accessible intended repository to run macOS Actions.
Never call the source archive an IPA or claim all providers work.

Additional requested provider integrations remain unverified and are not bundled into this mobile update.
Downloads require an explicit backend authorization contract/assets; do not enable ripping or fake download buttons.
Future work: real Xcode compile/device tests, database lifecycle tests, authenticated episode-option picker,
offline authorized-asset handling/sync, capability-gated previews and password recovery.

Validation: baseline 99 pass / 5 pre-existing fail. Patched 107 pass / same 5 fail. 8 new tests pass.
Files in server/payload are authoritative generated changes. Installer produced by build-installer.py.
Do not run prepare.py again without preserving subsequent mobile changes.

## Follow-up verification
113 local tests pass after updating five stale assertions to the already-requested neutral search UI and current provider-error semantics. Production provider behavior was not changed to satisfy those assertions.
Added explicit absolute-episode mapping for directly matched ongoing series with no final episode count. Real One Piece season 1 HTML yields 61 mappings. This verifies metadata mapping, not media playback.
Native Xcode build and device acceptance still blocked; not a release-ready IPA.

Live catalogue check: all 23 One Piece season pages fetched; 1,172 unique explicit episode mappings parsed (number range 1–1179, seven numbers absent). Episodes 1, 61, 62, 100 and 1000 map to unambiguous season/local-episode pairs. This is not a stream test.
