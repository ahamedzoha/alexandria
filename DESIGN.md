---
name: Alexandria
description: A native macOS client for your audiobookshelf library.
colors:
  lapis: "#3C67D9"
  glyph-shade: "#0000008C"
  glyph-ink: "#FFFFFF"
typography:
  display:
    fontFamily: "SF Pro (system)"
    fontSize: "34pt"
    fontWeight: 700
  headline:
    fontFamily: "SF Pro (system)"
    fontSize: "17pt (.title2)"
    fontWeight: 700
  title:
    fontFamily: "SF Pro (system)"
    fontSize: "11pt (.subheadline)"
    fontWeight: 600
  body:
    fontFamily: "SF Pro (system)"
    fontSize: "13pt (.body)"
    fontWeight: 400
  label:
    fontFamily: "SF Pro (system)"
    fontSize: "11pt (.subheadline)"
    fontWeight: 500
    letterSpacing: "uppercase, system tracking"
  meta:
    fontFamily: "SF Pro (system)"
    fontSize: "10pt (.caption)"
    fontWeight: 400
rounded:
  mark: "2pt"
  tile: "4pt"
  row: "6pt"
  control: "8pt"
  cover: "10pt"
  group: "12pt"
  card: "16pt"
  pill: "999pt"
spacing:
  xs: "4pt"
  s: "8pt"
  m: "14pt"
  l: "20pt"
  xl: "28pt"
components:
  button-primary:
    backgroundColor: "{colors.lapis}"
    textColor: "{colors.glyph-ink}"
    rounded: "{rounded.row}"
  cover-card:
    rounded: "{rounded.cover}"
    typography: "{typography.title}"
  mosaic-tile:
    rounded: "{rounded.tile}"
    size: "22pt"
  episode-play-pill:
    rounded: "{rounded.pill}"
    typography: "{typography.meta}"
  cover-play-glyph:
    backgroundColor: "{colors.glyph-shade}"
    textColor: "{colors.glyph-ink}"
    rounded: "{rounded.pill}"
    size: "44pt"
  content-card:
    rounded: "{rounded.card}"
    padding: "{spacing.m}"
---

# Design System: Alexandria

## Overview

**Creative North Star: "The Reading Lamp"**

Alexandria is a calm, native Mac room with one warm light in it, and the light comes from the book. Everything structural is the system's own: the sidebar, the toolbar, the inspector, sheets, list and table selection, buttons and fields, the SF type ramp and semantic colors that follow Light and Dark. Against that quiet, the artwork is allowed to glow: the Continue hero takes a soft wash from the cover it shows and tints its one action with the cover's color, covers make up the Home diary and the library mosaic, and Lapis marks the single thing to do next.

The app is dense where a Mac app is dense (tables, lists, the inspector) and generous where listening is personal (Home). It reads as Apple's Music, Books and Podcasts read: confident, quiet, specific, never a web page in a window. Motion is short and physical (smooth springs, 0.2–0.5 s), plays once rather than on every visit, and steps aside entirely under Reduce Motion.

The user has rejected the templated look by name: saturated or animated multi-hue gradient backgrounds, glassmorphism cards wrapping content, oversized rounded display faces everywhere, custom translucent pill text fields, and gradient call-to-action buttons.

**Key Characteristics:**
- System chrome and native controls first; custom drawing only where the system has no answer (the diary, the mosaic, cover overlays).
- Color comes from the artwork and from one accent, Lapis; everything else is semantic system ink.
- Liquid Glass belongs to the navigation layer only; content sits on materials.
- Covers are the primary material of the interface.
- Every number, label and state is legible at a glance in both appearances.

## Colors

A system-neutral palette lit by artwork, with one accent.

