import RoomCore
import SwiftUI

/// A read-only resource review. Activity evidence never becomes a deletion rule.
struct RoomDeveloperView: View {
    @Bindable var model: RoomDeveloperModel
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section = DeveloperSection.android
    @State private var showingAll = false
    @State private var showingNotes = false
    private enum DeveloperSection: String, CaseIterable { case android = "Android", gradle = "Gradle" }
    private var animation: Animation? { motionEnabled && !reduceMotion ? .smooth(duration: 0.22) : nil }
    private var groups: [RoomGradleVersionGroup] { RoomDeveloperPresentation.groups(model.report?.gradleResources ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Developer resources").font(RoomType.heading(22))
                    Text(model.report == nil ? "Devices, build versions, and the projects that reference them." : "\(RoomFormat.bytes(model.totalBytes)) measured · read-only review")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                if model.isChoosingFolder { ProgressView().controlSize(.small) }
                addMenu
                Button {
                    if model.isScanning { model.stop() } else { model.scan() }
                } label: {
                    Label(model.isScanning ? "Stop" : "Scan", systemImage: model.isScanning ? "stop" : "arrow.clockwise")
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(!model.canScan)
                .accessibilityIdentifier("RoomDeveloperScanButton")
                .keyboardShortcut("r", modifiers: .command)
            }

            if model.locations.isEmpty {
                emptyReview
            } else {
                DisclosureGroup("\(model.locations.count) \(model.locations.count == 1 ? "folder" : "folders") in this review") {
                    VStack(spacing: 12) {
                        ForEach(model.locations) { location in
                            HStack(spacing: 12) {
                                Image(systemName: location.role.symbol).frame(width: 20).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.role.title).font(.system(size: 13, weight: .medium))
                                    Text(location.folder.url.path).font(.system(size: 12)).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle).help(location.folder.url.path)
                                }
                                Spacer()
                                Button { model.remove(location) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.isScanning)
                                    .help("Remove from this review; saved folder access is managed in Settings")
                                    .accessibilityLabel("Remove \(location.folder.name) from developer review")
                            }
                        }
                    }.padding(.top, 12)
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(16).roomGlass(in: RoundedRectangle(cornerRadius: 18))
            }

