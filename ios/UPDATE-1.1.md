# Nexora 1.1 update

- Keep the search query and results while switching tabs and opening anime.
- Fetch missing Continue/History cover images through the existing mobile API.
- Full-screen landscape video and a 16:9 portrait player, with next-episode and autoplay controls.
- Save supported HLS and MP4 media locally through Apple's download sessions. Download buttons are available on episodes and in the player.
- Downloads tab: progress, offline playback, swipe to cancel/delete, local resume position. Downloads are separated by account. Up to two simultaneous downloads; starting requires at least 1 GB free.
- Related titles ranked by shared genres from the existing home catalogue; no claim that every recommended title is playable.
- Pushes to main that modify the app now start the build automatically, using version 1.1.0.

No server migration is required. Existing source availability and adult-content filtering are unchanged. No DRM or subscription bypass is implemented.

Validation: patch whitespace and application checks passed locally. Xcode compilation and iPhone acceptance testing are pending. Check portrait/landscape layout, tab persistence, covers, end-of-episode autoplay, download progress, cancellation, background completion, relaunch, and airplane-mode playback before distributing. Downloads depend on source support and signed URL lifetime. Failed downloads must be removed and restarted online. Offline playback position is local and is not yet synced to the server.
