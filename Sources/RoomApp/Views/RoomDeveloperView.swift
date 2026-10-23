import AppKit
import RoomCore
import SwiftUI

/// A read-only resource review. Activity evidence never becomes a deletion rule.
struct RoomDeveloperView: View {
    @Bindable var model: RoomDeveloperModel
    var motion = RoomMotionPolicy()
    @State private var section = DeveloperSection.android
    @State private var showingAll = false
    @State private var showingNotes = false
    private enum DeveloperSection: String, CaseIterable { case android = "Android", gradle = "Gradle" }
    private var groups: [RoomGradleVersionGroup] { RoomDeveloperPresentation.groups(model.report?.gradleResources ?? []) }

    private var subtitle: String {
        if model.isScanning { return model.report == nil ? "Reading chosen folders." : "Reading again. The previous review remains below." }
        return "Devices, build versions, and the projects that reference them."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.section) {
            RoomPageHeader(title: "Developer resources", subtitle: subtitle) {
                HStack(spacing: RoomSpace.compact) {
                    addMenu
                    if !model.locations.isEmpty {
                        Button {
                            if model.isScanning { model.stop() } else { model.scan() }
                        } label: {
                            Label(model.isScanning ? "Stop scan" : model.report == nil ? "Scan resources" : "Rescan", systemImage: model.isScanning ? "stop.fill" : "magnifyingglass")
                        }
                        .buttonStyle(.glassProminent).controlSize(.large)
                        .disabled(!model.canScan)
                        .accessibilityIdentifier("RoomDeveloperScanButton")
                        .keyboardShortcut("r", modifiers: .command)
                    }
                }
            }

            if model.isChoosingFolder {
                ProgressView("Choose a folder in the macOS dialog…").controlSize(.small).font(RoomTypography.body)
            }

            if model.locations.isEmpty {
                emptyReview
            } else {
                RoomContentGroup {
                  DisclosureGroup("\(model.locations.count) \(model.locations.count == 1 ? "folder" : "folders") in this review") {
                    LazyVStack(spacing: RoomSpace.standard) {
                        ForEach(model.locations) { location in
                            HStack(spacing: 12) {
                                Image(systemName: location.role.symbol).frame(width: 20).foregroundStyle(.secondary)
                                RoomPathLabel(path: location.folder.url.path, label: location.role.title, lineLimit: 1)
                                revealButton(location.folder.url)
                                Button { model.remove(location) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.isScanning)
                                    .help("Remove from this review; saved folder access is managed in Settings")
                                    .accessibilityLabel("Remove \(location.folder.name) from developer review")
                            }
                        }
                    }.padding(.top, 12)
                  }
                  .font(RoomTypography.bodyEmphasis)
                }
            }

            if model.isScanning {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.progress).font(RoomTypography.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.vertical, 3)
            } else if !model.locations.isEmpty && model.report == nil {
                RoomStatusNotice(message: "Folders are ready. Scan to connect resources with their usage evidence.", systemImage: "checkmark.circle")
            }

            if let report = model.report {
                summary(report)
                Picker("Developer resource type", selection: $section) {
                    ForEach(DeveloperSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                .accessibilityIdentifier("RoomDeveloperSectionPicker")
                if section == .android { androidResources(report) }
                else { gradleResources(report) }
                if report.cancelled || report.isPartial {
                    RoomStatusNotice(message: report.cancelled ? "Scan stopped. These sizes are partial." : "Some locations could not be fully measured. Sizes marked ≥ are lower bounds.", tone: .warning)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Measured \(report.scannedAt.formatted(date: .omitted, time: .shortened))")
                    Spacer()
                    if !report.issues.isEmpty {
                        Button("\(report.issues.count) \(report.issues.count == 1 ? "note" : "notes")") { showingNotes = true }.buttonStyle(.plain)
                    }
                }.font(RoomTypography.caption).foregroundStyle(.secondary)
            }
        }
        .animation(motion.selection, value: section)
        .animation(motion.disclosure, value: showingAll)
        .onChange(of: section) { _, _ in showingAll = false }
        .alert("Couldn’t add that folder", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $showingNotes) {
            RoomScanIssuesSheet(issues: model.report?.issues.map { "\($0.url.path): \($0.message)" } ?? [])
        }
    }

    private var addMenu: some View {
        Menu {
            ForEach(RoomDeveloperFolderRole.allCases) { role in
                roleControl(role)
            }
        } label: { Label("Add folder", systemImage: "plus") }
        .menuStyle(.button).buttonStyle(.glass).controlSize(.large).fixedSize().font(RoomTypography.body)
        .disabled(model.isScanning || model.isChoosingFolder)
        .accessibilityIdentifier("RoomDeveloperAddFolder")
    }

