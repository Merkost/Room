# Release

## Current candidates — 22 October 2026

- **Store 1.0.0 (5)** — final native archive and genuine Mac App Store export succeeded. The app, installer, profile, entitlements, and exact C4 icon passed distribution verification. Xcode reported **Upload succeeded**. Apple completed build processing and build 5 was selected for version 1.0.0. App Review submission, approval, and public availability are not yet confirmed.
- **Direct 1.8.0 (13)** — final Release rebuild succeeded in **157.34 s**. Actual Scan and Stop were verified without moving files; the Full scan scope was preserved.

The release refines the native hierarchy across Clean, Memory, Disk Map, Developer, Settings, and the menu-bar popup. It uses system typography, a stable toolbar, aligned native scan controls, a solid semantic canvas, smaller measured-value groups, and clearer read-access/setup states. Clean no longer presents an unmeasured first run as a large zero. The approved C4 soft-pocket geometry is unchanged.

## Fresh test checkpoint

| Edition | Result | Local evidence |
| --- | --- | --- |
| Direct 1.8.0 (13) | **186 tests / 20 suites passed in 38.784 s** | `store-publish/direct13-test-build.log` |
| Store 1.0.0 (5) | **171 tests / 20 suites passed in 40.619 s** | `store-publish/store5-test-build.log` |

These are fresh runs for the current release refinement, totaling 357 test executions across the two editions. A subsequent cosmetic fix changed only the swap label tint. The final Direct rebuild, Store archive/export, and distribution-signature checks passed after that fix; the tests were not rerun for the label tint. Unit tests, native acceptance, signing, upload, and review status remain separate evidence.

## Native Store 5 acceptance

The sandboxed Store 5 preview completed a disposable-fixture cleanup and recovery flow:

1. An approved-folder scan found a supported synthetic npm download object.
2. The exact reviewed write grant was required before moving it to Trash.
3. Room quit and relaunched; the cleanup receipt persisted.
4. The prior write grant was not retained. Recovery required a fresh grant.
5. Restore returned the object with matching **SHA256 and SHA512** content hashes.

No user cache moved, Trash was never emptied, and unrelated opened apps were not quit. This is a native synthetic-fixture result, not evidence that every cache or arbitrary file can be cleaned. Evidence: `store-publish/store5-native-acceptance.json` and its owned-fixture manifest.

Native Memory refresh, hidden-file Disk Map and allocated-size presentation, read-only Android/Gradle/project mapping, Settings appearance and About, and RAM/Storage monitor controls were verified. Optional Apple on-device inference remained **not ready**; Analyze honestly preserved rule-based review. No successful Apple-model inference is claimed.

## Final signing and upload

The earlier account/signing block was resolved using the publisher’s Apple account. The required Mac app and installer distribution certificates and explicit Store profile were created/imported with user approval. The final exported Store package passed:

- Expected bundle identifier `com.merkost.room`, version 1.0.0, build 5, and team/profile match.
- Deep strict application signature and the expected Mac app distribution authority.
- Installer distribution certificate, team, and certificate-fingerprint checks.
- App Sandbox, user-selected read/write access, and app-scoped bookmarks; no debug entitlement or network-client entitlement.
- Byte-identical approved C4 icon.

The installer checker’s generic Apple-chain label includes “Development”; its actual leaf is the expected **3rd Party Mac Developer Installer** distribution certificate, independently checked by name and fingerprint. This is not a development-signed Store upload claim.

Final local export evidence: `store-publish/store5-final-archive.log`, `store5-final-export.log`, and `store5-final-distribution-proof.json`. The separately executed upload log, `store5-upload.log`, reports 100%, **Upload succeeded**, and package processing on 22 October 2026. The processed build was subsequently observed and attached in App Store Connect. Upload and build processing do not establish review submission.

## Listing and screenshots

The Store title and subtitle were saved live as **Room: Disk Space & Memory** / **Storage maps & cache review**. The app is configured to be free, with no ads or in-app purchases. **Data Not Collected** was published after user confirmation. Private review contact details are omitted here.

Six current Store 5 screenshot compositions are prepared under `screenshots-store5`: Disk Map, Clean, Developer, reviewed cleanup, Memory, and the menu-bar monitor. Each is **2880×1800, opaque sRGB**, using fresh actual Store 5 captures. Source/output hashes and synthetic-folder labels are recorded; no old Store 3/4 native crops are reused. All six were uploaded, and all six finished Apple processing. The final English description, promotional text, keywords, reviewer notes, and sandbox usage explanation are saved.

## Product boundaries

Store cleanup admits only supported SHA512-addressed npm download-object leaves modified more than 30 days ago, within approved folders and bounded local content verification plus exact reviewed write access. npm indexes/temp, installed packages, and other process-guarded caches remain held because complete background-tool visibility is unavailable. General agent-cache cleanup, worktree actions, external model executables, and other-app termination are excluded from the Store edition.

Verification does not prove non-use. Downloads may recur, active installs may retry, and offline installs may fail. Room does not empty Trash. Restore rechecks content, identity, and access and refuses occupied destinations. Read approvals cover accessible descendants, while macOS protection and separate-volume approval remain. AVD metadata does not establish verified last launch; Gradle references cover selected project wrappers, and a missing reference does not mean unused.

The Direct edition retains broader guarded cache scanning, explicit normal app-quit review, and separate conservative worktree review. Current Direct 13 Scan/Stop acceptance moved no files. Successful actual local-model Analyze, busy Stop, owned-worker exit, Quit, and healthy relaunch remain specifically **historical Direct build 11** evidence; those interactive model flows were not rerun on Direct 13. Earlier Store 2 recovery and Store 3 functional checks are retained as historical checkpoints and are not relabeled as Store 5 runs.

## Remaining publication steps

The user requested a motion preview before submission. The exact requested design model was verified available; motion direction is in production. A Store preview must use genuine app footage, and the native macOS recorder currently needs user assistance to open. No animated-stills marketing video is represented as a qualifying Store preview. Finish and verify the video, upload it, then submit and verify App Review status. Approval and live Store release are later outcomes. No submitted, approved, or publicly available status is claimed.

Support: `https://room.merkost.dev/support/`. Privacy: `https://room.merkost.dev/privacy/`.

Local evidence paths above are relative to the task’s `work/room-native/` evidence directory; credentials, key locations, and private contacts are deliberately excluded.
