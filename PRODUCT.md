# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Apple's design language, rendered as a native SwiftUI **macOS** app for macOS 26 (Tahoe) and later, Liquid Glass included. (`ios` is the closest platform value the design tooling accepts.) Mac conventions win wherever they differ from iPhone ones: pointer and keyboard first, menus and toolbars, sheets and inspectors, no touch-target sizing. Not a web view, not Catalyst.

## Users

People who run their own [audiobookshelf](https://www.audiobookshelf.org/) server and listen on a Mac: the author first, then other audiobookshelf users who find the app on GitHub. They already have a library (audiobooks, podcasts or both) on a server they control, often on their home network behind a reverse proxy, and they listen at the desk: while working, in long sessions, alongside other apps.

## Product Purpose

Alexandria plays an audiobookshelf library on the Mac: browse it, pick up where you left off, and listen, with progress kept in step with the server so every other client agrees. Success is that a self-hoster never reaches for the web player or a phone while at the Mac.

## Positioning

The Mac-native audiobookshelf client. Other clients are iOS-first or wrap the web UI; Alexandria is built as a first-class Mac app: system controls and chrome, media keys and Now Playing, a menu-bar player, keyboard paths, and books and podcasts on equal footing in one Home.

## Operating Context

- Talks to the user's own server over the audiobookshelf REST API (`/api/...`), with a token stored in the app's sandbox container. Several servers can be added and switched.
- Server URLs are often LAN addresses or local hostnames behind a reverse proxy, so macOS Local Network privacy and per-app firewalls can block a freshly installed build.
- Listening is reported back as playback sessions and progress, so the server's stats and other clients (phones, the web UI) see Alexandria's listening.
- Downloads play offline; progress made offline queues and syncs on reconnect.
- Updates arrive in-app through Sparkle from GitHub Releases.

## Capabilities and Constraints

- **Home:** greeting, a seven-day listening diary (covers of what was played each day, across Alexandria and other clients), a library mosaic of finished / in-progress / unread books, one Continue hero, and shelves for Continue Listening (books and episodes from every library), Latest Episodes, Discover, Listen Again and Recently Added.
- **Library:** grid and table, sort and filter; Browse by Authors, Series (in reading order), Narrators; a Stats page.
- **Podcasts:** episode lists in the style of Apple Podcasts, per-show episode order, played state, downloads per episode.
- **Playback:** gapless multi-track books with chapters, skip, speed, a sleep timer shaped by chapters and episodes, Up Next (automatic from the show or series, editable, saved per server), media keys, Now Playing, a menu-bar mini player, Space to play/pause.
- **Sound:** per book or per series, Original / Voice Boost (louder, steadier, clearer) / Restore (plus ML voice isolation against tape hiss), with hold-to-compare and fine-tune sliders. Built from Apple's own audio units in the playback tap; nothing leaves the Mac.
- **Now Playing inspector:** details, chapters, and opt-in ratings and reviews from Audible and Open Library (spoilers collapsed).
- **Search:** global dropdown with keyboard navigation, ⌘F from anywhere.
- **Durable constraints:**
  - Free and open source; no pricing or paid tiers.
  - Distributed outside the App Store: GitHub Releases plus Sparkle, ad-hoc signed, not notarized.
  - No tracking or analytics. The app talks only to the user's server, plus Audible and Open Library for ratings when that setting is on.
  - Targets the latest macOS only (deployment target 26.0); no back-deploying.
- **Terminology:** "server" (an audiobookshelf instance), "library" (a server library, books or podcasts), "book", "show" and "episode", "Up Next", "Continue Listening".

## Brand Commitments

- Name: **Alexandria**. Icon: `docs/icon.png` (`press-kit/AppIcon-1024.png`).
- The app must read as a genuinely native Mac app, the calibre of Apple's Music, Books and Podcasts, never a templated web or AI-generated look. Native controls and system chrome first; warmth is welcome but restrained and on-brand, never decorative. (The user's standing direction.)
- Copy is plain, sentence case and specific: it names the book or show, says what happened and what to do next, and avoids exclamation marks and filler.

## Evidence on Hand

- Screenshots: `docs/screenshots/` (README), `press-kit/` (press kit, logo, descriptions).
- Release history and notes: GitHub Releases (`v0.5.x`).
- No user counts, testimonials, reviews or press coverage exist. Future work must not invent any.

## Product Principles

1. **Native before novel.** Prefer the system control, layout or behavior a Mac user already knows; invent only where the system has no answer.
2. **The server is the truth.** Progress, finished state and listening go to the server so every client agrees; local state (downloads, offline progress, the listening log) covers what the server can't, and never silently overrides it.
3. **Books and podcasts are equals.** Every surface that resumes, queues or counts listening handles both, in the words that fit each ("book", "show", "episode").
4. **Nothing leaves the Mac unasked.** No analytics; third-party lookups are opt-in and say what they send.
5. **Failures are visible and recoverable.** A failed play, download or sign-in says what happened and offers the next step, never a dead click.

## Accessibility & Inclusion

Honors Reduce Motion everywhere motion appears, labels controls and composite views for VoiceOver, keeps keyboard paths (Full Keyboard Access, Return/Delete in lists, Esc closes sheets), and uses `.secondary` rather than `.tertiary` for text that carries information.