    private var emptyReview: some View {
        RoomContentGroup {
            RoomEmptyState(title: "Connect storage to your work",
                           message: "Choose Android devices, a Gradle home, or projects to review. Only chosen folders are read.",
                           systemImage: "externaldrive.connected.to.line.below") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RoomSpace.compact) { setupButtons }
                    VStack(alignment: .leading, spacing: RoomSpace.compact) { setupButtons }
                }
            }
        }
    }

    private var setupButtons: some View {
        ForEach(RoomDeveloperFolderRole.allCases) { role in
            roleControl(role).menuStyle(.button).buttonStyle(.glass)
        }
    }

    @ViewBuilder private func roleControl(_ role: RoomDeveloperFolderRole, title: String? = nil) -> some View {
        let folders = model.reusableFolders(for: role)
        Group {
            if folders.isEmpty {
                Button { model.addFolder(role: role) } label: { Label(title ?? role.title, systemImage: role.symbol) }
            } else {
                Menu {
                    ForEach(folders) { folder in
                        Button { model.attach(role: role, to: folder.id) } label: {
                            Label((folder.url.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        }
                        .help(folder.url.path)
                        .accessibilityLabel("Use saved folder \(folder.url.path) for \(role.title)")
                        .accessibilityIdentifier("RoomDeveloperReuse-\(role.id)-\(folder.id)")
                    }
                    Divider()
                    Button { model.addFolder(role: role) } label: { Label("Choose Folder…", systemImage: "folder.badge.plus") }
                } label: { Label(title ?? role.title, systemImage: role.symbol) }
            }
        }
        .disabled(model.isScanning || model.isChoosingFolder)
    }

    private func summary(_ report: DeveloperResourcesReport) -> some View {
        VStack(alignment: .leading, spacing: RoomSpace.standard) {
            HStack(alignment: .top, spacing: RoomSpace.section) {
                RoomMetric(label: model.isScanning ? "Previously measured" : "Measured storage",
                           bytes: model.totalBytes, maximumSize: 32, lowerBound: report.isPartial || report.cancelled)
                Label("Read-only review", systemImage: "eye")
                    .font(RoomTypography.captionEmphasis).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: RoomSpace.section) {
                countMetric("Android devices", value: report.androidDevices.count)
                countMetric("Gradle versions", value: Set(report.gradleResources.compactMap(\.version)).count)
                countMetric("Project wrappers", value: report.projectWrappers.count)
            }
        }
    }
    private func countMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value.formatted()).font(RoomTypography.secondaryMetric).monospacedDigit()
            Text(title).font(RoomTypography.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func androidResources(_ report: DeveloperResourcesReport) -> some View {
        if report.androidDevices.isEmpty {
            RoomEmptyState(title: "No devices found", message: "Choose an AVD directory, usually .android/avd. Project folders do not contain your emulator devices.", systemImage: "externaldrive") {
                roleControl(.android, title: "Choose Android devices").menuStyle(.button).buttonStyle(.glass)
            }
        }
        let devices = showingAll ? report.androidDevices : Array(report.androidDevices.prefix(8))
        LazyVStack(alignment: .leading, spacing: RoomSpace.compact) {
          ForEach(devices) { device in
            RoomContentGroup {
                HStack(spacing: 18) {
                    AndroidDeviceGlyph().frame(width: 39, height: 63).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.displayName).font(RoomTypography.sectionTitle).lineLimit(1)
                        Text([device.apiLevel.map { "API \($0)" }, device.abi].compactMap { $0 }.joined(separator: " · "))
                            .font(RoomTypography.caption).foregroundStyle(.secondary)
                        activity(device.activity)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(device.isPartial ? "≥ " : "")\(RoomFormat.bytes(device.allocatedBytes))").font(RoomTypography.secondaryMetric).monospacedDigit()
                        Text("on disk").font(RoomTypography.caption).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    revealButton(device.url)
                }
                DisclosureGroup("Last use & evidence") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let lastUsed = device.lastUsedAt { Text("Last verified use: \(lastUsed.formatted())").font(RoomTypography.caption) }
                        else { Text("Last launch unavailable").font(RoomTypography.captionEmphasis) }
                        Text(device.lastUseNote).font(RoomTypography.caption).foregroundStyle(.secondary)
                        evidence(device.evidence)
                        path(device.url)
                    }.padding(.top, 12)
                }.font(RoomTypography.caption).foregroundStyle(.secondary)
            }
          }
        }
        moreButton(total: report.androidDevices.count)
    }

    @ViewBuilder private func gradleResources(_ report: DeveloperResourcesReport) -> some View {
        if groups.isEmpty {
            RoomEmptyState(title: "No Gradle resources found", message: "Choose a Gradle home, usually .gradle. Add projects to connect wrapper versions to resources.", systemImage: "shippingbox") {
                roleControl(.gradle, title: "Choose Gradle home").menuStyle(.button).buttonStyle(.glass)
            }
        }
        let visible = showingAll ? groups : Array(groups.prefix(8))
        LazyVStack(alignment: .leading, spacing: RoomSpace.compact) {
          ForEach(visible) { group in
            RoomContentGroup {
                RoomSectionHeader(title: group.title) {
                    Text("\(report.isPartial || report.cancelled || group.resources.contains(where: \.isPartial) ? "≥ " : "")\(RoomFormat.bytes(group.bytes))")
                        .font(RoomTypography.secondaryMetric).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: RoomSpace.small) {
                    Text(RoomDeveloperPresentation.referenceTitle(group.projects.count)).font(RoomTypography.bodyEmphasis)
                    if !group.projects.isEmpty {
                        LazyVStack(alignment: .leading, spacing: RoomSpace.small) {
                            ForEach(group.projects) { project in
                                HStack(spacing: RoomSpace.compact) {
                                    Label(project.projectURL.lastPathComponent, systemImage: "folder")
                                        .font(RoomTypography.body).lineLimit(1).truncationMode(.middle)
                                        .help(project.projectURL.path)
                                    Spacer(minLength: RoomSpace.small)
                                    revealButton(project.projectURL)
                                }
                            }
                        }
                    }
                }
                DisclosureGroup("\(group.resources.count) \(group.resources.count == 1 ? "resource" : "resources") · details") {
                    LazyVStack(alignment: .leading, spacing: RoomSpace.standard) {
                        Text("References cover the selected projects. No reference does not mean unused.")
                            .font(RoomTypography.caption).foregroundStyle(.secondary)
                        ForEach(group.resources) { resource in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(resource.name).font(RoomTypography.bodyEmphasis).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text("\(resource.isPartial ? "≥ " : "")\(RoomFormat.bytes(resource.allocatedBytes))").font(RoomTypography.body).monospacedDigit().fixedSize()
                                    revealButton(resource.url)
                                }
                                activity(resource.activity)
                                Text(resource.usageNote).font(RoomTypography.caption).foregroundStyle(.secondary)
                                path(resource.url)
                                evidence(resource.evidence)
                            }
                        }
                    }.padding(.top, 14)
                }.font(RoomTypography.caption).foregroundStyle(.secondary)
            }
          }
        }
        if !report.projectWrappers.isEmpty {
          RoomContentGroup {
            DisclosureGroup("Selected project wrappers") {
                LazyVStack(alignment: .leading, spacing: RoomSpace.standard) {
                    ForEach(report.projectWrappers) { wrapper in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(wrapper.projectURL.lastPathComponent, systemImage: "folder").font(RoomTypography.bodyEmphasis)
                                    .lineLimit(1).truncationMode(.middle)
                                path(wrapper.propertiesURL)
                                if !wrapper.note.isEmpty { Text(wrapper.note).font(RoomTypography.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(wrapper.version ?? "Unknown version").font(RoomTypography.body).monospacedDigit().fixedSize()
                            revealButton(wrapper.projectURL)
                        }
                    }
                }.padding(.top, 14)
            }.font(RoomTypography.caption).foregroundStyle(.secondary)
          }
        }
        moreButton(total: groups.count)
    }

    private func activity(_ value: DeveloperResourceActivity) -> some View {
        Label(RoomDeveloperPresentation.activityTitle(value.state), systemImage: value.state == .observedUse ? "waveform" : value.state == .possibleUse ? "exclamationmark.circle" : "questionmark.circle")
            .font(RoomTypography.caption).foregroundStyle(value.state == .possibleUse ? Color.orange : Color.secondary)
            .help(value.indicators.joined(separator: "\n"))
    }
    private func evidence(_ items: [DeveloperResourceEvidence]) -> some View {
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.label).font(RoomTypography.captionEmphasis)
                    Spacer()
                    if let date = item.date { Text(date, style: .date).font(RoomTypography.caption).monospacedDigit() }
                }
                Text(item.uncertainty).font(RoomTypography.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func path(_ url: URL) -> some View {
        RoomPathLabel(path: url.path)
    }
    private func revealButton(_ url: URL) -> some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
            Image(systemName: "arrow.up.forward").frame(width: 22, height: 22)
        }
        .buttonStyle(.glass).controlSize(.small)
        .help("Show in Finder: \(url.path)")
        .accessibilityLabel("Show \(url.lastPathComponent) in Finder")
    }
    @ViewBuilder private func moreButton(total: Int) -> some View {
        if total > 8 {
            Button(showingAll ? "Show fewer" : "Show all \(total)") { showingAll.toggle() }
                .buttonStyle(.plain).font(RoomTypography.body).foregroundStyle(.secondary)
        }
    }
}

private struct AndroidDeviceGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.38), lineWidth: 1.2)
            .overlay {
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.045)).padding(4)
            }
            .overlay(alignment: .top) { Capsule().fill(Color.primary.opacity(0.35)).frame(width: 11, height: 2).padding(.top, 7) }
            .overlay(alignment: .bottom) { Capsule().fill(Color.primary.opacity(0.24)).frame(width: 10, height: 2).padding(.bottom, 7) }
    }
}
