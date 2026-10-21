#if !ROOM_APP_STORE
import RoomCore
import SwiftUI

struct RoomAgentWorkView: View {
    @Bindable var model: AgentWorkModel
    let memoryReport: MemoryReport?
    @State private var sheet: AgentWorkSheet?
    @State private var queuedReview: AgentWorkItem?
    @State private var showingAllHistory = false

    private var isReading: Bool { model.isScanning || model.verifyingID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Worktrees").font(.system(size: 15, weight: .semibold))
                    Text("Link agent work to disk use and observed processes.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button { model.addProject() } label: {
                    Label("Add project", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)
                .disabled(model.isWorking || model.isScanning || model.verifyingID != nil)
                .accessibilityIdentifier("RoomAgentWorkAddProjectButton")

                Button {
                    if isReading { model.stop() } else { model.scan() }
                } label: {
                    Label(isReading ? "Stop" : "Scan worktrees", systemImage: isReading ? "stop.fill" : "magnifyingglass")
                }
                .buttonStyle(.glassProminent)
                .tint(Color(red: 0.60, green: 0.79, blue: 0.91))
                .disabled(model.isWorking)
                .accessibilityIdentifier("RoomAgentWorkScanButton")
            }
            .font(.system(size: 13))

            if model.isScanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    if let progress = model.progress {
                        Text("\(progress.inspectedCount) inspected")
                            .fixedSize()
                        Text(progress.currentPath)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .help(progress.currentPath)
                    } else {
                        Text("Reading local worktree metadata…")
                    }
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }

            if model.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isScanning ? "Looking for local agent work." : "Bring work into view.")
                        .font(.system(size: 15, weight: .medium))
                    Text("Scan agent worktrees or add a repository. Remote verification runs only when you request it.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(model.items) { item in
                        AgentWorkRow(item: item, verifying: model.verifyingID == item.id,
                                     disabled: model.isWorking || model.isScanning || model.verifyingID != nil,
                                     inspect: { sheet = .details(item) },
                                     verify: { model.verify(item) },
                                     review: { sheet = .cleanup(item) })
                    }
                }
            }

            if let report = model.report {
                if report.isPartial || report.cancelled {
                    Label("Partial scan. Unverified work stays held.", systemImage: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if !report.issues.isEmpty {
                    DisclosureGroup("\(report.issues.count) scan \(report.issues.count == 1 ? "note" : "notes")") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(report.issues.prefix(20))) { issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.message).font(.system(size: 13))
                                    Text(issue.url.path)
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                        .lineLimit(2).truncationMode(.middle)
                                        .help(issue.url.path)
                                }
                            }
                            if report.issues.count > 20 {
                                Text("\(report.issues.count - 20) additional \(report.issues.count - 20 == 1 ? "note" : "notes")")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.system(size: 13))
                }
            }

            if !model.receipts.isEmpty { history }
            AgentWorkFeedback(model: model)
        }
        .task { await model.refreshHistory() }
        .sheet(item: $sheet, onDismiss: sheetDismissed) { selected in
            switch selected {
            case .details(let item):
                AgentWorkDetailSheet(model: model, initialItem: item, memoryReport: memoryReport) { current in
                    queuedReview = current
                    sheet = nil
                }
            case .cleanup(let item):
                AgentWorkCleanupSheet(model: model, item: item)
            case .restore(let receipt):
                AgentWorkRestoreSheet(model: model, receipt: receipt)
            }
        }
    }

    private var history: some View {
        DisclosureGroup("Worktree activity · \(model.receipts.count)") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(model.receipts.prefix(showingAllHistory ? .max : 10))) { receipt in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.originalURL.lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1).truncationMode(.middle)
                            Text(receiptStatus(receipt.status))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(receipt.detail)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if receipt.status == .trashed || receipt.status == .needsAttention {
                            Button("Restore") { sheet = .restore(receipt) }
                                .buttonStyle(.glass)
                                .disabled(model.isWorking || model.isScanning)
                                .accessibilityLabel("Restore \(receipt.originalURL.lastPathComponent)")
                        }
                    }
                }
                if model.receipts.count > 10 {
                    Button(showingAllHistory ? "Show fewer" : "Show all \(model.receipts.count) records") {
                        showingAllHistory.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("RoomAgentWorkHistoryExpansion")
                }
            }
            .padding(.top, 12)
        }
        .font(.system(size: 13))
    }

    private func sheetDismissed() {
        model.discardReview()
        if let next = queuedReview {
            queuedReview = nil
            sheet = .cleanup(next)
        }
    }
}

