# Native Store archive

`project.yml` is the source of the native Xcode project. It defines the macOS application target `Room` (product `Room.app`), a statically linked `RoomCore` target, and the shared `StoreArchive` scheme. Both targets compile `ROOM_APP_STORE` in Swift 6 for arm64 and macOS 26. The app target also uses MainActor default isolation, matching the Swift package app target.

Source directories are included recursively. Regenerate after adding or removing a source file. The project uses the existing Store Info.plist, entitlements and icon; it does not rewrite those resources or the Swift package. Tests remain available through the Swift package commands in the main README.

## Preview commands

From the Room project directory:

```sh
./scripts/archive-store.sh --dry-run all
```

The dry run prints every command without generating a project, compiling, contacting Apple, signing, or creating distribution artifacts.

## Generate, archive and export

Requires Xcode 26.6 or newer selected through `xcode-select`, XcodeGen 2.45.3 or newer, and access to the configured developer team. The Store bundle identifier is `com.merkost.room`.

```sh
# Generate the project only. This does not compile or sign.
./scripts/generate-store-project.sh

# Create a real Xcode archive, then export a local App Store Connect package.
./scripts/archive-store.sh all
```

The default artifact directory is `$TMPDIR/Room-Store-distribution` (or `/tmp/Room-Store-distribution` when TMPDIR is unset). Existing archives and exports are preserved; set a fresh path for a subsequent run:

```sh
ROOM_STORE_ARTIFACTS_DIR=/absolute/path/Room-1.0.0-1 ./scripts/archive-store.sh all
```

Actions can also run separately:

```sh
./scripts/archive-store.sh archive
./scripts/archive-store.sh export
```

`ROOM_STORE_ARCHIVE_PATH`, `ROOM_STORE_EXPORT_PATH` and `ROOM_STORE_DERIVED_DATA` override individual paths. `ROOM_XCODEGEN_BIN` selects a specific XcodeGen executable.

## Signing

The application archives with automatic signing and an Apple Development identity. Xcode re-signs the app with the Store distribution identity during export and signs the package with a Mac Installer Distribution identity. The static library is linked into the app.

Room’s current sandbox, user-selected read/write and app-scoped bookmark entitlements are unrestricted on macOS. The Mac App Store accepts apps with this entitlement contract without a provisioning profile. TestFlight and apps with restricted entitlements have different requirements. [Apple’s provisioning profile guidance](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), [Apple’s installer signing guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution?changes=__3)

Signing secrets are not part of this repository. Configure the authorized publisher account and certificates in Xcode or supply signing settings through the normal Xcode build environment. `--allow-provisioning-updates` explicitly permits Xcode to contact Apple and manage signing assets; it is off by default:

```sh
./scripts/archive-store.sh --allow-provisioning-updates all
```

The export template `scripts/ExportOptions-AppStore.plist` uses `app-store-connect` with destination `export`. It preserves the checked-in version/build numbers and requests symbols plus App Store information. It does not upload. `ROOM_STORE_EXPORT_OPTIONS` can point to a publisher-reviewed alternative plist for manual signing or a different local export configuration. The script rejects an upload destination, including in an alternative plist.

Version values in `Resources/Info-Store.plist` are authoritative in the built bundle. Keep the matching `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` values in `project.yml` in sync when preparing a new release.

## Verify local artifacts

Run these from the checkout that supplied the artifact’s release settings.

```sh
# Verify an existing Xcode development archive. Omit the path to use the archive script's default.
./scripts/verify-store.sh archive /absolute/path/Room.xcarchive

# Verify a genuine exported Mac App Store installer.
./scripts/verify-store.sh package /absolute/path/Room.pkg

# Check Store application and installer signing identities in the local keychain search list.
./scripts/verify-store.sh signing

# Optionally match an existing Store profile to Room and the local distribution certificate.
./scripts/verify-store.sh signing /absolute/path/Store.provisionprofile
```

The verifier checks the bundle, version, build, executable architecture, Apple signing team and sealed app signature against this checkout. It reads the signed sandbox entitlements from the artifact. Package verification also requires the Store installer signature and distribution-signed app, then checks the app in a private temporary expansion. An embedded profile, when present, is checked for team, app, validity period and the app signing certificate. The development archive check also accepts a team-wide development profile.

The verifier uses the selected Xcode toolchain and local macOS trust settings. It does not run the installer, upload, change credentials, or print identity names, account identifiers, profile UUIDs or certificate fingerprints. The optional `signing` check reports missing local identities separately from artifact integrity. App Store Connect processing and review require separate evidence.

References: [XcodeGen project specification](https://github.com/yonaskolb/XcodeGen/blob/2.45.3/Docs/ProjectSpec.md). The export keys were checked against the installed Xcode 26.6 `xcodebuild -help` output.
