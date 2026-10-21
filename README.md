<p align="center"><img src="Resources/Room-1024.png" width="116" alt="Room icon"></p>

<h1 align="center">Room</h1>
<p align="center">Storage, clearly. A little more room for your Mac.</p>
<p align="center"><a href="https://room.merkost.dev">Website</a> · <a href="https://room.merkost.dev/support/">Support</a> · <a href="https://room.merkost.dev/privacy/">Privacy</a></p>

Room is a native macOS utility for understanding storage, reviewing developer resources, and monitoring memory. Built with SwiftUI, AppKit, and Liquid Glass. Free, with no ads or in-app purchases.

## See what is taking space

- **Clean** — measure known caches, separate clearable items from held resources, and review before moving anything to Trash.
- **Disk Map** — explore allocated size by folder, including hidden files, with drill-down and large-item details.
- **Memory** — inspect RAM, compression, swap, and the macOS pressure signal.
- **Activity** — keep cleanup receipts and restore unchanged items when the original location is still available.
- **Local analysis** — add on-device suggestions when supported; deterministic protections remain in charge.

Scans are on demand. Unknown files, installed resources, credentials, and project source are held for inspection. Moving files to Trash does not release their disk space until Trash is emptied. Room never empties Trash.

## Two editions

| | Mac App Store | Direct |
|---|---|---|
| File access | Folders selected through native macOS permission dialogs | Broader known-location scans, subject to macOS permissions |
| Memory | Monitoring and suggestions | Monitoring plus an explicit normal app-quit review |
| Analysis | Apple on-device models when available, otherwise local rules | Apple on-device models, optional separately installed local runtime, or rules |
| Agent worktrees | Excluded from the first Store release | Separate review with live remote verification and conservative holds |

The Store edition is being qualified for its first release. An App Store record or local build is not a published download. The website shows release availability when it is ready.

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

Tests use isolated fixtures. Some recovery tests exercise macOS Trash with their own temporary files.

## Design and boundaries

The interface uses native glass controls, readable numeric hierarchy, keyboard shortcuts, and system Reduce Motion and Reduce Transparency preferences. Scan cancellation keeps partial results visibly incomplete.

Cleanup rechecks path and filesystem identity, age, owner activity where reliable, and access before moving an item. Unverifiable candidates remain held. Restore refuses changed files and occupied destinations. These checks reduce races; filesystem changes are not an atomic transaction.

`RoomCore` owns scanners, classifications, cleanup, and recovery. `RoomApp` owns observable state, native permissions, and views. See [architecture](docs/ARCHITECTURE.md) for the source map and [release notes](docs/RELEASE.md) for distribution boundaries.

## Website

The `website/` directory contains the static marketing, support, and privacy pages deployed on Cloudflare. It has no analytics, advertising SDK, sign-in, or third-party font dependency.

© 2026 Konstantin Merenkov. All rights reserved.