### Primary
- **Lapis** (#3C67D9): the app accent, from `AccentColor`. The prominent action on a surface (Connect, Add, Sign In), selection and toggled states, the playing episode's play pill, today's column in the diary, and progress wherever no artwork color applies. When the system accent is set to a color, macOS substitutes it; Lapis is the default, not a promise.

### Neutral
- **System ink** (`.primary`, `.secondary`): all text. Information never sits in `.tertiary`; it is reserved for placeholder glyphs.
- **System surfaces** (window background, `.ultraThinMaterial`, `.regularMaterial`): page background and content cards.
- **Hairline** (`separatorColor`): card borders, tile outlines and separators in both appearances.
- **Glyph shade** (#0000008C) and **glyph ink** (#FFFFFF): the round play glyph over covers, which must read on any artwork.

### Artwork color
Each cover yields an `ArtworkPalette` (background, primary, accent). The Home hero uses it for its wash and its Resume button, the grid uses its background as the fill behind non-square covers, and the inspector uses its accent for the current chapter and ratings when it holds 3:1 against the panel (Lapis otherwise). Copy over these colors stays semantic.

### Named Rules
**The One Lamp Rule.** A surface has at most one saturated area: the artwork wash or the Lapis action, never decorative color besides.

**The System Ink Rule.** Text, separators and surfaces use semantic system colors so Light, Dark and Increase Contrast work without custom values; never a white- or black-opacity literal for text.

## Typography

**Display Font:** SF Pro (system)
**Body Font:** SF Pro (system)

**Character:** One family, the Mac's own, in the system's sizes. Hierarchy comes from weight and color, and from a single display size that only Home's greeting uses.

### Hierarchy
- **Display** (bold, 34pt): Home's greeting, populated and empty. Nothing else uses it.
- **Headline** (bold, `.title2`): shelf and section titles on Home and Browse.
- **Title** (semibold, `.subheadline`): titles under covers on cards and shelves.
- **Body** (regular, `.body`): list rows, detail text, show notes.
- **Label** (medium, `.subheadline`, uppercase, `.secondary`): eyebrows such as "CONTINUE · PODCAST" and the date line on stats.
- **Meta** (regular, `.caption`, `.secondary`): author, duration, time left, dates; numbers in `monospacedDigit()`.

### Named Rules
**The System Scale Rule.** Fonts come from `Theme.Typography` or the SF text styles. A fixed `.system(size:)` appears only as a token (the greeting and the empty-state symbol) or scaled to a shape it sits in (the cover play glyph).

**The Steady Numbers Rule.** Changing numbers (times, counts, progress) use `monospacedDigit()` and `contentTransition(.numericText())` so they don't jitter.

## Layout

The window is the system's three-pane shape: sidebar (Home, Library, Browse), the page, and an optional inspector (Now Playing details or Up Next) on the right, with the Now Playing bar floating at the bottom of the page. Pages lay out on the spacing scale: `xl` (28pt) for page gutters and between Home's sections, `l` (20pt) between cards in a grid, `m` (14pt) inside cards and grouped sections, `s` and `xs` inside components. Inside a component, stack spacing may use the small ladder (2, 4, 6, 8, 10, 12pt) directly. Content columns stop growing at 1180pt (`Theme.contentWidth`) and center.

Home opens with the header (greeting, the week's line, the seven-day diary, the library mosaic), then one Continue hero, then horizontal shelves that page with hover chevrons. Scrolling Home hands the greeting to a compact capsule in the toolbar and adds the live level meter beside search; other pages show those permanently.

Grids use adaptive columns (covers 160–200pt in the library, 170–220pt for series, 140–180pt for people). The library also has a native `Table` with row selection.

## Elevation & Depth

Depth comes from layers, not decoration: Liquid Glass for the navigation layer (toolbar items, the Now Playing bar, the compact greeting, floating controls), materials for content (cards, grouped sections, the search dropdown), and two small shadows for covers.

### Shadow Vocabulary
- **Card** (black at 10%, radius 5pt, y 2pt): covers and cards at rest.
- **Lifted** (black at 16%, radius 10pt, y 5pt): a hovered cover, together with a 1.03 scale.

### Named Rules
**The Glass Is Navigation Rule.** `navGlass` and `.glassEffect` go on bars and floating controls only; content cards use `contentCard()` (ultra-thin material and a hairline), never glass.

## Shapes

Continuous (squircle) corners everywhere, sized by what they round: `tile` (4pt) for thumbnails up to about 32pt, `row` (6pt) for row thumbnails and row fills, `control` (8pt) for chips, tooltips and highlights, `cover` (10pt) for covers on cards and in sheets, `group` (12pt) for grouped sections in sheets and the inspector, `card` (16pt) for cards and floating panels, and capsules for pills and toolbar items. Covers keep their own aspect ratio over a flat fill of their palette color; they are never stretched or blurred to fill.

## Components

### Buttons
- **Native first:** `.borderedProminent` for the one primary action on a surface (tinted Lapis, or the artwork's color on the Home hero), `.bordered` for secondary, `.link` for inline actions such as Clear or Show Less.
- **Icon buttons:** plain style with `iconHitTarget` so the whole square, at least 28pt, is clickable.
- **Sheets:** a bottom bar with Cancel and the default action on the right; Esc and Return work. The detail sheet closes from a Done bar.

### Cover cards
- **Shape:** cover at `cover` radius with the card shadow; title and meta beneath.
- **Hover:** the lifted shadow and 1.03 scale (no scale under Reduce Motion), plus the round play glyph centered on the cover.
- **Progress:** a 3pt line along the cover's bottom edge over a dark track (`CoverProgressEdge`), in the artwork's accent (Lapis until the palette loads); finished items darken slightly and carry a small green check badge.

### Episode rows
- **Style:** Apple Podcasts on the Mac: title, a two-line plain excerpt of the notes, then one capsule play pill that carries the time ("39m", "12m left" with a small progress bar, or a green check and "Played"), the date, and a ⋯ menu.
- **Playing:** the pill turns prominent and shows a small animated equalizer; a single click never starts playback, a double-click does.

### Lists and tables
- **Selection:** native `List(selection:)` and `Table(selection:)`; Return or a double-click opens or plays, Delete removes, right-click acts on the whole selection.

### Inputs
- **Fields:** native `TextField` and `SecureField` in `.roundedBorder`, each with a real label above it. The toolbar search is the one custom field, in a glass capsule, focusable with ⌘F.

### Navigation
- **Sidebar:** system sidebar with SF Symbols; libraries are listed with book or antenna symbols.
- **Toolbar:** Now Playing and Up Next are toggles in the toolbar, as in Music.

### Listening diary and library mosaic (signature)
The Home header's two halves are made of covers. The diary is seven day columns, each fanning up to three 22pt covers of what was played that day, with the time beneath and today in Lapis. The mosaic is the library as 22pt tiles at `tile` radius: finished books in full color, in-progress ones with an accent line, unread ones in grayscale; hover names a book and a click opens it. On first appearance per launch the tiles arrive in a diagonal wave, then the read ones color in.

## Do's and Don'ts

### Do:
- **Do** use the system control for the job before drawing one, and keep its native size and style.
- **Do** take radii from `Theme.Radius`, page spacing from `Theme.Space`, fonts from `Theme.Typography` or SF text styles.
- **Do** let the artwork supply color, and keep copy over it in semantic colors.
- **Do** play entrance motion once per launch, and give every animation a Reduce Motion path.
- **Do** say "show" and "episode" in podcast libraries and "book" in book libraries.

### Don't:
- **Don't** use saturated or animated multi-hue gradient backgrounds.
- **Don't** wrap content in glass cards; glass is for navigation.
- **Don't** build custom translucent pill text fields or gradient call-to-action buttons.
- **Don't** set a pointing-hand cursor on cards; Mac apps reserve it for links.
- **Don't** put information in `.tertiary` text.
