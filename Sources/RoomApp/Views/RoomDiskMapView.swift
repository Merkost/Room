import RoomCore
import SwiftUI

struct RoomDiskMapView: View {
    @Bindable var insights: RoomInsightsModel
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: DiskMapItem?
    @State private var showingIssues = false
    @State private var showingAll = false
    @State private var showingAllFindings = false
    @State private var filter = RoomDiskFilter.all

    private var animation: Animation? { motionEnabled && !reduceMotion ? .smooth(duration: 0.35) : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                Label("Disk map", systemImage: "square.grid.2x2")
                    .font(RoomType.heading(26)).tracking(-0.4)
                Spacer(minLength: 12)
                accessMenu
                Button { insights.chooseDiskFolder() } label: { Label("Choose folder", systemImage: "folder") }
                    .buttonStyle(.glass).controlSize(.large)
            }

            if let report = insights.diskReport {
                reportContents(report)
            } else if insights.isScanningDisk {
                scanProgress.frame(maxWidth: .infinity, minHeight: 380)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "square.grid.3x3.square")
                        .font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text("Start with a folder.").font(RoomType.heading(22))
                    Text("Hidden files included. Your files stay in place.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    Button { insights.scanHome() } label: { Label("Choose home folder", systemImage: "house") }
                        .buttonStyle(.glassProminent).controlSize(.large)
                }
                .frame(maxWidth: .infinity, minHeight: 380)
            }
        }
        .padding(.top, 22)
        .animation(animation, value: insights.diskReport?.id)
        .animation(animation, value: filter)
        .animation(animation, value: showingAllFindings)
        .onChange(of: insights.diskReport?.url.path) { _, _ in
            filter = .all
            showingAll = false
            showingAllFindings = false
        }
        .sheet(item: $selectedItem) { item in
            RoomDiskItemSheet(item: item, insights: insights)
        }
        .sheet(isPresented: $showingIssues) {
            RoomScanIssuesSheet(issues: insights.diskReport?.issues.map { "\($0.url.path): \($0.message)" } ?? [])
        }
    }

    private var accessMenu: some View {
        Menu {
            if !insights.accessFolders.isEmpty {
                Section("Saved folders") {
                    ForEach(insights.accessFolders) { folder in
                        Button { insights.scanDisk(url: folder.url) } label: { Label(folder.name, systemImage: "folder") }
                    }
                }
            }
            Button("Add folder access…", systemImage: "folder.badge.plus") { insights.chooseAccessFolder() }
            Button("Privacy & Security…", systemImage: "lock.shield") { insights.openPrivacySettings() }
        } label: {
            Image(systemName: "folder.badge.gearshape")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Saved folder access").accessibilityLabel("Saved folder access")
    }

    private func reportContents(_ report: DiskMapReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                RoomByteMetric(bytes: filter.total(in: report), maximumSize: 54)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(filter == .all ? "\(report.fileCount.formatted()) files" : filter.title)
                        .font(.system(size: 14))
                    Text(report.isPartial ? "Partial measurement" : "Allocated on disk")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .fixedSize()
            }
            HStack(spacing: 12) {
                Button { insights.diskGoUp() } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.glass).help("Scan parent folder").accessibilityLabel("Scan parent folder")
                    .disabled(insights.isScanningDisk || report.url.path == "/")
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.url.lastPathComponent.isEmpty ? "Macintosh HD" : report.url.lastPathComponent)
                        .font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(report.url.path).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button { insights.revealDiskRoot() } label: { Image(systemName: "arrow.up.forward") }
                    .buttonStyle(.glass).help("Show folder in Finder").accessibilityLabel("Show folder in Finder")
            }

            if !report.categories.isEmpty { categoryStrip(report) }
            filterBar(report)

            if insights.isScanningDisk {
                scanProgress.frame(height: 280)
            } else if filter.total(in: report) > 0 {
                RoomTreemap(entries: entries(in: report), open: open)
                    .frame(height: 285)
                    .id(report.url.path + filter.id)
                    .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.985)))
            } else {
                ContentUnavailableView("No matching space", systemImage: filter.symbol,
                    description: Text(filter == .all ? "No locally allocated files were measured." : "Try another filter."))
                    .frame(height: 220)
            }

            HStack(alignment: .top, spacing: 16) {
                Label(filter.mapNote, systemImage: "info.circle")
                Spacer(minLength: 0)
                if !report.issues.isEmpty {
                    Button("\(report.issues.count) scan notes") { showingIssues = true }.buttonStyle(.plain)
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)

            if let status = insights.statusMessage {
                Text(status).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            reviewSection(report)
            itemList(report)
        }
    }

    private func categoryStrip(_ report: DiskMapReport) -> some View {
        let summaries = report.categories.filter { $0.allocatedBytes > 0 }.sorted { $0.allocatedBytes > $1.allocatedBytes }
        return VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(summaries) { summary in
                        Button { toggleCategory(summary.category) } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(RoomStoragePalette.color(summary.category))
                                .opacity(filter == .all || filter == .category(summary.category) ? 1 : 0.35)
                                .frame(width: max(0, (geometry.size.width - CGFloat(max(0, summaries.count - 1)) * 2) *
                                       CGFloat(Double(summary.allocatedBytes) / Double(max(1, report.allocatedBytes)))))
                        }
                        .buttonStyle(.plain)
                        .help("\(summary.category.title): \(RoomFormat.bytes(summary.allocatedBytes))")
                        .accessibilityLabel("Filter \(summary.category.title), \(RoomFormat.bytes(summary.allocatedBytes))")
                    }
                }
            }
            .frame(height: 13)
            ScrollView(.horizontal) {
                HStack(spacing: 19) {
                    ForEach(summaries) { summary in
                        Button { toggleCategory(summary.category) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: summary.category.symbol)
                                Text(summary.category.title)
                                Text(RoomFormat.bytes(summary.allocatedBytes)).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12, weight: filter == .category(summary.category) ? .semibold : .regular))
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(filter == .category(summary.category) ? .primary : .secondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func toggleCategory(_ category: StorageCategory) {
        filter = filter == .category(category) ? .all : .category(category)
    }

    private func filterBar(_ report: DiskMapReport) -> some View {
        HStack(spacing: 8) {
            filterButton(.all)
            filterButton(.hidden)
            filterButton(.large)
            Spacer(minLength: 12)
            if case .category(let category) = filter {
                Label(category.title, systemImage: category.symbol)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if filter == .hidden {
                Text("\(report.hiddenFileCount.formatted()) hidden files")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else if filter == .large {
                Text("Items ≥ 1 GB").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder private func filterButton(_ option: RoomDiskFilter) -> some View {
        if filter == option {
            Button { filter = option } label: { Label(option.title, systemImage: option.symbol) }
                .buttonStyle(.glassProminent)
        } else {
            Button { filter = option } label: { Label(option.title, systemImage: option.symbol) }
                .buttonStyle(.glass)
        }
    }

    private func entries(in report: DiskMapReport) -> [RoomMapEntry] {
        let sorted = report.children.filter { filter.bytes(in: $0) > 0 }
            .sorted { filter.bytes(in: $0) > filter.bytes(in: $1) }
        let leading = Array(sorted.prefix(10))
        var entries = leading.map {
            RoomMapEntry(id: $0.id, name: $0.name, bytes: filter.bytes(in: $0), item: $0,
                         category: filter.category ?? $0.category)
        }
        let remainder = max(0, filter.total(in: report) - leading.reduce(Int64(0)) { $0 + filter.bytes(in: $1) })
        if remainder > 0 {
            entries.append(RoomMapEntry(id: "room-map-other", name: "Other", bytes: remainder, item: nil, category: nil))
        }
        return entries
    }

    private func open(_ item: DiskMapItem) {
        if item.isDirectory { insights.scanDisk(url: item.url) }
        else { selectedItem = item }
    }

    @ViewBuilder private func reviewSection(_ report: DiskMapReport) -> some View {
        if let analysis = insights.analysisReport, analysis.scanID == report.id {
            let findings = analysis.findings.filter { filter.includes($0.item, category: $0.category) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Label("Smart review", systemImage: "sparkle.magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                    Label(analysis.source == .onDevice ? analysis.availability.provider : "Rule-based",
                          systemImage: analysis.source == .onDevice ?
                            (analysis.availability.provider == "Apple Intelligence" ? "apple.intelligence" : "cpu") : "line.3.horizontal.decrease")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .help(analysis.source == .onDevice ?
                              (analysis.availability.modelName.map { "\(analysis.availability.provider) · \($0)" } ?? analysis.availability.provider) : "Local metadata rules")
                    Spacer(minLength: 8)
                    if insights.isAnalyzingStorage {
                        ProgressView().controlSize(.mini)
                        Button("Stop") { insights.cancelStorageAnalysis() }.buttonStyle(.glass)
                    } else {
                        Button { insights.analyzeStorage() } label: { Label("Analyze", systemImage: "sparkles") }
                            .buttonStyle(.glass).disabled(insights.isScanningDisk)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Text(insights.isAnalyzingStorage ? "Analyzing file metadata locally…" : analysis.availability.reason)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if !analysis.availability.isAvailable && !insights.isAnalyzingStorage {
                        Button { insights.openAppleIntelligenceSettings() } label: { Image(systemName: "gearshape") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Open Apple Intelligence settings. Local models use an existing runtime and model on this Mac.")
                            .accessibilityLabel("Apple Intelligence settings")
                    }
                }
                if findings.isEmpty {
                    Text("No review items match this filter.").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    ForEach(showingAllFindings ? findings : Array(findings.prefix(3))) { finding in
                        reviewCard(finding)
                    }
                    if findings.count > 3 {
                        Button(showingAllFindings ? "Show less" : "Review all \(findings.count)") { showingAllFindings.toggle() }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Text(analysis.source == .onDevice ? "Metadata suggestions only. Protection is never relaxed; cleanup eligibility is checked separately." :
                     "Metadata only. Review tags follow local rules. Cleanup eligibility is checked separately.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private func reviewCard(_ finding: StorageFinding) -> some View {
        Button { selectedItem = finding.item } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: finding.category.symbol)
                    .font(.system(size: 18, weight: .regular)).foregroundStyle(.secondary)
                    .frame(width: 23).padding(.top, 3)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(finding.item.name).font(.system(size: 14, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                        RoomDispositionLabel(disposition: finding.disposition)
                        Spacer(minLength: 8)
                        Text(RoomFormat.bytes(finding.item.allocatedBytes))
                            .font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    }
                    Text(finding.reason).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 5)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .help(finding.reason)
    }

    @ViewBuilder private func itemList(_ report: DiskMapReport) -> some View {
        let candidates = showingAll ? report.children : report.largestFiles
        let matching = candidates.filter { showingAll ? filter.bytes(in: $0) > 0 : filter.includes($0) }
            .sorted { filter.bytes(in: $0) > filter.bytes(in: $1) }
        let items = showingAll ? matching : Array(matching.prefix(3))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(showingAll ? "Folder contents" : "Largest matching files", systemImage: showingAll ? "folder" : "doc")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Button(showingAll ? "Largest files" : "Folder contents") { showingAll.toggle() }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Button { selectedItem = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.isDirectory ? "folder" : item.category.symbol).foregroundStyle(.secondary)
                            Text(item.name).font(.system(size: 14)).lineLimit(1).truncationMode(.middle)
                            if item.isHidden { Image(systemName: "eye.slash").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer()
                            Text(RoomFormat.bytes(filter.bytes(in: item)))
                                .font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 10).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !showingAll {
                    Text("From the scan’s largest 100 files.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    private var scanProgress: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.small)
            Text("Finding the big pieces…").font(RoomType.heading(20))
            Text("Measuring file sizes. Your files stay in place.").font(.system(size: 13)).foregroundStyle(.secondary)
            if let progress = insights.diskProgress {
                Text("\(progress.visitedFiles.formatted()) files · \(RoomFormat.bytes(progress.allocatedBytes)) measured")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Text(progress.currentName).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: 440)
            }
            Button("Stop scan") { insights.cancelDiskScan() }.buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
    }
}

private enum RoomDiskFilter: Equatable {
    case all, hidden, large, category(StorageCategory)
    static let largeThreshold: Int64 = 1_000_000_000
    var id: String {
        switch self { case .all: "all"; case .hidden: "hidden"; case .large: "large"; case .category(let value): value.rawValue }
    }
    var title: String {
        switch self { case .all: "All"; case .hidden: "Hidden"; case .large: "Large"; case .category(let value): value.title }
    }
    var symbol: String {
        switch self { case .all: "square.grid.2x2"; case .hidden: "eye.slash"; case .large: "arrow.up.right.square"; case .category(let value): value.symbol }
    }
    var category: StorageCategory? { if case .category(let value) = self { value } else { nil } }
    var mapNote: String {
        switch self {
        case .all: "Tile area = allocated size. Open a folder to look inside."
        case .hidden: "Hidden bytes within each folder, including hidden descendants."
        case .large: "Immediate items of at least 1 GB, including folder totals."
        case .category: "Matching bytes within each folder. Open it to explore."
        }
    }
    func bytes(in item: DiskMapItem) -> Int64 {
        switch self {
        case .all: item.allocatedBytes
        case .hidden: item.hiddenAllocatedBytes
        case .large: item.allocatedBytes >= Self.largeThreshold ? item.allocatedBytes : 0
        case .category(let category): item.categoryAllocatedBytes[category] ?? 0
        }
    }
    func total(in report: DiskMapReport) -> Int64 {
        switch self {
        case .all: report.allocatedBytes
        case .hidden: report.hiddenAllocatedBytes
        case .large: report.children.reduce(Int64(0)) { $0 + bytes(in: $1) }
        case .category(let category): report.categories.first { $0.category == category }?.allocatedBytes ?? 0
        }
    }
    func includes(_ item: DiskMapItem, category: StorageCategory? = nil) -> Bool {
        switch self {
        case .all: true
        case .hidden: item.isHidden
        case .large: item.allocatedBytes >= Self.largeThreshold
        case .category(let selected): (category ?? item.category) == selected
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
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
                        .scaleEffect(hovered == tile.id ? 0.985 : 1)
                    }
                    .buttonStyle(.plain).disabled(tile.entry.item == nil)
                    .offset(x: tile.rect.minX + 2.5, y: tile.rect.minY + 2.5)
                    .help("\(tile.entry.item?.url.path ?? "All remaining measured space")\n\(RoomFormat.bytes(tile.entry.bytes))")
                    .accessibilityLabel("\(tile.entry.name), \(RoomFormat.bytes(tile.entry.bytes))\(tile.entry.item?.isDirectory == true ? ", open folder" : "")")
                    .onHover { hovered = $0 ? tile.id : nil }
                }
            }
            .animation(motionEnabled && !reduceMotion ? .easeOut(duration: 0.16) : nil, value: hovered)
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

private struct RoomDiskItemSheet: View {
    let item: DiskMapItem
    @Bindable var insights: RoomInsightsModel
    @Environment(\.dismiss) private var dismiss
    private var finding: StorageFinding? {
        guard insights.analysisReport?.scanID == insights.diskReport?.id else { return nil }
        return insights.analysisReport?.findings.first { $0.item.id == item.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.isDirectory ? "folder" : item.category.symbol)
                    .font(.system(size: 27, weight: .light)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 9) {
                    Text(item.name).font(RoomType.heading(24)).lineLimit(2)
                    HStack(spacing: 12) {
                        Label(item.category.title, systemImage: item.category.symbol)
                        if item.isHidden { Label("Hidden", systemImage: "eye.slash") }
                    }
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            RoomByteMetric(bytes: item.allocatedBytes, maximumSize: 46)
            Text("Allocated on disk · \(RoomFormat.bytes(item.logicalBytes)) logical size")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if let finding {
                VStack(alignment: .leading, spacing: 11) {
                    RoomDispositionLabel(disposition: finding.disposition)
                    Text(finding.reason).font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(finding.source == .onDevice ? "On-device suggestion · existing protections stay in force" : "Review tag: local rules")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Text(item.url.path).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Button { insights.reveal(item: item) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.glass)
                if item.isDirectory {
                    Button("Look inside") { insights.scanDisk(url: item.url); dismiss() }.buttonStyle(.glass)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(32).frame(width: 580)
    }
}
