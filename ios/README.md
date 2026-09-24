# Nexora iOS

Native SwiftUI client for https://nexoradc.duckdns.org. iOS 17 or newer.
This source project has not yet been built with Xcode or tested on an iPhone.

## Build and future updates

Put the contents of this directory at the root of a GitHub repository, including `.github`.
Open Actions → Build Nexora IPA → Run workflow. Choose a semantic version, such as 1.0.0.
The macOS job builds the native app and uploads Nexora-unsigned.ipa only if the build succeeds.
Sign that IPA using your own authorized signing/sideloading setup before installation.
A Mac with Xcode and XcodeGen can also run `bash scripts/build.sh`.

For future features, change the Swift files and run the workflow with a new version.
Keep `org.nexora.anime` as the bundle ID and use the same signing identity/team to update in place.
Do not uninstall the old app to update. Server-side account data survives reinstall after logging in.
Keychain persistence depends on signing and OS behavior; a new login may be required.
No remote executable code or unsigned automatic app replacement is used.

The API is additive under `/api/mobile`. Keep compatibility with older releases when adding endpoints.
Configure `NEXORA_IOS_LATEST_VERSION`, `NEXORA_IOS_MINIMUM_VERSION`, `NEXORA_IOS_UPDATE_URL`
and `NEXORA_IOS_RELEASE_NOTES` in the backend container environment to publish release information.
The app offers an update notice. Minimum-version enforcement is not enabled in this build.
New catalogue data and calendar updates do not require a new IPA.

## Implemented source flows

Username/password registration, Keychain sessions, login/logout/account deletion; Home, airing calendar,
Coming soon, debounced catalogue search, seasons and paged episodes, native AVPlayer, periodic progress,
continue watching, favorites/history, image cache, support Discord, preferences, update notice.
The player uses the existing backend resolver and relay; provider failures remain visible.

## Known limits — not a completed acceptance test

- No IPA has been built or installed in this environment. The macOS workflow must pass first.
- Server patch must be installed, migration applied and HTTPS endpoints verified before use.
- Provider playback, correct episode identity and English audio are not universally verified.
- Download/offline playback and trailer previews are unavailable: backend currently has no explicitly
  authorized downloadable assets or preview contract. Offline mode displays an honest empty state.
- Calendar is a broadcast schedule (first 50 upcoming entries), not a promise of source availability.
- Mobile accounts are separate from Discord accounts. Existing Discord history is not auto-linked.
- No password recovery/email verification yet. Choose and retain a strong unique password.
- Favorites is the save-for-later list. Continue Watching is generated from playback progress.
- The app does not have per-episode source/language availability pickers yet; language preference
  is configured in Settings, and unavailable language errors are surfaced.
- No local offline progress queue yet; progress writes require a working server connection.

Support button: https://discord.gg/BU5xTMu9QE
