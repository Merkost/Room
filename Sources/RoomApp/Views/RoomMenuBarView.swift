import RoomCore
import SwiftUI

struct RoomMenuBarView: View {
    @Bindable var insights: RoomInsightsModel
    @Bindable var memoryActions: MemoryActionsModel
    @Bindable var cacheModel: RoomViewModel
    let openRoom: () -> Void
    @AppStorage("RoomMenuBarMetric") private var metric = RoomMonitorMetric.memory.rawValue
    @AppStorage("RoomMonitorShowPressure") private var showPressure = true
    @AppStorage("RoomMonitorShowSwap") private var showSwap = true
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selectedMetric: RoomMonitorMetric { RoomMonitorMetric(rawValue: metric) ?? .memory }
    private var memory: RoomMonitorPresentation {
        let report = insights.memoryReport
        return .memory(total: report?.totalBytes ?? 0, used: report?.usedBytes ?? 0,
            available: report?.availableBytes ?? 0, pressure: report?.pressure ?? .unknown,
            swap: report.flatMap(RoomMonitorPresentation.measuredSwap), showPressure: showPressure, showSwap: showSwap)
    }
    private var storage: RoomMonitorPresentation { .storage(total: insights.diskCapacityBytes, available: insights.diskAvailableBytes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                RoomMark().fill(.secondary, style: FillStyle(eoFill: true))
                    .frame(width: 19, height: 19).accessibilityHidden(true)
                Text("Room").font(.system(size: 16, weight: .semibold))
                Spacer()
                if insights.isScanningMemory { ProgressView().controlSize(.small) }
                Button {
                    insights.scanMemory(); insights.refreshDiskCapacity()
                } label: { Image(systemName: "arrow.clockwise").frame(width: 25, height: 25) }
                .buttonStyle(.glass).help("Refresh measurements").accessibilityLabel("Refresh measurements")
                .disabled(insights.isScanningMemory)
            }
            Picker("Menu bar value", selection: $metric) {
                ForEach(RoomMonitorMetric.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .accessibilityIdentifier("RoomMonitorMetricPicker")

            if selectedMetric == .memory {
                memoryCard
                storageCard
            } else {
                storageCard
                memoryCard
            }

            #if !ROOM_APP_STORE
            if memoryActions.selectedCount > 0 {
                Button { show(.memory) } label: {
                    Label("\(memoryActions.selectedCount) selected for review", systemImage: "checkmark.circle")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            #endif
            HStack(spacing: 9) {
                Button(cacheModel.isScanning ? "Stop scan" : "Scan caches") {
                    if cacheModel.isScanning { cacheModel.cancelScan() } else { cacheModel.scan() }
                    show(.clean)
                }
                .buttonStyle(.glass).disabled(!cacheModel.canScan)
                Spacer(minLength: 0)
                Button("Open Room") { openRoom() }.buttonStyle(.glassProminent)
            }.controlSize(.regular)
            if let date = insights.memoryReport?.scannedAt {
                Text("Updated \(date, style: .relative) ago").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(20).frame(width: 320)
        .animation(motionEnabled && !reduceMotion ? .smooth(duration: 0.22) : nil, value: selectedMetric)
        .task {
            memoryActions.refresh(from: insights.memoryReport)
            if insights.memoryReport == nil { insights.scanMemory() }
            insights.refreshDiskCapacity()
        }
        .onChange(of: insights.memoryReport?.id) { _, _ in memoryActions.refresh(from: insights.memoryReport) }
    }

    private var memoryCard: some View {
        Button { show(.memory) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.07), lineWidth: 4)
                    if let fraction = memory.fraction {
                        Circle().trim(from: 0, to: fraction)
                            .stroke(memory.tone.color, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    Image(systemName: "memorychip").font(.system(size: 15, weight: .light)).foregroundStyle(.secondary)
                }.frame(width: 42, height: 42).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Memory").font(.system(size: 14, weight: .medium))
                        Spacer()
                        if memory.fraction != nil { Text(memory.value).font(.system(size: 14, weight: .medium)).monospacedDigit() }
                    }
                    if let report = insights.memoryReport, memory.fraction != nil {
                        Text("of \(RoomFormat.memoryBytes(report.totalBytes)) physical RAM")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        if showPressure {
                            HStack(spacing: 6) {
                                Circle().fill(memory.tone.color).frame(width: 5, height: 5)
                                Text(RoomMonitorPresentation.pressureTitle(report.pressure))
                            }.font(.system(size: 12)).foregroundStyle(memory.tone.color)
                        }
                        if showSwap {
                            Text(RoomMonitorPresentation.measuredSwap(report).map { "\(RoomFormat.memoryBytes($0)) swap used" } ?? "Swap unavailable")
                                .font(.system(size: 12)).monospacedDigit().foregroundStyle(memory.tone.color)
                        }
                    } else {
                        Text(insights.isScanningMemory ? "Reading your Mac…" : "Measurement unavailable")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Open memory overview").accessibilityValue(memory.detail)
    }

    private var storageCard: some View {
        Button { show(.disk) } label: {
            HStack(spacing: 14) {
                Image(systemName: "internaldrive").font(.system(size: 23, weight: .light))
                    .frame(width: 42, height: 42).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Startup disk").font(.system(size: 14, weight: .medium))
                        Spacer()
                        if storage.fraction != nil { Text(storage.value).font(.system(size: 14, weight: .medium)).monospacedDigit() }
                    }
                    Text(storage.fraction == nil ? "Free space unavailable" : "available")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if let fraction = storage.fraction { ProgressView(value: fraction).tint(.secondary).controlSize(.small) }
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Open Disk Map").accessibilityValue(storage.detail)
    }
    private func show(_ destination: RoomInsightDestination) { insights.requestedDestination = destination; openRoom() }
}
