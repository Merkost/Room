# Release

## Shared candidate features

Disk Map has labeled Scan/Rescan/Stop controls, current-folder context, category and hidden-file filters, and remembered ancestor-folder access for accessible drill-down. Developer review is read-only: Android AVD sizes and metadata evidence, plus Gradle version storage linked only to selected project wrappers. Standard AVD metadata does not establish a last launch; timestamp evidence is not an unused verdict.

The menu-bar monitor can display RAM or available storage. Pressure colors use the actual macOS signal, swap details are optional, and unavailable values are not presented as measured zero. Settings About reads the actual bundle version/build. Native toolbar, icon, Reduce Motion, and Reduce Transparency acceptance must be checked in the final artifact.

## Direct edition

The direct edition supports broader known-location scans, an explicit normal app-quit review, an optional installed local model runtime, and a separate worktree review. Settings offers an explicit shortcut to macOS Full Disk Access; the user must enable access. Local builds are ad hoc signed unless a publisher identity is supplied. The direct release 1.7.0 (9) built successfully and passed strict `codesign` verification; `outputs/Room-macOS.zip` was refreshed. This establishes the local artifact and signature check, not notarization or a public release. Public direct distribution still requires the appropriate signing/notarization and release handoff.

## Mac App Store edition

Bundle identifier: `com.merkost.room`. App Store Connect record: `6825292305`; current recorded state is Prepare for Submission. This is not an upload receipt or published release.

The Store edition is free, with no advertising or in-app purchases. It is sandboxed and uses native user-selected read-only folder access, optionally remembered for the home folder and accessible descendants. It excludes other-app termination, external model executables, and the direct worktree review/cleanup flow.

Store cleanup is restricted to supported npm SHA512-addressed immutable download-object files modified more than 30 days ago, verified through bounded local content reads. A candidate still needs exact reviewed write access and identity/content revalidation. This is not proof of non-use: downloads can recur, active installs can retry, and offline installs can fail. npm index/tmp data, installed packages, and other process-guarded caches remain held. The sandbox cannot establish complete background-tool visibility. General Codex/Claude cache cleanup is not a Store feature.

Eligible moves use Trash and container-local recovery receipts. Restore requires the original parent approval and either an exact saved Trash-item scope or explicit approval of that exact item. Changed content and occupied destinations remain protected. Room never empties Trash, and Trash continues occupying space. Signed native move, Quit/relaunch, and Restore qualification for the npm exception is pending; fixture test evidence alone is insufficient.

## Qualification and publication

The current qualification logs record Store 166 tests in 20 suites passed (`work/room-native/store-test-verified.log`) and direct 181 tests in 20 suites passed (`work/room-native/direct-test-verified.log`). Focused App access and remembered-access tests also passed. A Store preview showed basic memory statistics and About. Fixture results and basic preview observations do not qualify the latest native toolbar/icon, Developer review, status-item interactions, analysis, or signed npm Trash/restart/Restore. Final native acceptance remains a release gate.

### Archive and export evidence

Native `xcodebuild` reported **ARCHIVE SUCCEEDED** for `/private/tmp/Room-Store-final/Room-release.xcarchive`. That archive includes the current SVG-derived icon/mark, repaired toolbar and header alignment. Store Info declares `ITSAppUsesNonExemptEncryption=false`; this declaration is not Apple approval of export-compliance answers.

The actual Apple Store export command was attempted and **failed with exit code 70**: `No Accounts`, no `Mac Installer Distribution` identity, and no provisioning profile for `com.merkost.room`. Native archive creation did not produce a distribution-signed Store export or accepted upload. The user has been asked to sign into the appropriate Xcode account so its team, identity and profile can be made available.

Final native interaction testing is currently blocked by the locked Mac; the unlock request is pending. The successful archive and earlier basic Memory/About preview do not establish latest native toolbar, permission, Developer, monitor, analysis, or npm Trash/restart/Restore acceptance.

### App Store Connect state

The final Description, Promotional Text and Keywords were saved from the current listing draft. Review contact and the no-sign-in answer were already saved; private contact values are not reproduced here. Free pricing is confirmed, and the authoritative Availability page saved **All Countries or Regions (175)**, with each entry **Available on App Release**. This is configured availability, not a live release.

All seven existing age-rating questionnaire steps were reviewed as No/None and not designed for Kids, with a calculated **4+** rating. Save was disabled because the answers were unchanged; Cancel preserved the existing settings. No new age-rating save is claimed.

Data Not Collected privacy answers were saved, but the final legally worded privacy Publish/attestation still awaits the user's confirmation at that action. Saved answers are not a completed privacy publication or App Review submission.

Before release:

1. Retain the current both-edition test evidence with the frozen candidate; rerun relevant checks if release code changes. Distinguish full suites from focused fixes and older direct runs.
2. Verify the actual signed sandboxed app: remembered read access, exact temporary write scopes, cancellation, npm Trash/receipt persistence, Quit/relaunch/Restore, conflict handling, local analysis/fallback, Developer evidence, menu-bar metrics, and the repaired toolbar at minimum/default window sizes.
3. Recapture and review the final native Store screenshots with non-private demonstration data. Existing historical layout studies are not final upload assets.
4. Align metadata, privacy inventory/manifest, public support/privacy pages, final version/build, publisher declarations, and reviewer notes with the actual qualified artifact.
5. Resolve the failed export through the correct Xcode account, distribution identity and provisioning profile; validate the resulting distribution export, then complete upload processing, App Review, and final live availability as separate steps. An accepted upload does not mean approval or publication.

The support and privacy pages are configured at `https://room.merkost.dev/support/` and `https://room.merkost.dev/privacy/`. Availability on the website must match the actual release state. No App Review approval or public Store release is established by this document.
