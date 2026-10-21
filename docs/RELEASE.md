# Release

## Qualified candidates

- **Store 1.0.0 (3)**: native Xcode archive succeeded. An archive-derived sandboxed preview was installed and checked. This is not a distribution-signed Store export or upload.
- **Direct 1.7.2 (11)**: release build succeeded, installed, and passed strict `codesign` verification. No notarization or public-release claim is implied.

Final source/build acceptance is complete for these candidates. The root task is consolidating the separate final proof JSON; earlier checkpoints are not relabeled as these artifacts.

## Final tests

| Edition | Result | Evidence |
| --- | --- | --- |
| Store build 3 | **171 tests / 20 suites passed in 35.279 s** | `work/room-native/store-tests-release3-20261022.log` |
| Direct build 11 | **186 tests / 20 suites passed in 28.181 s** | `work/room-native/direct-tests-release11-20261022.log` |

These final runs supersede earlier 166/171 Store and 181 direct checkpoints. Unit tests and native acceptance remain distinct evidence.

## Native Store acceptance

Build 3 verified saved-folder read access, hidden-file Disk Map/rescan, styling, About build 3, pressure/swap settings, and the exact cleanup-impact disclosure. **Move to Trash remained disabled before the native exact-folder write grant.** No actual move was repeated on build 3.

The complete recovery flow was exercised on **Store release 2**, using one disposable **1 MiB (1,048,576-byte)** npm object:

1. Approved-folder scan found the synthetic eligible object.
2. Its cleanup consequences were reviewed, including download/retry/offline effects.
3. A native panel approved its exact npm prefix-bucket parent for the reviewed write.
4. The object moved to Trash with a local receipt.
5. Room quit and relaunched; read approvals persisted.
6. Restore returned the object with identical **SHA256 and SHA512** content.

Core and Store write/recovery code were unchanged for build 3. The carried recovery evidence therefore remains specifically a release 2 full-move test plus build 3 permission/impact smoke, not a second build 3 move. Only synthetic fixture data moved; **no user caches were cleaned**.

Synthetic native Android/Gradle mapping passed. AVD review remains read-only and metadata dates do not establish last launch. Gradle references cover selected project wrappers; no reference does not mean unused. On the qualification Mac, the Apple Intelligence model was not ready and the honestly labeled rule-based fallback worked. No Apple-model inference success is claimed.

## Direct native acceptance

Build 11 completed actual Analyze through its owned local-model worker. Stop while busy displayed **“Analysis stopped. Current review kept.”** and the owned worker exited. Quit while busy exited Room and its worker and removed temporary key directories. Healthy relaunch and About build 11 passed. These direct-runtime results are not Store AI evidence; unrelated opened apps were not targeted.

A read-only Full scan completed 216 catalogue locations and 43 source groups. Stop was responsive, and no files moved. Personal storage totals and paths are deliberately omitted.

## Scope and cleanup boundaries

Disk Map exposes labeled Scan/Rescan/Stop, current-folder context, allocated-size categories and hidden-file filters. Remembered ancestor read access covers accessible descendants, while macOS protections and separate-volume approvals remain. The monitor supports RAM or available storage with actual pressure colors and optional swap details; unavailable signals remain unknown.

Store is free, with no ads or in-app purchases. It excludes other-app termination, external model executables, worktree actions and Git remote verification. Store cleanup admits only supported npm SHA512-addressed download-object leaves modified more than 30 days ago and passing bounded local verification plus exact reviewed access. npm index/tmp, installed packages and other process-guarded caches stay held because complete background-tool visibility is unavailable. General Codex/Claude cache cleanup is excluded.

Verification does not prove non-use: downloads can recur, active installs can retry, and offline installs can fail. Trash retains disk space until the user empties it; Room never does so. Restore rechecks content/identity/access and refuses occupied destinations. The successful narrow fixture does not imply global all-file or whole-Trash access.

## Store distribution and last-saved account state

The final build 3 Store export was retried and failed with exit code **70**: **No Accounts**, missing **Mac Installer Distribution** identity/certificate, and no provisioning profile for `com.merkost.room`. Native archive success does not establish a distribution-signed export, accepted upload or Apple export-compliance approval. Info declares `ITSAppUsesNonExemptEncryption=false`.

The Chrome App Store Connect session has expired. The following is **last-saved state before expiry**, not a fresh live account check:

- App `com.merkost.room`, record `6825292305`, Prepare for Submission.
- Description, Promotional Text, Keywords, review contact and no-sign-in saved; private contact values are omitted.
- Free pricing and All Countries or Regions (175) saved, each Available on App Release.
- Seven existing No/None, non-Kids age steps reviewed, calculated 4+; unchanged disabled Save/Cancel preserved them.
- Data Not Collected answers saved **but not published**. Final legal privacy Publish/attestation still requires the user's confirmation at that action.

## Remaining publication work

Five actual Store build 3 screenshots have been captured; composition is in progress. **Zero screenshots are uploaded.** The chosen set will be five strong frames; ten is the optional maximum, not a requirement. Historical direct layout studies are not final upload assets. Final compositions need dimension, readability, privacy and metadata checks.

Renew account access and resolve Store signing/profile prerequisites, validate a genuine distribution export, finish user-confirmed privacy publication and remaining publisher declarations, then upload and verify processing. App Review submission, approval and live availability are separate later outcomes. No Store upload, review approval or public Store release is claimed.

Configured support: `https://room.merkost.dev/support/`. Configured privacy: `https://room.merkost.dev/privacy/`.