            if model.isScanning {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.progress).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }.padding(.vertical, 3)
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
                HStack(alignment: .top) {
                    Text(report.cancelled ? "Stopped · partial results" : report.isPartial ? "Partial results · some locations need attention" : "Measured \(report.scannedAt.formatted(date: .omitted, time: .shortened))")
                    Spacer()
                    if !report.issues.isEmpty {
                        Button("\(report.issues.count) \(report.issues.count == 1 ? "note" : "notes")") { showingNotes = true }.buttonStyle(.plain)
                    }
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 6)
        .animation(animation, value: section)
        .animation(animation, value: model.report?.id)
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
                Button { model.addFolder(role: role) } label: { Label(role.title, systemImage: role.symbol) }
            }
        } label: { Label("Add folder", systemImage: "plus") }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 13))
        .disabled(model.isScanning || model.isChoosingFolder)
        .accessibilityIdentifier("RoomDeveloperAddFolder")
    }

    private var emptyReview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 24) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.secondary).frame(width: 70)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect the storage to the work.").font(RoomType.heading(19))
                    Text("Choose your AVD directory, Gradle home, or project folders to begin.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                ForEach(RoomDeveloperFolderRole.allCases) { role in
                    Button { model.addFolder(role: role) } label: { Label(role.title, systemImage: role.symbol) }
                        .buttonStyle(.glass).disabled(model.isChoosingFolder)
                }
            }
            Text("Only chosen folders are read. No resources are removed.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .roomGlass(in: RoundedRectangle(cornerRadius: 24))
    }

    private func summary(_ report: DeveloperResourcesReport) -> some View {
        HStack(spacing: 28) {
            countMetric("Android devices", value: report.androidDevices.count, symbol: "iphone.gen3")
            Divider().frame(height: 35)
            countMetric("Gradle versions", value: Set(report.gradleResources.compactMap(\.version)).count, symbol: "shippingbox")
            Divider().frame(height: 35)
            countMetric("Project wrappers", value: report.projectWrappers.count, symbol: "point.3.connected.trianglepath.dotted")
            Spacer(minLength: 0)
        }.padding(.vertical, 6)
    }
    private func countMetric(_ title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value.formatted()).font(RoomType.figure(28)).monospacedDigit()
            Label(title, systemImage: symbol).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func androidResources(_ report: DeveloperResourcesReport) -> some View {
        if report.androidDevices.isEmpty { noResults("No Android devices found in the chosen directories.") }
        let devices = showingAll ? report.androidDevices : Array(report.androidDevices.prefix(8))
        ForEach(devices) { device in
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    AndroidDeviceGlyph().frame(width: 39, height: 63).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.displayName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text([device.apiLevel.map { "API \($0)" }, device.abi].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        activity(device.activity)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(device.isPartial ? "≥ " : "")\(RoomFormat.bytes(device.allocatedBytes))").font(RoomType.figure(22)).monospacedDigit()
                        Text("on disk").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("Last use & evidence") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let lastUsed = device.lastUsedAt { Text("Last verified use: \(lastUsed.formatted())").font(.system(size: 12)) }
                        else { Text("Last launch unavailable").font(.system(size: 12, weight: .medium)) }
                        Text(device.lastUseNote).font(.system(size: 12)).foregroundStyle(.secondary)
                        evidence(device.evidence)
                        path(device.url)
                    }.padding(.top, 12)
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(20).roomGlass(in: RoundedRectangle(cornerRadius: 22))
        }
        moreButton(total: report.androidDevices.count)
    }

    @ViewBuilder private func gradleResources(_ report: DeveloperResourcesReport) -> some View {
        if groups.isEmpty { noResults("No Gradle resources found in the chosen homes.") }
        let visible = showingAll ? groups : Array(groups.prefix(8))
        ForEach(visible) { group in
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title).font(RoomType.heading(19))
                    Spacer()
                    Text(RoomFormat.bytes(group.bytes)).font(RoomType.figure(22)).monospacedDigit()
                }
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(RoomDeveloperPresentation.referenceTitle(group.projects.count)).font(.system(size: 13, weight: .medium))
                        if !group.projects.isEmpty {
                            ForEach(group.projects) { project in
                                Label(project.projectURL.lastPathComponent, systemImage: "folder")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                    .help(project.projectURL.path).textSelection(.enabled)
                            }
                        }
                    }
                    Spacer()
                }
                DisclosureGroup("\(group.resources.count) \(group.resources.count == 1 ? "resource" : "resources") · details") {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("References cover the selected projects. No reference does not mean unused.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ForEach(group.resources) { resource in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(resource.name).font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(resource.isPartial ? "≥ " : "")\(RoomFormat.bytes(resource.allocatedBytes))").font(.system(size: 12)).monospacedDigit()
                                }
                                activity(resource.activity)
                                Text(resource.usageNote).font(.system(size: 12)).foregroundStyle(.secondary)
                                path(resource.url)
                                evidence(resource.evidence)
                            }
                        }
                    }.padding(.top, 14)
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(20).roomGlass(in: RoundedRectangle(cornerRadius: 22))
        }
        if !report.projectWrappers.isEmpty {
            DisclosureGroup("Selected project wrappers") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(report.projectWrappers) { wrapper in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(wrapper.projectURL.lastPathComponent, systemImage: "folder").font(.system(size: 13, weight: .medium))
                                path(wrapper.propertiesURL)
                                if !wrapper.note.isEmpty { Text(wrapper.note).font(.system(size: 12)).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(wrapper.version ?? "Unknown version").font(.system(size: 13)).monospacedDigit()
                        }
                    }
                }.padding(.top, 14)
            }.font(.system(size: 12)).foregroundStyle(.secondary)
        }
        moreButton(total: groups.count)
    }

    private func activity(_ value: DeveloperResourceActivity) -> some View {
        Label(RoomDeveloperPresentation.activityTitle(value.state), systemImage: value.state == .observedUse ? "waveform" : value.state == .possibleUse ? "exclamationmark.circle" : "questionmark.circle")
            .font(.system(size: 12)).foregroundStyle(value.state == .possibleUse ? Color.orange : Color.secondary)
            .help(value.indicators.joined(separator: "\n"))
    }
    private func evidence(_ items: [DeveloperResourceEvidence]) -> some View {
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.label).font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let date = item.date { Text(date, style: .date).font(.system(size: 11)).monospacedDigit() }
                }
                Text(item.uncertainty).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private func path(_ url: URL) -> some View {
        Text(url.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            .lineLimit(2).truncationMode(.middle)
    }
    private func noResults(_ title: String) -> some View {
        Text(title).font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 20)
    }
    @ViewBuilder private func moreButton(total: Int) -> some View {
        if total > 8 {
            Button(showingAll ? "Show fewer" : "Show all \(total)") { showingAll.toggle() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
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

private struct RoomDeveloperGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : .clear, in: shape)
            .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
    }
}
private extension View {
    func roomGlass<S: Shape>(in shape: S) -> some View { modifier(RoomDeveloperGlass(shape: shape)) }
}
