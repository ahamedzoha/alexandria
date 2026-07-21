# Alexandria

A native macOS client for [audiobookshelf](https://www.audiobookshelf.org/), built with SwiftUI.

**Phase 1 (this MVP):** log in to your server, browse a library of covers, open a book, stream playback with a now-playing bar (play/pause, ±15s/30s skip, scrubber, speed 0.75×–3×).

Planned next: offline downloads, progress sync back to the server, menu-bar mini-player, media keys, bookmarks, sleep timer.

## Requirements

- macOS 14 or later
- Xcode 16 or later (install from the Mac App Store)
- A running audiobookshelf server you can reach

## Run it

1. Open `Alexandria.xcodeproj` in Xcode (double-click it).
2. Top toolbar: scheme = **Alexandria**, destination = **My Mac**.
3. Press **⌘R** (or the ▶ button).
4. In the app: enter your server URL (e.g. `http://192.168.1.50:13378`), username, password → **Connect**.

If Xcode shows a signing error: select the **Alexandria** target → **Signing & Capabilities** →
set **Team** to your Apple ID (free) or leave signing to run locally.

## Project layout

```
Alexandria/
  AlexandriaApp.swift      app entry point
  Models.swift             Codable types for the ABS API
  APIClient.swift          async REST calls (login, libraries, items, cover, play)
  AppState.swift           observable app/session state
  PlayerEngine.swift       AVPlayer wrapper (playback, seek, speed)
  Views/                   SwiftUI screens
Info.plist                 allows plain-http LAN servers (ATS)
```

New `.swift` files dropped into `Alexandria/` are picked up automatically (Xcode 16
synchronized folders) — no project fiddling needed.

## Known MVP limitations

- Plays the **first audio track** of an item only (multi-track queueing is next).
- Auth token is stored in `UserDefaults` — move to Keychain before shipping.
- No offline/download support yet.
