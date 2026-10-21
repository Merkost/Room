<p align="center"><img src="Resources/Room-1024.png" width="116" alt="Room icon"></p>

<h1 align="center">Room</h1>
<p align="center">Storage, clearly. A little more room for your Mac.</p>
<p align="center"><a href="https://room.merkost.dev">Website</a> · <a href="https://room.merkost.dev/support/">Support</a> · <a href="https://room.merkost.dev/privacy/">Privacy</a></p>

Room is a native macOS utility for understanding storage, reviewing developer resources, and monitoring memory. Built with SwiftUI, AppKit, and Liquid Glass. Free, with no ads or in-app purchases.

![Room Disk Map showing sample folders](Resources/RoomPreview.png)

## See what is taking space

- **Clean** — measure known caches, distinguish clearable items from held storage, and review before any supported move to Trash.
- **Disk Map** — explore allocated size by folder, including hidden files, categories, and large items. Labeled Scan, Rescan, and Stop controls keep the current folder clear.
- **Developer** — review Android virtual-device sizes and available metadata evidence; group Gradle storage by version and show references from selected project wrappers. This view is read-only. Standard AVD metadata does not provide verified last-launch history, and no project reference does not mean unused.
- **Memory** — inspect RAM, compression, swap, and the macOS pressure signal. Choose RAM or available storage for the menu bar; pressure colors and swap details are configurable. Unavailable signals stay unknown.
- **Activity** — keep local cleanup receipts and restore unchanged items when their original locations remain available.
- **Local analysis** — add on-device review suggestions when supported; deterministic protections remain in charge.

Storage scans start on demand. The optional menu-bar monitor periodically samples memory and disk capacity. Unknown files, installed resources, credentials, and project source remain held for inspection. Moving files to Trash does not release their disk space until Trash is emptied. Room never empties Trash.

## Two editions

| | Mac App Store candidate | Direct |
|---|---|---|
| File access | Native, remembered read-only folder approvals; optional home-folder approval covers accessible descendants. Reviewed changes need temporary exact write grants. | Broader known-location scans, subject to macOS permissions; Settings opens Full Disk Access for the user to enable. |
| Cache cleanup | Narrow exception for old, locally SHA512-verified npm download objects. Other process-guarded caches remain held because sandboxed background-tool visibility cannot be established. | Broader known-cache cleanup with age, identity and available owner-activity checks. |
| Developer review | Read-only AVD evidence and Gradle selected-project references. | Same read-only review. |
| Memory | Monitoring and suggestions. | Monitoring plus an explicit normal app-quit review. |
| Analysis | Apple on-device models when available, otherwise local rules. | Apple on-device models, an optional separately installed local runtime, or rules. |
| Agent worktrees | Excluded. Codex and Claude storage may be inspected, but general agent-cache cleanup is not enabled. | Separate worktree review with live remote verification and conservative holds. |

The Store npm exception applies only to supported immutable download-object files modified more than 30 days ago, within approved folders and bounded local content-verification limits. It does not prove an object is unused. Installs may download it again, active installs may retry, and offline installs may fail. npm indexes, temporary data, and installed packages stay in place. Native sandboxed Trash, Quit/relaunch and Restore passed on a disposable release 2 fixture with exact content hashes; build 3 verified the impact disclosure and pre-grant write gate without repeating the move. Core/Store write code was unchanged, and no user caches were cleaned.

Store 1.0.0 (3) passed its final tests and archive-derived sandboxed native checks; direct 1.7.2 (11) passed its final tests, native checks and strict signature verification. Store distribution export remains blocked by account/signing prerequisites, and publication work is still in progress. An App Store record, local build, or passing unit test is not a published download. The website shows release availability when it is ready.

## Build

Requires an Apple silicon Mac, macOS 26+, and Xcode with Swift 6.2 or newer. No external package dependencies are needed to build the app.

```sh
# Direct edition
./scripts/build.sh

# Sandboxed Store candidate
./scripts/build-store.sh
```

These scripts create locally signed candidates. App Store distribution requires the publisher’s distribution signing identities, provisioning, and an accepted upload.

```sh
swift test
ROOM_EDITION=store swift test
```

Tests use isolated fixtures. Some recovery tests exercise macOS Trash with their own temporary files. Unit-test fixtures do not establish distribution-signed sandbox behavior.

## Design and boundaries

The interface uses native glass controls, a flat adaptive toolbar, readable numeric hierarchy, keyboard shortcuts, and system Reduce Motion and Reduce Transparency preferences. Scan cancellation keeps partial results visibly incomplete.

Read-only folder bookmarks cover accessible descendants, so rescans and approved drill-down do not need another picker. macOS may still protect files, and other volumes need separate approval. Room never enables system permissions itself.

Cleanup rechecks path and filesystem identity, age, applicable content validation, owner activity where reliable, and access before moving an item. Unverifiable candidates remain held. Restore refuses changed files and occupied destinations. These checks reduce races; filesystem changes are not an atomic transaction. npm verification reads bounded object contents locally; optional model analysis receives metadata rather than scanned file contents.

`RoomCore` owns scanners, classifications, cleanup, and recovery. `RoomApp` owns observable state, native permissions, and views. See [architecture](docs/ARCHITECTURE.md) for the source map and [release notes](docs/RELEASE.md) for distribution boundaries.

## Website

The `website/` directory contains the static marketing, support, and privacy pages for Cloudflare. It has no analytics, advertising SDK, sign-in, or third-party font dependency.

© 2026 Konstantin Merenkov. All rights reserved.
