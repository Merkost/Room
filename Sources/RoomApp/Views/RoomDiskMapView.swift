import RoomCore
import SwiftUI

struct RoomDiskMapView: View {
    @Bindable var insights: RoomInsightsModel
    var motion = RoomMotionPolicy()
    @State private var selectedItem: RoomDiskItemSelection?
    @State private var showingIssues = false
    @State private var showingAllFindings = false
    @State private var visibleItemLimit = 100
    private var browser: RoomDiskBrowserState { insights.diskBrowserState }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.section) {
            RoomPageHeader(title: "Disk map", subtitle: "Explore allocated space. Hidden files included.") { headerActions }
            navigation
            if let report = insights.diskReport {
                reportContents(report)
            } else if insights.isScanningDisk {
                scanProgress.frame(maxWidth: .infinity, minHeight: 300)
            } else {
                RoomEmptyState(title: "Start with a folder", message: "A read-only map shows which folders and files take space.", systemImage: "square.grid.3x3.square") {
                    Button("Choose folder") { insights.chooseDiskFolder() }.buttonStyle(.glassProminent)
                }
            }
            if let message = insights.diskStatusMessage {
                RoomStatusNotice(message: message, tone: .information)
            }
        }
        .animation(motion.selection, value: browser.scope)
        .animation(motion.selection, value: browser.category)
        .animation(motion.disclosure, value: showingAllFindings)
        .onChange(of: insights.diskReport?.id) { _, _ in visibleItemLimit = 100; showingAllFindings = false }
        .onChange(of: browser.query) { _, _ in visibleItemLimit = 100 }
        .onChange(of: browser.listMode) { _, _ in visibleItemLimit = 100 }
        .sheet(item: $selectedItem) { selection in
            RoomDiskItemSheet(item: selection.item, scanID: selection.scanID,
                             isPartial: selection.isPartial, insights: insights)
        }
        .sheet(isPresented: $showingIssues) {
            RoomScanIssuesSheet(issues: insights.diskReport?.issues.map { "\($0.url.path): \($0.message)" } ?? [])
        }
    }

    private var headerActions: some View {
        HStack(spacing: RoomSpace.small) {
            accessMenu
            Button { insights.chooseDiskFolder() } label: { Label("Change folder", systemImage: "folder") }
                .buttonStyle(.glass).controlSize(.large)
                .accessibilityIdentifier("RoomDiskChangeFolderButton")
            Button {
                if insights.isScanningDisk { insights.cancelDiskScan() }
                else { insights.rescanDisk() }
            } label: {
                Label(insights.isScanningDisk ? "Stop scan" : insights.diskURL == nil ? "Scan home" : "Rescan",
                      systemImage: insights.isScanningDisk ? "stop.fill" : "arrow.clockwise")
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityIdentifier("RoomDiskScanButton")
        }
    }

    private var navigation: some View {
        HStack(spacing: RoomSpace.small) {
            Button { insights.diskGoBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!insights.canGoBack).help("Back to saved map").accessibilityLabel("Back to saved map")
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityIdentifier("RoomDiskBackButton")
            Button { insights.diskGoForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!insights.canGoForward).help("Forward to saved map").accessibilityLabel("Forward to saved map")
                .keyboardShortcut("]", modifiers: .command)
                .accessibilityIdentifier("RoomDiskForwardButton")
            Button { insights.diskGoUp() } label: { Image(systemName: "arrow.up") }
                .disabled(insights.diskURL == nil || insights.diskURL?.path == "/")
                .help("Inspect parent folder").accessibilityLabel("Inspect parent folder")
            if let url = insights.diskURL { RoomPathLabel(path: url.path, lineLimit: 1) }
            else { Text("Choose a folder to inspect").font(RoomTypography.body).foregroundStyle(.secondary) }
            Spacer(minLength: RoomSpace.small)
            if insights.diskURL != nil {
                Button { insights.revealDiskRoot() } label: { Image(systemName: "arrow.up.forward") }
                    .help("Show folder in Finder").accessibilityLabel("Show folder in Finder")
            }
        }
        .buttonStyle(.glass).controlSize(.regular)
    }

    private var accessMenu: some View {
        Menu {
            if !insights.accessFolders.isEmpty {
                Section("Saved folders") {
                    ForEach(insights.accessFolders) { folder in
                        Button { insights.scanDisk(url: folder.url) } label: {
                            Label((folder.url.path as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        }
                        .help(folder.url.path).accessibilityLabel(folder.url.path)
                    }
                }
            }
            Button("Add folder access…", systemImage: "folder.badge.plus") { insights.chooseAccessFolder() }
            #if ROOM_APP_STORE
            if !insights.hasRememberedHomeAccess { Button("Remember home folder…", systemImage: "house") { insights.chooseHomeAccess() } }
            #else
            Button("Full Disk Access…", systemImage: "lock.shield") { insights.openPrivacySettings() }
            #endif
        } label: { Image(systemName: "folder.badge.gearshape") }
        .menuStyle(.button).buttonStyle(.glass).controlSize(.large)
        .help("Saved folder access").accessibilityLabel("Saved folder access")
    }

    private func reportContents(_ report: DiskMapReport) -> some View {
        VStack(alignment: .leading, spacing: RoomSpace.section) {
            HStack(alignment: .bottom, spacing: RoomSpace.section) {
                RoomMetric(label: browser.category?.title ?? "Allocated on disk", bytes: browser.total(in: report),
                    lowerBound: report.isPartial)
                VStack(alignment: .trailing, spacing: RoomSpace.small) {
                    Text("\(report.fileCount.formatted()) \(report.fileCount == 1 ? "file" : "files") measured").font(RoomTypography.body)
                    Text("Measured \(report.scannedAt, style: .relative) ago").font(RoomTypography.caption).foregroundStyle(.secondary)
                    if !report.issues.isEmpty {
                        Button("\(report.issues.count) scan notes") { showingIssues = true }.buttonStyle(.plain)
                            .font(RoomTypography.caption)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            if report.isPartial {
                RoomStatusNotice(message: report.cancelled ? "Stopped scan. Sizes are lower bounds." : "Some locations could not be fully measured. Sizes are lower bounds.", tone: .warning)
            }
            categoryStrip(report)
            browserControls
            let mapEntries = entries(in: report)
            if !mapEntries.isEmpty {
                RoomTreemap(entries: mapEntries, open: open)
                    .frame(height: 300)
            } else {
                RoomEmptyState(title: "No matching allocated space", message: "The filters apply to this folder’s measured contents.", systemImage: "line.3.horizontal.decrease") {
                    if browser.scope != .all || browser.category != nil || !browser.query.isEmpty {
                        Button("Reset filters") { insights.diskBrowserState = RoomDiskBrowserState() }.buttonStyle(.glass)
                    }
                }
            }
            HStack(alignment: .top, spacing: RoomSpace.standard) {
                Text(mapNote).font(RoomTypography.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Label("Saved measurement · Rescan to refresh", systemImage: "clock")
                    .font(RoomTypography.caption).foregroundStyle(.secondary)
            }
            itemList(report)
            reviewSection(report)
        }
    }

    private func categoryStrip(_ report: DiskMapReport) -> some View {
        let summaries = report.categories.filter { $0.allocatedBytes > 0 }.sorted { $0.allocatedBytes > $1.allocatedBytes }
        return VStack(alignment: .leading, spacing: RoomSpace.compact) {
            if !summaries.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Folder breakdown").font(RoomTypography.captionEmphasis)
                    Spacer(minLength: RoomSpace.small)
                    Text("Before filters").font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(summaries) { summary in
                            Button { toggleCategory(summary.category) } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(RoomStoragePalette.color(summary.category))
                                    .opacity(browser.category == nil || browser.category == summary.category ? 1 : 0.3)
                                    .frame(width: max(0, (geometry.size.width - CGFloat(max(0, summaries.count - 1)) * 2) *
                                        CGFloat(Double(summary.allocatedBytes) / Double(max(1, report.allocatedBytes)))))
                            }
                            .buttonStyle(.plain)
                            .help("Entire folder · \(summary.category.title): \(RoomFormat.bytes(summary.allocatedBytes)) before filters")
                            .accessibilityLabel("Filter \(summary.category.title), \(RoomFormat.bytes(summary.allocatedBytes)) in the entire folder before filters")
                        }
                    }
                }.frame(height: 12)
            }
            ScrollView(.horizontal) {
                HStack(spacing: RoomSpace.standard) {
                    Button("All categories") { insights.diskBrowserState.category = nil }
                        .foregroundStyle(browser.category == nil ? .primary : .secondary)
                    ForEach(summaries) { summary in
                        Button { toggleCategory(summary.category) } label: {
                            Label(summary.category.title, systemImage: summary.category.symbol)
                        }
                        .foregroundStyle(browser.category == summary.category ? .primary : .secondary)
                        .help("\(RoomFormat.bytes(summary.allocatedBytes)) in the entire folder before filters")
                    }
                }
                .font(RoomTypography.caption).buttonStyle(.plain).padding(.vertical, RoomSpace.micro)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var browserControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomSpace.standard) { scopePicker; searchField }
            VStack(alignment: .leading, spacing: RoomSpace.compact) { scopePicker; searchField }
        }
    }

    private var scopePicker: some View {
        Picker("File scope", selection: $insights.diskBrowserState.scope) {
            ForEach(RoomDiskScope.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 260)
        .accessibilityIdentifier("RoomDiskScopePicker")
    }

    private var searchField: some View {
        HStack(spacing: RoomSpace.small) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search measured items", text: $insights.diskBrowserState.query)
                .textFieldStyle(.plain).font(RoomTypography.body)
                .accessibilityLabel("Search measured items")
                .accessibilityIdentifier("RoomDiskSearchField")
            if !browser.query.isEmpty {
                Button { insights.diskBrowserState.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, RoomSpace.compact).padding(.vertical, RoomSpace.small)
        .background(RoomSurface.group, in: RoundedRectangle(cornerRadius: RoomRadius.control))
        .frame(minWidth: 200, maxWidth: .infinity)
    }

    private func toggleCategory(_ category: StorageCategory) {
        insights.diskBrowserState.category = browser.category == category ? nil : category
    }

    private var mapNote: String {
        switch browser.scope {
        case .all: "Tile area shows matching allocated bytes in each immediate item. Open a folder to explore."
        case .hidden: "Hidden allocated bytes in each item, including matching hidden descendants."
        case .large: "Matching bytes within immediate items of at least 1 GB, including folder totals."
        }
    }

    private func entries(in report: DiskMapReport) -> [RoomMapEntry] {
        let matches = browser.items(in: report, mode: .contents).filter { browser.bytes(in: $0) > 0 }
            .sorted { browser.bytes(in: $0) > browser.bytes(in: $1) }
        let leading = Array(matches.prefix(12))
        var result = leading.map { RoomMapEntry(id: $0.id, name: $0.name, bytes: browser.bytes(in: $0), item: $0, category: browser.category ?? $0.category) }
        let remainder = matches.dropFirst(12).reduce(Int64(0)) { $0 + browser.bytes(in: $1) }
        if remainder > 0 { result.append(RoomMapEntry(id: "room-map-other", name: "Other measured items", bytes: remainder, item: nil, category: nil)) }
        return result
    }

    private func open(_ item: DiskMapItem) {
        if item.isDirectory { insights.scanDisk(url: item.url) }
        else { inspect(item) }
    }

    private func inspect(_ item: DiskMapItem) {
        guard let report = insights.diskReport else { return }
        selectedItem = RoomDiskItemSelection(item: item, scanID: report.id, isPartial: report.isPartial)
    }

    private func itemList(_ report: DiskMapReport) -> some View {
        let items = browser.items(in: report)
        return VStack(alignment: .leading, spacing: RoomSpace.standard) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RoomSpace.standard) { listModePicker; Spacer(minLength: 12); sortPicker }
                VStack(alignment: .leading, spacing: RoomSpace.compact) { listModePicker; sortPicker }
            }
            if items.isEmpty {
                RoomStatusNotice(message: browser.listMode == .largest ? "No match among the scan’s largest 100 files. Folder contents remains available above." : "No measured items match these filters. Reset a filter or search another name.", systemImage: "magnifyingglass")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.prefix(visibleItemLimit))) { item in
                        Button { inspect(item) } label: {
                            HStack(spacing: RoomSpace.compact) {
                                Image(systemName: item.isDirectory ? "folder" : item.category.symbol)
                                    .foregroundStyle(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: RoomSpace.micro) {
                                    Text(item.name).font(RoomTypography.bodyEmphasis).lineLimit(1).truncationMode(.middle)
                                    if browser.listMode == .largest {
                                        Text(item.url.deletingLastPathComponent().path).font(RoomTypography.caption)
                                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                if item.isHidden { Image(systemName: "eye.slash").font(RoomTypography.caption).foregroundStyle(.secondary) }
                                Spacer(minLength: RoomSpace.compact)
                                Text(RoomFormat.bytes(browser.bytes(in: item))).font(RoomTypography.body).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(RoomTypography.meta).foregroundStyle(.tertiary)
                            }
                            .padding(RoomSpace.compact).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 44)
                    }
                }
                if items.count > visibleItemLimit {
                    Button("Show next \(min(100, items.count - visibleItemLimit)) items") { visibleItemLimit += 100 }
                        .buttonStyle(.plain).font(RoomTypography.body)
                }
            }
            Text(browser.listMode == .largest ? "Searches the scan’s retained largest 100 files. Folder contents lists immediate children." : "Searches immediate folder contents. Open a folder to search inside it.")
                .font(RoomTypography.caption).foregroundStyle(.secondary)
        }
    }

    private var listModePicker: some View {
        Picker("Item list", selection: $insights.diskBrowserState.listMode) {
            ForEach(RoomDiskListMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 280)
        .accessibilityIdentifier("RoomDiskListModePicker")
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $insights.diskBrowserState.sort) {
            ForEach(RoomDiskSort.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.menu).fixedSize()
        .accessibilityIdentifier("RoomDiskSortPicker")
    }

    @ViewBuilder private func reviewSection(_ report: DiskMapReport) -> some View {
        if let analysis = insights.analysisReport, analysis.scanID == report.id {
            let findings = analysis.findings.filter { browser.matches($0.item) }
            VStack(alignment: .leading, spacing: RoomSpace.standard) {
                RoomSectionHeader(title: "Smart review", detail: analysis.source == .onDevice ? analysis.availability.provider : "Local rules") {
                    if insights.isAnalyzingStorage {
                        ProgressView().controlSize(.small)
                        Button("Stop") { insights.cancelStorageAnalysis() }.buttonStyle(.glass)
                    } else {
                        Button { insights.analyzeStorage() } label: { Label("Analyze", systemImage: "sparkles") }
                            .buttonStyle(.glass).disabled(insights.isScanningDisk)
                    }
                }
                if insights.isAnalyzingStorage {
                    RoomStatusNotice(message: "Analyzing metadata on this Mac…", systemImage: "sparkles")
                } else if let message = insights.analysisStatus {
                    Text(message).font(RoomTypography.caption).foregroundStyle(.secondary)
                }
                if findings.isEmpty {
                    Text("No review items match these filters.").font(RoomTypography.body).foregroundStyle(.secondary)
                } else {
                    ForEach(showingAllFindings ? findings : Array(findings.prefix(3))) { finding in
                        Button { inspect(finding.item) } label: {
                            HStack(alignment: .top, spacing: RoomSpace.compact) {
                                Image(systemName: finding.category.symbol).frame(width: 20).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: RoomSpace.micro) {
                                    Text(finding.item.name).font(RoomTypography.bodyEmphasis).lineLimit(1)
                                    Text(finding.reason).font(RoomTypography.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: RoomSpace.small)
                                RoomDispositionLabel(disposition: finding.disposition)
                            }
                            .padding(.vertical, RoomSpace.small).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(finding.reason)
                    }
                    if findings.count > 3 {
                        Button(showingAllFindings ? "Show fewer" : "Review all \(findings.count)") { showingAllFindings.toggle() }
                            .buttonStyle(.plain).font(RoomTypography.body)
                    }
                }
                if !analysis.availability.isAvailable && !insights.isAnalyzingStorage {
                    Button("Apple Intelligence settings", systemImage: "gearshape") { insights.openAppleIntelligenceSettings() }
                        .buttonStyle(.plain).font(RoomTypography.caption)
                }
                Text("Metadata suggestions do not authorize cleanup. Known cache locations can be reviewed in Clean.")
                    .font(RoomTypography.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var scanProgress: some View {
        VStack(spacing: RoomSpace.standard) {
            ProgressView().controlSize(.small)
            Text("Measuring this folder").font(RoomTypography.sectionTitle)
            if let progress = insights.diskProgress {
                Text("\(progress.visitedFiles.formatted()) files · \(RoomFormat.bytes(progress.allocatedBytes))")
                    .font(RoomTypography.body).monospacedDigit().foregroundStyle(.secondary)
                RoomPathLabel(path: progress.currentName, lineLimit: 1).frame(maxWidth: 440)
            }
            Text("Files stay in place.").font(RoomTypography.caption).foregroundStyle(.secondary)
            Button("Stop scan") { insights.cancelDiskScan() }.buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum RoomStoragePalette {
    static func color(_ category: StorageCategory) -> Color {
        let index = StorageCategory.allCases.firstIndex(of: category) ?? 0
        return Color(hue: 0.52 + Double(index % 3) * 0.028, saturation: 0.24, brightness: 0.48 + Double(index) * 0.065)
    }
}

private struct RoomDispositionLabel: View {
    let disposition: StorageDisposition
    private var symbol: String {
        switch disposition { case .protected: "lock.shield"; case .review: "eye"; case .cache: "arrow.trianglehead.2.clockwise.rotate.90" }
    }
    private var title: String {
        switch disposition { case .protected: "Protected"; case .review: "Review"; case .cache: "Cache" }
    }
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.55), in: Capsule())
            .fixedSize()
            .help(disposition.title)
    }
}

private struct RoomTreemap: View {
    let entries: [RoomMapEntry]
    let open: (DiskMapItem) -> Void
    @Environment(\.colorScheme) private var colorScheme
    var motion = RoomMotionPolicy()
    @State private var hovered: String?

    var body: some View {
        GeometryReader { geometry in
            let tiles = RoomMapLayout.layout(entries, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    Button {
                        if let item = tile.entry.item { open(item) }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            if tile.rect.width > 80 && tile.rect.height > 52 {
                                HStack(alignment: .top, spacing: 7) {
                                    if tile.rect.width > 180, let category = tile.entry.category {
                                        Image(systemName: tile.entry.item?.isDirectory == true ? "folder" : category.symbol)
                                            .font(.system(size: 14)).opacity(0.7)
                                    }
                                    Text(tile.entry.name)
                                        .font(.system(size: tile.rect.width > 240 ? 16 : 13, weight: .medium))
                                        .lineLimit(tile.rect.height > 100 ? 2 : 1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                    if tile.entry.item?.isDirectory == true && tile.rect.width > 130 {
                                        Image(systemName: "arrow.down.right").font(.system(size: 11)).opacity(0.6)
                                    }
                                }
                                if tile.rect.height > 78 {
                                    Text(RoomFormat.bytes(tile.entry.bytes))
                                        .font(RoomType.figure(tile.rect.width > 240 ? 26 : 16)).monospacedDigit().opacity(0.72)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(min(20, max(8, tile.rect.width * 0.055)))
                        .frame(width: max(0, tile.rect.width - 5), height: max(0, tile.rect.height - 5), alignment: .topLeading)
                        .background(tileGradient(tile.entry.category, index: tile.index))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(hovered == tile.id ? 0.2 : 0), lineWidth: 1.5)
                        }
                        .opacity(hovered == tile.id ? 0.88 : 1)
                    }
                    .buttonStyle(.plain).disabled(tile.entry.item == nil)
                    .offset(x: tile.rect.minX + 2.5, y: tile.rect.minY + 2.5)
                    .help("\(tile.entry.item?.url.path ?? "All remaining measured space")\n\(RoomFormat.bytes(tile.entry.bytes))")
                    .accessibilityLabel("\(tile.entry.name), \(RoomFormat.bytes(tile.entry.bytes))\(tile.entry.item?.isDirectory == true ? ", open folder" : "")")
                    .onHover { hovered = $0 ? tile.id : nil }
                }
            }
            .animation(motion.selection, value: hovered)
        }
    }

    private func tileGradient(_ category: StorageCategory?, index: Int) -> LinearGradient {
        let categoryIndex = category.flatMap { StorageCategory.allCases.firstIndex(of: $0) } ?? index
        let hue = 0.52 + Double(categoryIndex % 3) * 0.028
        let saturation = colorScheme == .dark ? 0.23 : 0.16
        let base = colorScheme == .dark ? 0.24 + Double(categoryIndex % 4) * 0.035 : 0.89 + Double(categoryIndex % 3) * 0.025
        return LinearGradient(colors: [Color(hue: hue, saturation: saturation, brightness: base + 0.045),
                                       Color(hue: hue, saturation: saturation + 0.03, brightness: base)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct RoomMapEntry {
    let id: String
    let name: String
    let bytes: Int64
    let item: DiskMapItem?
    let category: StorageCategory?
}
private struct RoomMapTile: Identifiable {
    let entry: RoomMapEntry
    let rect: CGRect
    let index: Int
    var id: String { entry.id }
}

/// Weighted binary partitioning preserves each child's share at every level.
/// The gutter is visual padding inside its measured rectangle, never extra data.
private enum RoomMapLayout {
    static func layout(_ entries: [RoomMapEntry], in rect: CGRect) -> [RoomMapTile] {
        var result: [RoomMapTile] = []
        func divide(_ range: Range<Int>, _ bounds: CGRect) {
            guard !range.isEmpty else { return }
            if range.count == 1 {
                result.append(RoomMapTile(entry: entries[range.lowerBound], rect: bounds, index: range.lowerBound))
                return
            }
            let total = range.reduce(0.0) { $0 + Double(entries[$1].bytes) }
            guard total > 0 else { return }
            var accumulated = 0.0
            var split = range.lowerBound + 1
            var nearest = Double.greatestFiniteMagnitude
            for index in range.dropLast() {
                accumulated += Double(entries[index].bytes)
                let distance = abs(total * 0.5 - accumulated)
                if distance < nearest { nearest = distance; split = index + 1 }
            }
            let left = (range.lowerBound..<split).reduce(0.0) { $0 + Double(entries[$1].bytes) }
            let ratio = left / total
            if bounds.width >= bounds.height {
                let width = bounds.width * ratio
                divide(range.lowerBound..<split, CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height))
                divide(split..<range.upperBound, CGRect(x: bounds.minX + width, y: bounds.minY, width: bounds.width - width, height: bounds.height))
            } else {
                let height = bounds.height * ratio
                divide(range.lowerBound..<split, CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height))
                divide(split..<range.upperBound, CGRect(x: bounds.minX, y: bounds.minY + height, width: bounds.width, height: bounds.height - height))
            }
        }
        divide(entries.indices, rect)
        return result
    }
}

private struct RoomDiskItemSelection: Identifiable {
    let item: DiskMapItem
    let scanID: UUID
    let isPartial: Bool
    var id: String { scanID.uuidString + ":" + item.id }
}

private struct RoomDiskItemSheet: View {
    let item: DiskMapItem
    let scanID: UUID
    let isPartial: Bool
    @Bindable var insights: RoomInsightsModel
    @Environment(\.dismiss) private var dismiss
    private var finding: StorageFinding? {
        guard insights.analysisReport?.scanID == scanID else { return nil }
        return insights.analysisReport?.findings.first { $0.item.id == item.id }
    }

    var body: some View {
        RoomSheetLayout(title: item.name, subtitle: item.category.title + (item.isHidden ? " · Hidden" : ""),
                        width: 620, maxContentHeight: 390) {
            RoomMetric(label: "Allocated on disk", bytes: item.allocatedBytes, lowerBound: isPartial)
            Text("\(RoomFormat.bytes(item.logicalBytes)) measured logical size")
                .font(RoomTypography.body).foregroundStyle(.secondary)
            if isPartial {
                RoomStatusNotice(message: "This scan was incomplete. Sizes are lower bounds.", tone: .warning)
            }
            if let finding {
                VStack(alignment: .leading, spacing: RoomSpace.compact) {
                    RoomDispositionLabel(disposition: finding.disposition)
                    Text(finding.reason).font(RoomTypography.body).foregroundStyle(.secondary)
                    Text(finding.source == .onDevice ? "On-device suggestion · existing protections stay in force" : "Review tag: local rules")
                        .font(RoomTypography.caption).foregroundStyle(.secondary)
                }
            }
            RoomPathLabel(path: item.url.path, label: "Location")
        } actions: {
            Button { insights.reveal(item: item) } label: { Label("Show in Finder", systemImage: "folder") }
                .roomAction(.secondary)
            if item.isDirectory {
                Button("Look inside") { insights.scanDisk(url: item.url); dismiss() }.roomAction(.secondary)
            }
            if finding?.disposition == .cache {
                Button("Review in Clean") { insights.requestCleanReview(path: item.url.path); dismiss() }
                    .roomAction(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.roomAction(.primary).keyboardShortcut(.defaultAction)
        }
    }
}
