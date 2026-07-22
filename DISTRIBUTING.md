# Distributing Alexandria

How to package the app as a `.dmg` and cut GitHub releases. Written for someone
new to the Apple toolchain.

## TL;DR

```bash
# 1. Bump the version in Xcode (target → General → Version), commit it.
# 2. Tag and push — GitHub Actions builds the DMG and creates the release:
git tag v0.2.0
git push origin v0.2.0
```

To build a DMG locally without releasing (for testing):

```bash
Scripts/package.sh           # → build/Alexandria-<version>.dmg
Scripts/package.sh 0.2.0     # force a version
```

---

## The pieces

| File | What it does |
|------|--------------|
| `Scripts/package.sh` | Archives a Release build (ad-hoc signed), wraps the `.app` + an `/Applications` shortcut into `build/Alexandria-<version>.dmg`. |
| `.github/workflows/release.yml` | On a pushed `v*` tag, runs the script on a macOS runner and publishes the DMG to a GitHub Release with auto-generated notes. |

`build/` is git-ignored — artifacts never get committed.

## Signing reality (read this once)

macOS Gatekeeper checks who signed an app. There are three tiers:

1. **Ad-hoc signed (what we do now, free).** The app is signed with `"-"` — enough
   to *run* (Apple Silicon refuses completely unsigned apps), but Apple hasn't
   notarized it. The **first** time another person opens it they get
   *"Alexandria can't be opened because Apple cannot check it for malicious
   software."* They open it anyway via **right-click (or Control-click) → Open →
   Open**, or from Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Alexandria.app
   ```
   Put those instructions in the release notes. This is normal for hobby/open-source
   Mac apps.

2. **Developer ID + notarized (the "just works" upgrade, needs the paid
   [Apple Developer Program](https://developer.apple.com/programs/), $99/yr).**
   The DMG opens with no warning. When you're ready, this adds three steps after
   the archive (a *Developer ID Application* certificate, `xcrun notarytool
   submit --wait`, then `xcrun stapler staple`) — see "Upgrading to notarized"
   below. Nothing else in this setup changes.

3. **Mac App Store.** A different pipeline entirely (App Store Connect, sandbox
   review). Not covered here.

## Release workflow (the normal loop)

1. **Bump the version.** In Xcode: select the **Alexandria** target → **General**
   → **Version** (this is `MARKETING_VERSION`, e.g. `0.1` → `0.2.0`). Commit it.
   *(Optional: also bump Build if you ship multiple builds of one version.)*
2. **Tag it** with a matching `v` tag and push:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
3. The **Release** Action runs, builds `Alexandria-0.2.0.dmg`, and creates the
   GitHub Release. Check the **Actions** tab; the DMG appears under **Releases**.

Use [semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`
(breaking / feature / fix).

### Prefer to publish from your Mac instead of CI?

Skip the tag-push and do it locally with the `gh` CLI (already installed & authed):

```bash
Scripts/package.sh 0.2.0
gh release create v0.2.0 build/Alexandria-0.2.0.dmg --generate-notes
```

Do **one or the other** for a given version — if you both push the tag *and*
`gh release create`, the Action and your local command will collide on the same
release.

## CI note (Xcode version)

The app uses macOS 26 (Liquid Glass) APIs guarded by `#available`. Compiling them
needs the **macOS 26 SDK (Xcode 26+)**. The workflow selects `latest-stable`; if
GitHub's runners don't have Xcode 26 yet, the CI build will fail to compile the
glass code — until then, cut releases locally with `Scripts/package.sh` (your Mac
has Xcode 26). Bump nothing else; CI will start working once the runner image
catches up.

## Upgrading to notarized (later, when you have the $99 account)

1. In Xcode → **Settings → Accounts**, add your Apple ID; create a **Developer ID
   Application** certificate (Xcode can do this, or the Developer portal).
2. Set the target's **Team** and use that identity instead of `"-"` in
   `Scripts/package.sh`'s archive step.
3. After building the DMG, notarize and staple:
   ```bash
   xcrun notarytool submit build/Alexandria-<v>.dmg \
     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw" --wait
   xcrun stapler staple build/Alexandria-<v>.dmg
   ```
   (Store the Apple ID / app-specific password as GitHub **Secrets** for CI.)

Once notarized, drop the right-click-to-open instructions — the DMG just opens.
