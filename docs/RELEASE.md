# Release

## Direct edition

The direct edition supports broader known-location scans and a separate worktree review. Local builds are ad hoc signed unless a publisher identity is supplied. Public direct distribution additionally requires appropriate signing and notarization.

## Mac App Store edition

Bundle identifier: `com.merkost.room`.

The first Store release is free, with no advertising or in-app purchases. It is sandboxed and uses native user-selected file access. It excludes app termination, external model executables, and the direct worktree cleanup flow.

Release gates are separate: tests, signed sandbox behavior, final screenshots, metadata, distribution signing, upload processing, App Review, and live availability. Passing one does not establish the next.

The support and privacy pages use `https://room.merkost.dev/`. Availability on the website must match the actual release state.
