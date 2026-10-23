import Foundation
import RoomCore
import SwiftUI

enum RoomMonitorMetric: String, CaseIterable, Identifiable {
    case memory, storage
    var id: String { rawValue }
    var title: String { self == .memory ? "RAM" : "Storage" }
    var symbol: String { self == .memory ? "memorychip" : "internaldrive" }
}

enum RoomPressureTone: Equatable {
    case neutral, normal, elevated, critical
    init(_ pressure: MemoryPressure) {
        switch pressure { case .unknown: self = .neutral; case .normal: self = .normal; case .elevated: self = .elevated; case .critical: self = .critical }
    }
    var title: String {
        switch self { case .neutral: "Unavailable"; case .normal: "Normal"; case .elevated: "Elevated"; case .critical: "High" }
    }
    var color: Color {
        switch self { case .neutral: .secondary; case .normal: .green; case .elevated: .orange; case .critical: .red }
    }
}

struct RoomMonitorPresentation: Equatable {
    let metric: RoomMonitorMetric
    let value: String
    let detail: String
    let tone: RoomPressureTone
    let fraction: Double?

    static func memory(total: Int64, used: Int64, available: Int64, pressure: MemoryPressure,
                       swap: Int64?, showPressure: Bool, showSwap: Bool) -> Self {
        guard total > 0, used > 0 || available > 0 else {
            return Self(metric: .memory, value: "—", detail: "Memory measurement unavailable", tone: .neutral, fraction: nil)
        }
        let measured = max(0, min(total, used))
        var details = ["\(RoomFormat.memoryBytes(measured)) used of \(RoomFormat.memoryBytes(total))"]
        if showPressure { details.append(pressureTitle(pressure)) }
        if showSwap { details.append(swap.map { "\(RoomFormat.memoryBytes(max(0, $0))) swap" } ?? "Swap unavailable") }
        return Self(metric: .memory, value: RoomFormat.memoryBytes(measured), detail: details.joined(separator: " · "),
            tone: showPressure ? RoomPressureTone(pressure) : .neutral, fraction: Double(measured) / Double(total))
    }

    static func storage(total: Int64, available: Int64) -> Self {
        guard total > 0 else { return Self(metric: .storage, value: "—", detail: "Free space unavailable", tone: .neutral, fraction: nil) }
        let free = max(0, min(total, available))
        return Self(metric: .storage, value: RoomFormat.bytes(free), detail: "\(RoomFormat.bytes(free)) available on startup disk", tone: .neutral,
                    fraction: Double(free) / Double(total))
    }

    // MemoryReport currently carries availability failures as notes. Keep a failed
    // swap read distinct from a measured zero until Core exposes a typed signal.
    static func measuredSwap(_ report: MemoryReport) -> Int64? {
        report.issues.contains { $0.hasPrefix("Swap usage could not be read.") } ? nil : report.swapUsedBytes
    }

    static func pressureTitle(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: "Normal pressure"
        case .elevated: "Elevated pressure"
        case .critical: "High pressure"
        case .unknown: "Pressure unavailable"
        }
    }
}

struct RoomAboutInformation: Equatable {
    let name: String
    let version: String?
    let build: String?
    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        func clean(_ key: String) -> String? {
            guard let value = info[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !value.contains("$(") else { return nil }
            return value
        }
        name = clean("CFBundleDisplayName") ?? clean("CFBundleName") ?? "Room"
        version = clean("CFBundleShortVersionString")
        build = clean("CFBundleVersion")
    }
    var versionLabel: String {
        if let version, let build { return "Version \(version) (\(build))" }
        if let version { return "Version \(version)" }
        if let build { return "Build \(build)" }
        return "Development build"
    }
}
