#if !ROOM_APP_STORE
import AppKit
import RoomCore
import SwiftUI

struct RoomAgentWorkView: View {
    @Bindable var model: AgentWorkModel
    let memoryReport: MemoryReport?
    let onShowActivity: () -> Void
    @State private var sheet: AgentWorkSheet?
    @State private var queuedReview: AgentWorkItem?
    @State private var query = ""
    @State private var ownerFilter = AgentWorkOwnerFilter.all
    @State private var reviewFilter = AgentWorkReviewFilter.all

    private var isReading: Bool { model.isScanning || model.verifyingID != nil }
    private var matchingItems: [AgentWorkItem] {
        model.items.filter { item in
            ownerFilter.includes(item.owner) && reviewFilter.includes(item) &&
            (query.isEmpty || (item.title + " " + item.url.path + " " + branchTitle(item)).localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.section) {
            RoomPageHeader(title: "Agent work", subtitle: "Worktrees, remote proof, and observed process activity.") {
                HStack(spacing: RoomSpace.compact) {
                    Button { model.addProject() } label: { Label("Add project", systemImage: "folder.badge.plus") }
                        .roomAction(.secondary).disabled(model.isWorking || isReading)
                        .accessibilityIdentifier("RoomAgentWorkAddProjectButton")
                    Button {
                        if isReading { model.stop() } else { model.scan() }
                    } label: { Label(isReading ? "Stop" : model.report == nil ? "Scan worktrees" : "Rescan", systemImage: isReading ? "stop.fill" : "magnifyingglass") }
                        .roomAction(.primary).disabled(model.isWorking)
                        .accessibilityIdentifier("RoomAgentWorkScanButton")
                        .keyboardShortcut("r", modifiers: .command)
                }.controlSize(.large)
            }
            if model.isScanning {
                HStack(spacing: RoomSpace.compact) {
                    ProgressView().controlSize(.small)
                    if let progress = model.progress {
                        Text("\(progress.inspectedCount) inspected").font(RoomTypography.caption).fixedSize()
                        Text(progress.currentPath).font(RoomTypography.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).help(progress.currentPath)
                    } else { Text("Reading local worktree metadata…").font(RoomTypography.body) }
                }.accessibilityElement(children: .combine)
            }
            if model.items.isEmpty {
                RoomEmptyState(title: model.isScanning ? "Looking for agent work" : "Bring work into view", message: "Scan local agent worktrees or add a repository. Remote checks run only when you request them.", systemImage: "point.3.connected.trianglepath.dotted")
            } else {
                filterBar
                RoomSectionHeader(title: "Worktrees", detail: "\(matchingItems.count) of \(model.items.count)")
                if matchingItems.isEmpty {
                    RoomEmptyState(title: "No matching worktrees", message: "Try another owner, status, or search.", systemImage: "line.3.horizontal.decrease")
                } else {
                    LazyVStack(spacing: RoomSpace.compact) {
                        ForEach(matchingItems) { item in
                            AgentWorkRow(item: item, verifying: model.verifyingID == item.id,
                                         disabled: model.isWorking || isReading,
                                         verificationUnavailableReason: model.verificationUnavailableReason(for: item),
                                         inspect: { sheet = .details(item) }, verify: { model.verify(item) },
                                         review: { sheet = .cleanup(item) })
                        }
                    }
                }
            }
            if let report = model.report {
                if report.isPartial || report.cancelled {
                    RoomStatusNotice(message: "Partial scan. Unverified work stays held.")
                }
                if !report.issues.isEmpty {
                    DisclosureGroup("\(report.issues.count) scan \(report.issues.count == 1 ? "note" : "notes")") {
                        LazyVStack(alignment: .leading, spacing: RoomSpace.standard) {
                            ForEach(report.issues) { issue in
                                VStack(alignment: .leading, spacing: RoomSpace.micro) {
                                    Text(issue.message).font(RoomTypography.body)
                                    RoomPathLabel(path: issue.url.path)
                                }
                            }
                        }.padding(.top, RoomSpace.compact)
                    }.font(RoomTypography.bodyEmphasis)
                }
            }
            HStack(spacing: RoomSpace.standard) {
                if let report = model.report {
                    Text("Scanned \(report.scannedAt, style: .relative) ago").font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onShowActivity) { Label("View Activity", systemImage: "clock.arrow.circlepath") }
                    .roomAction(.secondary).accessibilityIdentifier("RoomAgentWorkShowActivity")
            }
            AgentWorkFeedback(model: model)
        }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { selected in
            switch selected {
            case .details(let item):
                AgentWorkDetailSheet(model: model, initialItem: item, memoryReport: memoryReport) { current in
                    queuedReview = current
                    sheet = nil
                }
            case .cleanup(let item): AgentWorkCleanupSheet(model: model, item: item)
            }
        }
    }

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomSpace.compact) { search; ownerPicker; eligibilityPicker }
            VStack(alignment: .leading, spacing: RoomSpace.compact) {
                search
                HStack(spacing: RoomSpace.compact) { ownerPicker; eligibilityPicker }
            }
        }
    }
    private var search: some View {
        TextField("Find a worktree", text: $query).textFieldStyle(.roundedBorder)
            .frame(width: 220).accessibilityLabel("Find a worktree")
    }
    private var ownerPicker: some View {
        Picker("Owner", selection: $ownerFilter) {
            ForEach(AgentWorkOwnerFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu).frame(width: 150)
    }
    private var eligibilityPicker: some View {
        Picker("Review status", selection: $reviewFilter) {
            ForEach(AgentWorkReviewFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
            .accessibilityLabel("Worktree review status")
    }
    private func sheetDismissed() {
        model.discardReview()
        if let next = queuedReview { queuedReview = nil; sheet = .cleanup(next) }
    }
}

/// Recovery is available from Activity itself, independent of Memory or a scan.
struct RoomAgentHistoryView: View {
    @Bindable var model: AgentWorkModel
    @State private var restoreReview: AgentWorkReceipt?

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.standard) {
            RoomSectionHeader(title: "Worktrees", detail: "\(model.receipts.count)")
            if model.receipts.isEmpty {
                RoomEmptyState(title: "No worktree activity", message: "Reviewed worktree moves and recovery records appear here.", systemImage: "point.3.connected.trianglepath.dotted")
            } else {
                LazyVStack(alignment: .leading, spacing: RoomSpace.standard) {
                    ForEach(model.receipts) { receipt in
                        RoomContentGroup {
                            HStack(alignment: .top, spacing: RoomSpace.standard) {
                                Image(systemName: receipt.status == .restored ? "arrow.uturn.backward" : "folder")
                                    .font(.system(size: 21)).foregroundStyle(.secondary).frame(width: 30).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: RoomSpace.micro) {
                                    Text(receipt.originalURL.lastPathComponent).font(RoomTypography.bodyEmphasis)
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                                    Text(receiptStatus(receipt.status)).font(RoomTypography.captionEmphasis)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if receipt.status == .trashed || receipt.status == .needsAttention {
                                    Button("Restore") { restoreReview = receipt }.roomAction(.secondary)
                                        .disabled(model.isWorking || model.isScanning || model.verifyingID != nil)
                                        .accessibilityLabel("Restore \(receipt.originalURL.lastPathComponent)")
                                }
                            }
                            Text(receipt.detail).font(RoomTypography.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("Locations & recovery") {
                                VStack(alignment: .leading, spacing: RoomSpace.compact) {
                                    RoomPathLabel(path: receipt.originalURL.path, label: "Original checkout")
                                    if let trash = receipt.trashURL { RoomPathLabel(path: trash.path, label: "Recorded Trash item") }
                                    RoomPathLabel(path: receipt.adminURL.path, label: "Git metadata")
                                }.padding(.top, RoomSpace.compact)
                            }.font(RoomTypography.caption)
                        }
                    }
                }
            }
            AgentWorkFeedback(model: model)
        }
        .task { await model.refreshHistory() }
        .sheet(item: $restoreReview, onDismiss: { model.discardReview() }) { receipt in
            AgentWorkRestoreSheet(model: model, receipt: receipt)
        }
    }
}

private enum AgentWorkOwnerFilter: String, CaseIterable {
    case all = "All owners", codex = "Codex", claude = "Claude", project = "Projects"
    func includes(_ owner: AgentWorkOwner) -> Bool {
        switch self { case .all: true; case .codex: owner == .codex; case .claude: owner == .claude; case .project: owner == .project }
    }
}
private enum AgentWorkReviewFilter: String, CaseIterable {
    case all = "All", ready = "Ready", held = "Held"
    func includes(_ item: AgentWorkItem) -> Bool {
        let ready = item.canReviewForCleanup && hasCurrentRemoteProof(item)
        return switch self { case .all: true; case .ready: ready; case .held: !ready }
    }
}

private struct AgentWorkRow: View {
    let item: AgentWorkItem
    let verifying: Bool
    let disabled: Bool
    let verificationUnavailableReason: String?
    let inspect: () -> Void
    let verify: () -> Void
    let review: () -> Void

    var body: some View {
        RoomContentGroup {
            Button(action: inspect) {
                HStack(spacing: RoomSpace.standard) {
                    Image(systemName: ownerSymbol(item.owner)).font(.system(size: 20)).foregroundStyle(.secondary)
                        .frame(width: 26).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: RoomSpace.micro) {
                        Text(item.title).font(RoomTypography.bodyEmphasis).foregroundStyle(.primary)
                            .lineLimit(1).truncationMode(.middle)
                        Text("\(ownerTitle(item.owner)) · \(branchTitle(item))")
                            .font(RoomTypography.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: RoomSpace.micro) {
                        Text("\(item.isPartial ? "≥ " : "")\(RoomFormat.bytes(item.allocatedBytes))")
                            .font(RoomTypography.bodyEmphasis).monospacedDigit()
                        Text("\(item.processIDs.count) linked \(item.processIDs.count == 1 ? "process" : "processes")")
                            .font(RoomTypography.caption).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.right").font(RoomTypography.meta).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }
            .roomAction(.quiet).help(item.url.path)
            .accessibilityLabel("Inspect worktree \(item.title), \(item.isPartial ? "at least " : "")\(RoomFormat.bytes(item.allocatedBytes)), \(item.processIDs.count) linked \(item.processIDs.count == 1 ? "process" : "processes")")

            HStack(spacing: RoomSpace.compact) {
                if verifying { ProgressView().controlSize(.mini) }
                Label(verifying ? "Verifying remote…" : verificationUnavailableReason == nil ? proofSummary(item) : "Rescan needed",
                      systemImage: verificationUnavailableReason != nil ? "arrow.clockwise" : hasCurrentRemoteProof(item) ? "checkmark.shield" : "network")
                    .font(RoomTypography.caption).foregroundStyle(.secondary)
                    .help(verificationUnavailableReason ?? item.pushVerification.detail)
                if !item.heldReasons.isEmpty {
                    Text("\(item.heldReasons.count) \(item.heldReasons.count == 1 ? "hold" : "holds")")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: RoomSpace.compact)
                if verificationUnavailableReason != nil {
                    Button("Inspect", action: inspect).roomAction(.primary).disabled(disabled)
                } else if item.canReviewForCleanup && hasCurrentRemoteProof(item) {
                    Button("Review tree", action: review).roomAction(.primary).disabled(disabled)
                } else if hasCurrentRemoteProof(item) {
                    Button("Review holds", action: inspect).roomAction(.primary).disabled(disabled)
                } else {
                    Button("Verify remote", action: verify).roomAction(.primary).disabled(disabled)
                        .help("Check the configured remote for this checkout’s current commit. Verification does not mark work finished.")
                }
            }
        }
    }
}

private struct AgentWorkDetailSheet: View {
    @Bindable var model: AgentWorkModel
    let initialItem: AgentWorkItem
    let memoryReport: MemoryReport?
    let review: (AgentWorkItem) -> Void
    @Environment(\.dismiss) private var dismiss

    private var item: AgentWorkItem { model.items.first { $0.id == initialItem.id } ?? initialItem }
    private var associations: [AgentWorkProcessAssociation] {
        model.report?.processAssociations.filter { $0.worktreeID == item.id } ?? []
    }
    private var canReviewTree: Bool {
        model.verificationUnavailableReason(for: item) == nil && item.canReviewForCleanup && hasCurrentRemoteProof(item)
    }

    var body: some View {
        RoomSheetLayout(title: item.title, subtitle: "\(ownerTitle(item.owner)) · \(branchTitle(item))", width: 620, maxContentHeight: 390) {
            RoomMetric(label: "Allocated on disk", bytes: item.allocatedBytes, maximumSize: 34, lowerBound: item.isPartial)
            heldReasons
            remoteProof
            processLinks
            DisclosureGroup("Git and locations") {
                VStack(alignment: .leading, spacing: RoomSpace.compact) {
                    RoomPathLabel(path: item.url.path, label: "Checkout")
                    if let url = item.repositoryURL { RoomPathLabel(path: url.path, label: "Repository") }
                    if let url = item.gitAdminURL { RoomPathLabel(path: url.path, label: "Git metadata") }
                    if let head = item.head { Text("HEAD \(head)").font(RoomTypography.caption).textSelection(.enabled) }
                    Text("\(item.changedCount) changed · \(item.untrackedCount) untracked · \(item.ignoredCount) ignored")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                    if let activity = item.lastActivityAt {
                        Text("Last activity \(activity, style: .relative) ago. Age does not show that work is finished.")
                            .font(RoomTypography.caption).foregroundStyle(.secondary)
                    }
                }.padding(.top, RoomSpace.compact)
            }.font(RoomTypography.bodyEmphasis)
            AgentWorkFeedback(model: model)
        } actions: {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: { Label("Show in Finder", systemImage: "folder") }
                .roomAction(.secondary).disabled(model.isWorking)
            Spacer()
            if canReviewTree {
                Button("Done") { dismiss() }.roomAction(.secondary).keyboardShortcut(.cancelAction).disabled(model.isWorking)
                Button("Review tree") { review(item) }.roomAction(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking || model.isScanning || model.verifyingID != nil)
            } else {
                Button("Done") { dismiss() }.roomAction(.primary).keyboardShortcut(.defaultAction).disabled(model.isWorking)
            }
        }
        .interactiveDismissDisabled(model.isWorking)
    }

    private var remoteProof: some View {
        VStack(alignment: .leading, spacing: RoomSpace.compact) {
            if let reason = model.verificationUnavailableReason(for: item) {
                RoomSectionHeader(title: "Remote proof", detail: "Rescan needed")
                RoomStatusNotice(message: reason, systemImage: "arrow.clockwise")
                Button("Rescan worktrees") { dismiss(); model.scan() }
                    .roomAction(.primary)
                    .disabled(model.isWorking || model.isScanning || model.verifyingID != nil)
                    .accessibilityIdentifier("RoomAgentWorkDetailRescanButton")
            } else {
                RoomSectionHeader(title: "Remote proof", detail: hasCurrentRemoteProof(item) ? verificationTitle(item.pushVerification) : "Check needed")
                Text(item.pushVerification.detail).font(RoomTypography.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let checked = item.pushVerification.checkedAt {
                    Text("Checked \(checked, style: .relative) ago").font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                Button(model.verifyingID == item.id ? "Stop verification" : hasCurrentRemoteProof(item) ? "Check remote again" : "Verify remote") {
                    if model.verifyingID == item.id { model.stop() } else { model.verify(item) }
                }
                .roomAction(hasCurrentRemoteProof(item) ? .secondary : .primary)
                .disabled(model.isWorking || model.isScanning || (model.verifyingID != nil && model.verifyingID != item.id))
                Text(isLocalProof(item.pushVerification)
                     ? "A local remote is not an off-device backup. A verified commit does not show that work is finished."
                     : "This check contacts the configured remote. A verified commit does not show that work is finished.")
                    .font(RoomTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var heldReasons: some View {
        if !item.heldReasons.isEmpty {
            VStack(alignment: .leading, spacing: RoomSpace.compact) {
                RoomSectionHeader(title: "Held for review", detail: "\(item.heldReasons.count)")
                ForEach(Array(item.heldReasons.enumerated()), id: \.offset) { reason in
                    RoomStatusNotice(message: reason.element, systemImage: "lock.shield")
                }
                Text("Resolve these conditions outside Room, then rescan. Held work cannot be selected for cleanup.")
                    .font(RoomTypography.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var processLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoomSectionHeader(title: "Observed processes")
            if item.processIDs.isEmpty {
                Text("No process link was observed. This does not prove the work is finished.")
                    .font(RoomTypography.body).foregroundStyle(.secondary)
            } else {
                ForEach(Array(Set(item.processIDs)).sorted(), id: \.self) { pid in
                    let association = associations.first { $0.processID == pid }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(association?.processName ?? "Process") · PID \(pid)")
                            .font(RoomTypography.bodyEmphasis)
                        Text(association?.detail ?? "Association details unavailable.")
                            .font(RoomTypography.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                Text("Process links come from the worktree scan. The memory sample is separate; Room does not assign a RAM total to this worktree.")
                    .font(RoomTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AgentWorkCleanupSheet: View {
    @Bindable var model: AgentWorkModel
    let item: AgentWorkItem
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsFinished = false
    @State private var prepared = false
    @State private var needsRecheck = false

    private var canMove: Bool {
        prepared && confirmsFinished && model.reviewLocations.count == 2 && model.allLocationsGranted && !model.isWorking && !model.isScanning && model.verifyingID == nil
    }

    var body: some View {
        RoomSheetLayout(title: "Review one worktree", subtitle: item.title, width: 620, maxContentHeight: 390) {
            RoomMetric(label: "To move to Trash", bytes: item.allocatedBytes, maximumSize: 34, lowerBound: item.isPartial)
            RoomPathLabel(path: item.url.path, label: "Checkout")
            RoomStatusNotice(message: "The remote commit and local checks are revalidated before this checkout moves. Linked Git metadata stays available for recovery.", systemImage: "checkmark.shield")
            Toggle("I’ve finished this worktree and no longer need this checkout.", isOn: $confirmsFinished)
                .toggleStyle(.checkbox).font(RoomTypography.body).disabled(model.isWorking || !prepared)
                .accessibilityIdentifier("RoomAgentWorkFinishedAttestation")
            if needsRecheck {
                Button("Review again") { Task { await checkReview() } }.roomAction(.secondary).disabled(model.isWorking)
                    .accessibilityIdentifier("RoomAgentWorkReviewAgainButton")
            } else if !prepared {
                ProgressView("Checking review…").controlSize(.small)
            } else { AgentWorkPermissions(model: model, restoring: false) }
            AgentWorkFeedback(model: model)
        } actions: {
            Button("Cancel") { dismiss() }.roomAction(.secondary).keyboardShortcut(.cancelAction).disabled(model.isWorking)
            Spacer()
            if model.isWorking { ProgressView().controlSize(.small) }
            Button {
                Task {
                    if await model.moveToTrash(item, confirmsFinished: confirmsFinished) { dismiss() }
                    else { prepared = false; confirmsFinished = false; needsRecheck = true }
                }
            } label: { Label(model.isWorking ? "Moving…" : "Move to Trash", systemImage: "trash") }
                .roomAction(.primary).keyboardShortcut(.defaultAction).disabled(!canMove)
                .accessibilityIdentifier("RoomAgentWorkMoveToTrashButton")
        }
        .interactiveDismissDisabled(model.isWorking)
        .task(id: item.id) { await checkReview() }
    }

    private func checkReview() async {
        prepared = false
        needsRecheck = false
        confirmsFinished = false
        await model.prepareReview(item)
        prepared = model.reviewLocations.count == 2
        needsRecheck = !prepared
    }
}

private struct AgentWorkRestoreSheet: View {
    @Bindable var model: AgentWorkModel
    let receipt: AgentWorkReceipt
    @Environment(\.dismiss) private var dismiss
    @State private var prepared = false
    @State private var needsRecheck = false

    private var canRestore: Bool {
        prepared && model.reviewLocations.count == 2 && model.allLocationsGranted && !model.isWorking && !model.isScanning && model.verifyingID == nil
    }

    var body: some View {
        RoomSheetLayout(title: "Restore worktree", subtitle: receipt.originalURL.lastPathComponent, width: 620) {
            RoomPathLabel(path: receipt.originalURL.path, label: "Restore to")
            RoomStatusNotice(message: "Room checks the checkout and its Git metadata before restoring. New or changed destinations are kept; nothing is overwritten.", systemImage: "arrow.uturn.backward")
            if needsRecheck {
                Button("Check again") { Task { await checkRecovery() } }.roomAction(.secondary).disabled(model.isWorking)
                    .accessibilityIdentifier("RoomAgentWorkRestoreCheckAgainButton")
            } else if !prepared {
                ProgressView("Checking recovery…").controlSize(.small)
            } else { AgentWorkPermissions(model: model, restoring: true) }
            AgentWorkFeedback(model: model)
        } actions: {
            Button("Cancel") { dismiss() }.roomAction(.secondary).keyboardShortcut(.cancelAction).disabled(model.isWorking)
            Spacer()
            if model.isWorking { ProgressView().controlSize(.small) }
            Button(model.isWorking ? "Restoring…" : "Restore") {
                Task {
                    if await model.restoreReviewed(receipt) { dismiss() }
                    else { prepared = false; needsRecheck = true }
                }
            }
            .roomAction(.primary).keyboardShortcut(.defaultAction).disabled(!canRestore)
            .accessibilityIdentifier("RoomAgentWorkRestoreButton")
        }
        .interactiveDismissDisabled(model.isWorking)
        .task(id: receipt.id) { await checkRecovery() }
    }

    private func checkRecovery() async {
        prepared = false
        needsRecheck = false
        await model.prepareRestore(receipt)
        prepared = model.reviewLocations.count == 2
        needsRecheck = !prepared
    }
}

private struct AgentWorkPermissions: View {
    @Bindable var model: AgentWorkModel
    let restoring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoomSectionHeader(title: "Folder access")
            Text("Allowing access does not move files.")
                .font(RoomTypography.caption).foregroundStyle(.secondary)
            ForEach(Array(model.reviewLocations.enumerated()), id: \.element.path) { indexed in
                let url = indexed.element
                let isGitMetadata = indexed.offset > 0
                HStack(alignment: .center, spacing: 16) {
                    AgentWorkPath(label: isGitMetadata ? "Git metadata" : restoring ? "Destination parent" : "Checkout", url: url)
                    Spacer(minLength: 0)
                    if model.grantedLocations.contains(url.path) {
                        Label("Allowed", systemImage: "checkmark.circle")
                            .font(RoomTypography.caption).foregroundStyle(.secondary)
                            .fixedSize()
                    } else {
                        Button(isGitMetadata ? "Allow Git metadata" : restoring ? "Allow destination parent" : "Allow checkout") {
                            Task { await model.allow(url) }
                        }
                        .roomAction(.secondary)
                        .disabled(model.isWorking)
                        .fixedSize()
                    }
                }
            }
        }
    }
}

private struct AgentWorkPath: View {
    let label: String
    let url: URL
    var body: some View { RoomPathLabel(path: url.path, label: label) }
}

private struct AgentWorkFeedback: View {
    @Bindable var model: AgentWorkModel
    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.small) {
            if let message = model.statusMessage, !message.isEmpty { RoomStatusNotice(message: message) }
            if let message = model.errorMessage, !message.isEmpty { RoomStatusNotice(message: message, tone: .error) }
        }
    }
}

private enum AgentWorkSheet: Identifiable {
    case details(AgentWorkItem)
    case cleanup(AgentWorkItem)

    var id: String {
        switch self {
        case .details(let item): "details:\(item.id)"
        case .cleanup(let item): "cleanup:\(item.id)"
        }
    }
}

private func ownerTitle(_ owner: AgentWorkOwner) -> String {
    switch owner { case .codex: "Codex"; case .claude: "Claude"; case .project: "Project" }
}

private func ownerSymbol(_ owner: AgentWorkOwner) -> String {
    switch owner { case .codex: "terminal"; case .claude: "sparkles"; case .project: "folder" }
}

private func branchTitle(_ item: AgentWorkItem) -> String {
    item.branch ?? (item.head == nil ? "Branch unavailable" : "Detached HEAD")
}

private func hasCurrentRemoteProof(_ item: AgentWorkItem) -> Bool {
    guard item.pushVerification.state == .verified, item.pushVerification.checkedAt != nil,
          let head = item.head, !head.isEmpty else { return false }
    return item.pushVerification.head == head
}

private func proofSummary(_ item: AgentWorkItem) -> String {
    item.pushVerification.state == .verified && !hasCurrentRemoteProof(item)
        ? "Verification needs refresh" : verificationTitle(item.pushVerification)
}

private func isLocalProof(_ verification: AgentWorkPushVerification) -> Bool {
    verification.remoteName?.hasPrefix("Local remote") == true
}

private func verificationTitle(_ verification: AgentWorkPushVerification) -> String {
    switch verification.state {
    case .notChecked: "Remote unchecked"
    case .verified: isLocalProof(verification) ? "Local remote verified" : "Remote verified"
    case .unavailable: "Remote unavailable"
    case .mismatch: "Remote differs"
    }
}

private func receiptStatus(_ status: AgentWorkReceiptStatus) -> String {
    switch status {
    case .pending: "Recovery record pending"
    case .trashed: "In Trash"
    case .restored: "Restored"
    case .failed: "Operation failed"
    case .needsAttention: "Recovery needs attention"
    }
}

#endif
