# Release

## Final C4 identity candidates

The user-selected **C4 soft pocket** is applied exactly as the SVG-derived graphite/white icon and five filled native mark consumers.

- **Direct 1.7.3 (12)**: Swift Release build exited 0 in **126.96 s**; installed. Actual C4 toolbar and Settings build label 12 were inspected.
- **Store 1.0.0 (4)**: native Xcode archive reported **ARCHIVE SUCCEEDED**, exit 0; installed. Actual C4 toolbar, onboarding, menu popup and Settings build label 4 were inspected. Store quit after capture; direct Room was left running.

Core, scanning, cleanup and model code are unchanged. The functional tests below remain the previous Store 3/direct 11 checkpoint; **Core/AI/cache tests were not rerun for the C4 identity-only change**. No new cleanup/move is claimed.

The direct and sandbox-preview ZIPs were extracted and passed `codesign --deep --strict`; packaged icon bytes match the selected C4. `outputs/Room-macOS.zip` is direct 1.7.3 (12); `outputs/Room-Store-sandbox.zip` is Store preview 1.0.0 (4). Store archive ZIP `outputs/Room-AppStore/Room-1.0.0-4.xcarchive.zip` is ready. Package hashes are recorded in `work/room-native/c4-packages-proof.json`; identity/build/native proof is consolidated in `work/room-native/c4-identity-proof.json`. Local strict signature checks do not establish a Store distribution export or notarization.

C4 website branding deployment **`8003eb77-f495-487d-807a-af0835734db4`** was verified. Website branding and the user's logo choice did not change Apple account/privacy state or authorize the pending legal privacy Publish action.

Five C4 screenshot compositions are complete under `screenshots-c4`, each **2880×1800, opaque sRGB**. Four use unchanged qualified Store 3 native content crops excluding the old toolbar glyph; the fifth uses a fresh actual Store 4 full monitor capture. Root reviewed the contact sheet; provenance/source/output hashes are recorded. This is not five all-new Store 4 captures. Earlier Store 3 proofs remain preserved; **zero screenshots are uploaded**.

## Previous qualified functional candidates

- **Store 1.0.0 (3)**: native Xcode archive succeeded. An archive-derived sandboxed preview was installed and checked. This is not a distribution-signed Store export or upload.
- **Direct 1.7.2 (11)**: release build succeeded, installed, and passed strict `codesign` verification. No notarization or public-release claim is implied.

Source/build acceptance was complete for these previous functional candidates. Their proof is preserved and not relabeled as Store 4/direct 12 acceptance.

## Functional test checkpoint — Store 3 / direct 11

| Edition | Result | Evidence |
| --- | --- | --- |
| Store build 3 | **171 tests / 20 suites passed in 35.279 s** | `work/room-native/store-tests-release3-20261022.log` |
| Direct build 11 | **186 tests / 20 suites passed in 28.181 s** | `work/room-native/direct-tests-release11-20261022.log` |

These runs passed on Store build 3/direct build 11 and supersede earlier checkpoints. They were not rerun or relabeled as Store 4/direct 12 tests; Core/scanning/cleanup/model source is unchanged for C4. Unit tests, identity rebuilds and native appearance acceptance remain distinct evidence.

## Native Store acceptance

Build 3 verified saved-folder read access, hidden-file Disk Map/rescan, styling, About build 3, pressure/swap settings, and the exact cleanup-impact disclosure. **Move to Trash remained disabled before the native exact-folder write grant.** No actual move was repeated on build 3.

The complete recovery flow was exercised on **Store release 2**, using one disposable **1 MiB (1,048,576-byte)** npm object:

1. Approved-folder scan found the synthetic eligible object.
2. Its cleanup consequences were reviewed, including download/retry/offline effects.
3. A native panel approved its exact npm prefix-bucket parent for the reviewed write.
4. The object moved to Trash with a local receipt.
5. Room quit and relaunched; read approvals persisted.
6. Restore returned the object with identical **SHA256 and SHA512** content.

