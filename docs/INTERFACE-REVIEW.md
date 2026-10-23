# Interface system candidate

As of **23 October 2026**, this work targets unreleased **Direct 1.9.0 (14)** and **Store 1.1.0 (6)**. It describes the current source candidate. The [release record](RELEASE.md) retains the separate, dated evidence for Store 1.0.0 (5) and Direct 1.8.0 (13).

## Shared native foundation

The extracted design system provides semantic typography, spacing, surfaces, motion, headers, groups, metrics, paths, feedback, empty states, action styles, and review sheets. San Francisco roles run from 24-point page titles through 13-point body text and 11-point metadata; numeric metrics keep their value and unit together. Spacing follows a 4/8/12/16/24/28-point scale.

Native Liquid Glass controls and navigation sit above semantic data surfaces. The upright C4 soft-pocket mark remains shared. Native focus, shortcuts, mixed-state checkboxes, full-path accessibility labels, and system motion/transparency preferences are retained. Review sheets share fixed headings and action footers; cache-review feedback remains beside the actions.

## Screen changes

| Surface | Candidate behavior |
|---|---|
| Navigation and onboarding | Adaptive navigation, destination scroll reset, and a first-task choice for storage, memory, disk mapping, or developer resources. |
| Clean and source details | Explicit Scan/Stop, Quick/Full scope, independent filters, eligible-item checkboxes, and selected counts and bytes. Held items remain inspectable. |
| Review and folder access | Shared cleanup/restore layouts, visible retry errors, exact temporary Store write approvals, and explicit Renew/Forget for unavailable saved access. |
| Disk Map and analysis | Independent hidden/category/search/sort controls, measured folder graphics, persistent Back/Forward snapshots, and a handoff to Clean for known sources. Analysis remains advisory. |
| Memory and menu bar | Actual recent samples, pressure-led guidance, process context, RAM/storage choice, sample freshness, and configurable pressure/swap details. A reading does not promise recoverable RAM. |
| Developer | Fair scan budgets across selected Android, Gradle, and project roles; exact saved-folder reuse; version-to-wrapper references; partial totals; and resource-specific Finder actions. Direct samples activity; Store leaves unavailable observation unknown. This view remains read-only. |
| Agent Work — Direct | Separate discovery, owner/status filters, remote verification, explicit holds, finished-work review, and recovery through Activity. Cancelled scans offer inspection and Rescan before verification. Missing process evidence or an old date does not establish non-use. |
| Activity and settings | Cache/worktree history filters in Direct, receipt-based restore, consistent settings, System appearance by default, and About/version information from the bundle. Store retains cache history only. |

Direct's memory action requests a normal app quit after an explicit identity-bound review. Store provides monitoring and suggestions. Neither edition automatically closes running apps to optimize a reading.

## Selection, Stop, and recovery

Cleanup binds to selected eligible item IDs. Replacing an item with another of equal size invalidates its Store write review. Changing the next scan scope keeps earlier measurements labeled and prevents cleanup until the scopes agree. Stop keeps partial evidence without cleanup authority, including a cancellation arriving during the final configuration handoff. Automatic rescans after cleanup or restore leave selection empty.

Store's **Next npm batch** advances bounded discovery within the approved physical scope. Each batch replaces the results and selection; its total is not cumulative or proof that every cache was scanned. Receipt recovery reconstructs exact approved original parents independently of the discovery page. Existing content, identity, scope, and destination checks still govern every move or restore.

## Regression coverage and qualification

Source regressions cover [granular selection and grant retries](../Tests/RoomAppTests/RoomViewModelTests.swift), [late Stop](../Tests/RoomAppTests/RoomScanCancellationTests.swift), [navigation and asynchronous policy changes](../Tests/RoomAppTests/RoomDiskNavigationTests.swift), and [npm continuation and recovery](../Tests/RoomCoreTests/StoreNPMContinuationTests.swift). Additional tests cover unavailable access renewal, actual memory history, and developer-role fairness.

On **23 October 2026**, sequential full suites passed **222 Direct tests in 30 suites** and **219 Store tests in 31 suites**. Both optimized builds passed. All 49 Swift source files received full-body review, including computed views and conditional editions; inspection is separate from runtime execution coverage.

The latest regressions also cover [saved Developer access reuse](../Tests/RoomAppTests/RoomDeveloperAccessReuseTests.swift), [Agent verification after Stop](../Tests/RoomAppTests/AgentWorkVerificationTests.swift), [Store grant removal during a scan](../Tests/RoomAppTests/RoomStoreGrantRevocationTests.swift), and [incomplete agent directory reads](../Tests/RoomCoreTests/AgentDirectoryReadTests.swift). Changed or unreadable resources retain partial status and cannot acquire cleanup authority from incomplete inspection.

Native acceptance remains pending for the latest candidate, including minimum-window layout, keyboard and accessibility behavior, appearance and reduced motion, menu-bar interactions, and exact permission/recovery flows. The Mac must be unlocked to finish those checks. Automated tests and earlier native checks do not establish a new production-signed release, upload, submission, or review outcome.

## Suggested next additions

- A version-to-project graph for Gradle and Android resources, with explicit unknown references.
- Comparable storage snapshots that distinguish measured changes from different scan scopes.
- A redacted scan summary for support, with a preview before export.

These are proposals, separate from the implemented candidate above.