private struct AgentWorkRow: View {
    let item: AgentWorkItem
    let verifying: Bool
    let disabled: Bool
    let inspect: () -> Void
    let verify: () -> Void
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: inspect) {
                HStack(spacing: 14) {
                    Image(systemName: ownerSymbol(item.owner))
                        .font(.system(size: 20)).foregroundStyle(.secondary)
                        .frame(width: 25)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1).truncationMode(.middle)
                        Text("\(ownerTitle(item.owner)) · \(branchTitle(item))")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(item.isPartial ? "≥ " : "")\(RoomFormat.bytes(item.allocatedBytes))")
                            .font(.system(size: 14, weight: .medium)).monospacedDigit()
                        Text("\(item.processIDs.count) linked \(item.processIDs.count == 1 ? "PID" : "PIDs")")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.url.path)
            .accessibilityLabel("Inspect worktree \(item.title), \(RoomFormat.bytes(item.allocatedBytes)), \(item.processIDs.count) linked \(item.processIDs.count == 1 ? "process" : "processes")")

            HStack(spacing: 10) {
                if verifying { ProgressView().controlSize(.mini) }
                Text(verifying ? "Verifying remote…" : verificationTitle(item.pushVerification))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if !item.heldReasons.isEmpty {
                    Text("· \(item.heldReasons.count) \(item.heldReasons.count == 1 ? "hold" : "holds")")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if item.canReviewForCleanup {
                    Button("Review tree", action: review)
                        .buttonStyle(.glass)
                        .disabled(disabled)
                } else {
                    Button("Verify remote", action: verify)
                        .buttonStyle(.glass)
                        .disabled(disabled)
                        .help("Contact this checkout’s configured remote to verify its current commit. This does not mark the work finished.")
                }
            }
            .font(.system(size: 12))
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoomSheetHeading(title: item.title, subtitle: "\(ownerTitle(item.owner)) · \(branchTitle(item))")
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Text("\(item.isPartial ? "≥ " : "")\(RoomFormat.bytes(item.allocatedBytes))")
                    .font(RoomType.figure(34))
                Text("allocated on disk").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    remoteProof
                    heldReasons
                    processLinks
                    DisclosureGroup("Git and locations") {
                        VStack(alignment: .leading, spacing: 12) {
                            AgentWorkPath(label: "Checkout", url: item.url)
                            if let url = item.repositoryURL { AgentWorkPath(label: "Repository", url: url) }
                            if let url = item.gitAdminURL { AgentWorkPath(label: "Git metadata", url: url) }
                            if let head = item.head {
                                Text("HEAD \(head)").font(.system(size: 12)).textSelection(.enabled)
                            }
                            Text("\(item.changedCount) changed · \(item.untrackedCount) untracked · \(item.ignoredCount) ignored")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            if let activity = item.lastActivityAt {
                                Text("Last activity \(activity, style: .relative) ago. Age does not establish that work is finished.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .font(.system(size: 13, weight: .medium))
                    AgentWorkFeedback(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 350)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Button("Done") { dismiss() }
                    .buttonStyle(.glass).keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                Spacer()
                if item.canReviewForCleanup {
                    Button("Review this tree") { review(item) }
                        .buttonStyle(.glassProminent)
                        .disabled(model.isWorking || model.isScanning || model.verifyingID != nil)
                }
            }
            .controlSize(.large)
        }
        .padding(28).frame(width: 620)
        .interactiveDismissDisabled(model.isWorking)
    }

    private var remoteProof: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verificationTitle(item.pushVerification))
                .font(.system(size: 14, weight: .medium))
            Text(item.pushVerification.detail)
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let checked = item.pushVerification.checkedAt {
                Text("Checked \(checked, style: .relative) ago")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button(model.verifyingID == item.id ? "Stop verification" : "Verify remote") {
                if model.verifyingID == item.id { model.stop() } else { model.verify(item) }
            }
                .buttonStyle(.glass)
                .disabled(model.isWorking || model.isScanning || (model.verifyingID != nil && model.verifyingID != item.id))
            Text(isLocalProof(item.pushVerification)
                 ? "This proof checks a local remote and does not establish an off-device backup. A verified commit does not show that work is finished."
                 : "Verification explicitly contacts the configured remote. A verified commit does not show that work is finished.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var heldReasons: some View {
        if !item.heldReasons.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What holds this tree").font(.system(size: 14, weight: .medium))
                ForEach(Array(item.heldReasons.enumerated()), id: \.offset) { reason in
                    Label(reason.element, systemImage: "lock.shield")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var processLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observed processes").font(.system(size: 14, weight: .medium))
            if item.processIDs.isEmpty {
                Text("No process link was observed. This does not prove the work is finished.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ForEach(Array(Set(item.processIDs)).sorted(), id: \.self) { pid in
                    let association = associations.first { $0.processID == pid }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(association?.processName ?? "Process") · PID \(pid)")
                            .font(.system(size: 13, weight: .medium))
                        Text(association?.detail ?? "Association details unavailable.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                Text("Process links come from the worktree scan. The memory sample is separate; Room does not assign a RAM total to this worktree.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
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
        prepared && confirmsFinished && model.reviewLocations.count == 2 && model.allLocationsGranted && !model.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoomSheetHeading(title: "Review one worktree.", subtitle: item.title)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(RoomFormat.bytes(item.allocatedBytes)).font(RoomType.figure(34))
                Text("to move to Trash").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AgentWorkPath(label: "Checkout", url: item.url)
                    Text("The verified remote commit and local checks are revalidated before this checkout moves. Its linked Git metadata is retained for recovery.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("I’ve finished this worktree and no longer need this checkout.", isOn: $confirmsFinished)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                        .disabled(model.isWorking || !prepared)
                        .accessibilityIdentifier("RoomAgentWorkFinishedAttestation")

                    if needsRecheck {
                        Button("Review again") { Task { await checkReview() } }
                            .buttonStyle(.glass)
                            .disabled(model.isWorking)
                            .accessibilityIdentifier("RoomAgentWorkReviewAgainButton")
                    } else if !prepared {
                        ProgressView("Checking review…").controlSize(.small)
                    } else {
                        AgentWorkPermissions(model: model, restoring: false)
                    }
                    AgentWorkFeedback(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 340)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass).keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button {
                    Task {
                        if await model.moveToTrash(item, confirmsFinished: confirmsFinished) {
                            dismiss()
                        } else {
                            prepared = false
                            confirmsFinished = false
                            needsRecheck = true
                        }
                    }
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canMove)
                .accessibilityIdentifier("RoomAgentWorkMoveToTrashButton")
            }
            .controlSize(.large)
        }
        .padding(28).frame(width: 620)
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
        prepared && model.reviewLocations.count == 2 && model.allLocationsGranted && !model.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RoomSheetHeading(title: "Restore this worktree.", subtitle: receipt.originalURL.lastPathComponent)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AgentWorkPath(label: "Restore to", url: receipt.originalURL)
                    Text("Room checks the checkout and its Git metadata before restoring. A new or changed destination is kept; it is never overwritten.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if needsRecheck {
                        Button("Check again") { Task { await checkRecovery() } }
                            .buttonStyle(.glass)
                            .disabled(model.isWorking)
                            .accessibilityIdentifier("RoomAgentWorkRestoreCheckAgainButton")
                    } else if !prepared {
                        ProgressView("Checking recovery…").controlSize(.small)
                    } else {
                        AgentWorkPermissions(model: model, restoring: true)
                    }
                    AgentWorkFeedback(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 340)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass).keyboardShortcut(.cancelAction)
                    .disabled(model.isWorking)
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button("Restore") {
                    Task {
                        if await model.restoreReviewed(receipt) {
                            dismiss()
                        } else {
                            prepared = false
                            needsRecheck = true
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRestore)
                .accessibilityIdentifier("RoomAgentWorkRestoreButton")
            }
            .controlSize(.large)
        }
        .padding(28).frame(width: 620)
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
            Text("Folder access").font(.system(size: 14, weight: .medium))
            Text("Allowing access does not move files.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(Array(model.reviewLocations.enumerated()), id: \.element.path) { indexed in
                let url = indexed.element
                let isGitMetadata = indexed.offset > 0
                HStack(alignment: .center, spacing: 16) {
                    AgentWorkPath(label: isGitMetadata ? "Git metadata" : restoring ? "Destination parent" : "Checkout", url: url)
                    Spacer(minLength: 0)
                    if model.grantedLocations.contains(url.path) {
                        Label("Allowed", systemImage: "checkmark.circle")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize()
                    } else {
                        Button(isGitMetadata ? "Allow Git metadata" : restoring ? "Allow destination parent" : "Allow checkout") {
                            Task { await model.allow(url) }
                        }
                        .buttonStyle(.glass)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(url.path)
                .font(.system(size: 12))
                .lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
                .help(url.path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentWorkFeedback: View {
    @Bindable var model: AgentWorkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.statusMessage, !message.isEmpty {
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = model.errorMessage, !message.isEmpty {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 13)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum AgentWorkSheet: Identifiable {
    case details(AgentWorkItem)
    case cleanup(AgentWorkItem)
    case restore(AgentWorkReceipt)

    var id: String {
        switch self {
        case .details(let item): "details:\(item.id)"
        case .cleanup(let item): "cleanup:\(item.id)"
        case .restore(let receipt): "restore:\(receipt.id)"
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
