<p align="center"><img src="Resources/Room-1024.png" width="96" alt="Room app icon"></p>

<h1 align="center">Room</h1>

<p align="center"><strong>See what fills your Mac.</strong></p>
<p align="center"><a href="https://room.merkost.dev/">Website</a> · <a href="https://room.merkost.dev/support/">Support</a> · <a href="https://room.merkost.dev/privacy/">Privacy</a></p>

Room is a native Mac app for mapping storage, reviewing cache moves, and watching memory. It runs locally and requires no account. Built by Merkost.

## What Room does

- **Overview** shows free space, storage changes over time, and folders you’ve pinned.
- **Disk Map** turns folders you choose into a visual map. Find large files, explore accessible hidden items, and compare saved scans when history is available.
- **Caches** shows what’s taking up space and lets you review eligible moves. Room keeps a receipt for each move so you can restore unchanged items when their original locations are available.
- **Developer** shows Android virtual devices, Gradle storage, and version references from projects you select. The Storage tab measures SDK images, downloaded Gradle JDKs, daemon data, and Apple Simulator devices in folders you approve.
- **Memory** shows pressure, RAM use, compression, and swap. The menu bar can show memory or free space.

## Editions

| | Mac App Store | Direct |
| --- | --- | --- |
| Cache moves | Eligible npm downloads older than 30 days that pass local verification. Moving them requires approval for each exact folder. | A broader cache catalog with eligibility checks and a review before moving files. |
| Memory | Monitoring and suggestions. | Monitoring, suggestions, and a review for quitting selected apps normally. |
| Storage suggestions | Local rules and optional Apple on-device analysis. | Local rules, Apple on-device analysis, or a separately installed local model runtime. |
| Worktrees | — | Review eligible finished worktrees before moving them to Trash. |

Room moves eligible files to Trash. They still use disk space there until you empty it. Recovery checks the item and its original location before restoring it.

## Developer storage

| Choose this folder | Room can measure |
| --- | --- |
| Gradle User Home, usually `~/.gradle` | `daemon/` logs and registries, plus toolchain JDKs in `jdks/`. [Gradle directory layout](https://docs.gradle.org/current/userguide/directory_layout.html) |
| Android SDK, usually `~/Library/Android/sdk` | Emulator OS images in `system-images/`. [Android emulator directories](https://developer.android.com/studio/run/emulator-commandline#directories) |
| `~/Library/Developer/CoreSimulator/Devices` | Simulator devices and their app data. Manage Simulator OS runtimes separately in Xcode. [Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components) |

Room measures disk space used by these folders. These sizes are for inspection in Developer.

## Build and test

You’ll need an Apple silicon Mac running macOS 26 or later, and Xcode with Swift 6.2 or later.

```sh
git clone https://github.com/Merkost/Room.git
cd Room
swift build
```

Build a local app bundle for either edition from the repository root.

```sh
./scripts/build.sh "$PWD/.build/Room.app"
./scripts/build-store.sh "$PWD/.build/Room Store.app"
```

The second command builds a locally signed sandbox preview. Distribution uses the [Mac App Store archive workflow](scripts/STORE-ARCHIVE.md).

```sh
swift test
ROOM_EDITION=store swift test --scratch-path .build/store-tests
```

## Project links

- [Architecture](docs/ARCHITECTURE.md) covers the SwiftUI and AppKit interface, file access, scanning, and recovery.
- [Design](DESIGN.md) describes the interface and its interaction rules.
- [Release notes](docs/RELEASE.md) record past builds and verification.
- [GitHub issues](https://github.com/Merkost/Room/issues) is the place to report bugs or propose improvements.

## License

A project license is pending.