Core and Store write/recovery code were unchanged for build 3 and remain unchanged in the identity-only build 4 source. The carried recovery evidence therefore remains specifically a release 2 full-move test plus build 3 permission/impact smoke, not a second build 3 move. Only synthetic fixture data moved; **no user caches were cleaned**.

Synthetic native Android/Gradle mapping passed. AVD review remains read-only and metadata dates do not establish last launch. Gradle references cover selected project wrappers; no reference does not mean unused. On the qualification Mac, the Apple Intelligence model was not ready and the honestly labeled rule-based fallback worked. No Apple-model inference success is claimed.

## Direct native acceptance

Build 11 completed actual Analyze through its owned local-model worker. Stop while busy displayed **“Analysis stopped. Current review kept.”** and the owned worker exited. Quit while busy exited Room and its worker and removed temporary key directories. Healthy relaunch and About build 11 passed. These direct-runtime results are not Store AI evidence; unrelated opened apps were not targeted.

A read-only Full scan completed 216 catalogue locations and 43 source groups. Stop was responsive, and no files moved. Personal storage totals and paths are deliberately omitted.

## Scope and cleanup boundaries

Disk Map exposes labeled Scan/Rescan/Stop, current-folder context, allocated-size categories and hidden-file filters. Remembered ancestor read access covers accessible descendants, while macOS protections and separate-volume approvals remain. The monitor supports RAM or available storage with actual pressure colors and optional swap details; unavailable signals remain unknown.

Store is free, with no ads or in-app purchases. It excludes other-app termination, external model executables, worktree actions and Git remote verification. Store cleanup admits only supported npm SHA512-addressed download-object leaves modified more than 30 days ago and passing bounded local verification plus exact reviewed access. npm index/tmp, installed packages and other process-guarded caches stay held because complete background-tool visibility is unavailable. General Codex/Claude cache cleanup is excluded.

Verification does not prove non-use: downloads can recur, active installs can retry, and offline installs can fail. Trash retains disk space until the user empties it; Room never does so. Restore rechecks content/identity/access and refuses occupied destinations. The successful narrow fixture does not imply global all-file or whole-Trash access.

## Store distribution and last-saved account state

The last Store export attempt was for build 3 and was retried and failed with exit code **70**: **No Accounts**, missing **Mac Installer Distribution** identity/certificate, and no provisioning profile for `com.merkost.room`. Native archive success does not establish a distribution-signed export, accepted upload or Apple export-compliance approval. Info declares `ITSAppUsesNonExemptEncryption=false`.

The Chrome App Store Connect session has expired. The following is **last-saved state before expiry**, not a fresh live account check:

- App `com.merkost.room`, record `6825292305`, Prepare for Submission.
- Description, Promotional Text, Keywords, review contact and no-sign-in saved; private contact values are omitted.
- Free pricing and All Countries or Regions (175) saved, each Available on App Release.
- Seven existing No/None, non-Kids age steps reviewed, calculated 4+; unchanged disabled Save/Cancel preserved them.
- Data Not Collected answers saved **but not published**. Final legal privacy Publish/attestation still requires the user's confirmation at that action.

## Remaining publication work

The selected five C4 compositions are complete, inspected and provenance-verified, with four unchanged Store 3 native content crops and one fresh Store 4 monitor capture. Prior Store 3 compositions/proofs remain preserved. **Zero screenshots are uploaded.** Ten is optional maximum, not a requirement. Account/signing, final legal privacy confirmation and submission gates below are unchanged.

Renew account access and resolve Store signing/profile prerequisites, validate a genuine distribution export, finish user-confirmed privacy publication and remaining publisher declarations, then upload and verify processing. App Review submission, approval and live availability are separate later outcomes. No Store upload, review approval or public Store release is claimed.

Configured support: `https://room.merkost.dev/support/`. Configured privacy: `https://room.merkost.dev/privacy/`.
