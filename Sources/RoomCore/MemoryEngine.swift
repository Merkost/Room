import Darwin
import Dispatch
import Foundation

public enum MemoryPressure: String, Codable, CaseIterable, Sendable {
    case normal
    case elevated
    case critical
    case unknown
}

public struct MemoryProcess: Identifiable, Equatable, Sendable {
    public let id: Int32
    public let name: String
    /// Resident set size, including pages that may also be shared with other processes.
    public let residentBytes: Int64

    public init(id: Int32, name: String, residentBytes: Int64) {
        self.id = id
        self.name = name
        self.residentBytes = residentBytes
    }
}

public struct MemoryRecommendation: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct MemoryReport: Identifiable, Sendable {
    public let id: UUID
    public let scannedAt: Date
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64
    public let compressedBytes: Int64
    public let swapUsedBytes: Int64
    public let pressure: MemoryPressure
    public let processes: [MemoryProcess]
    public let recommendations: [MemoryRecommendation]
    public let issues: [String]
}

/// Reads host memory counters and executable RSS only. It never purges memory,
/// changes a setting, sends a signal, or opens process arguments or contents.
public actor MemoryEngine {
    public init() { }

    public func scan() async -> MemoryReport {
        let scannedAt = Date()
        var issues: [String] = []
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let total = Int64(clamping: physicalMemory)
        var metrics = MemoryMetrics(totalBytes: total, usedBytes: 0, availableBytes: 0, compressedBytes: 0)
        do { metrics = try Self.readHostMetrics(totalBytes: total) }
        catch { issues.append(error.localizedDescription) }

        var swapUsed: Int64 = 0
        do { swapUsed = try Self.readSwapUsage() }
        catch { issues.append(error.localizedDescription) }

        var pressure = MemoryPressure.unknown
        do {
            pressure = Self.pressure(fromDispatchFlags: try Self.readPressureFlags())
            if pressure == .unknown { issues.append("macOS returned an unrecognized memory pressure state. Check Activity Monitor.") }
        } catch { issues.append(error.localizedDescription) }

        var processes: [MemoryProcess] = []
        if !Task.isCancelled {
            do { processes = try Self.readProcesses() }
            catch { issues.append(error.localizedDescription) }
        } else {
            issues.append("The memory scan was cancelled before process measurement completed.")
        }

        return MemoryReport(id: UUID(), scannedAt: scannedAt, totalBytes: metrics.totalBytes,
            usedBytes: metrics.usedBytes, availableBytes: metrics.availableBytes,
            compressedBytes: metrics.compressedBytes, swapUsedBytes: swapUsed, pressure: pressure,
            processes: processes,
            recommendations: Self.recommendations(pressure: pressure, totalBytes: total,
                swapUsedBytes: swapUsed, processes: processes), issues: issues)
    }

    private static func readHostMetrics(totalBytes: Int64) throws -> MemoryMetrics {
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            throw MemoryReadError.message("The system RAM page size could not be read.")
        }
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MemoryReadError.message("The system RAM counters could not be read (Mach error \(result)).")
        }
        return MemoryMetrics.calculate(totalBytes: totalBytes, pageSize: UInt64(pageSize),
            internalPages: UInt64(statistics.internal_page_count), purgeablePages: UInt64(statistics.purgeable_count),
            wiredPages: UInt64(statistics.wire_count), compressorPages: UInt64(statistics.compressor_page_count))
    }

    private static func readSwapUsage() throws -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0,
              size == MemoryLayout<xsw_usage>.size else {
            throw MemoryReadError.message("Swap usage could not be read. Check Activity Monitor for its current value.")
        }
        return Int64(clamping: usage.xsu_used)
    }

    private static func readPressureFlags() throws -> UInt32 {
        var flags: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &flags, &size, nil, 0) == 0,
              size == MemoryLayout<UInt32>.size else {
            throw MemoryReadError.message("The macOS memory pressure signal is unavailable. RAM occupancy is not a pressure measurement.")
        }
        return flags
    }

    /// XNU's sysctl handler converts its internal level to the Dispatch flags,
    /// rather than returning the different 0/1/2/3 internal enum values.
    /// Primary source: apple-oss-distributions/xnu, kern_memorystatus_notify.c,
    /// sysctl_memorystatus_vm_pressure_level; SDK dispatch/source.h defines 1/2/4.
    static func pressure(fromDispatchFlags flags: UInt32) -> MemoryPressure {
        switch UInt(flags) {
        case DispatchSource.MemoryPressureEvent.normal.rawValue: .normal
        case DispatchSource.MemoryPressureEvent.warning.rawValue: .elevated
        case DispatchSource.MemoryPressureEvent.critical.rawValue: .critical
        default: .unknown
        }
    }

    private static func readProcesses() throws -> [MemoryProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // comm is the executable name, never the command's private arguments.
        process.arguments = ["-axww", "-o", "pid=,rss=,comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain before waitUntilExit: a large process list can fill the pipe.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw MemoryReadError.message("Process memory could not be measured. The host RAM counters are still available.")
        }
        let processes = parseProcesses(text)
        guard !processes.isEmpty else {
            throw MemoryReadError.message("No process memory rows were available. Check Activity Monitor for more detail.")
        }
        return processes
    }

    static func parseProcesses(_ text: String) -> [MemoryProcess] {
        text.split(separator: "\n").compactMap { line -> MemoryProcess? in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), pid > 0,
                  let kibibytes = Int64(fields[1]), kibibytes >= 0,
                  kibibytes <= Int64.max / 1024 else { return nil }
            let executable = String(fields[2]).trimmingCharacters(in: .whitespaces)
            let name = URL(fileURLWithPath: executable).lastPathComponent
            guard !name.isEmpty, name != "/" else { return nil }
            return MemoryProcess(id: pid, name: name, residentBytes: kibibytes * 1024)
        }.sorted {
            $0.residentBytes == $1.residentBytes ? $0.id < $1.id : $0.residentBytes > $1.residentBytes
        }.prefix(12).map { $0 }
    }

    static func recommendations(pressure: MemoryPressure, totalBytes: Int64,
                                swapUsedBytes: Int64, processes: [MemoryProcess]) -> [MemoryRecommendation] {
        var result: [MemoryRecommendation]
        switch pressure {
        case .normal:
            result = [MemoryRecommendation(id: "normal", title: "No RAM optimization needed",
                detail: "macOS reports normal memory pressure. It uses spare RAM for caches and reclaims it when apps need it.")]
        case .elevated:
            result = [MemoryRecommendation(id: "pressure", title: "Reduce your active workload",
                detail: "macOS reports elevated memory pressure. Finish or pause unused apps, browser tabs, and parallel agents or builds, then scan again.")]
        case .critical:
            result = [MemoryRecommendation(id: "pressure", title: "Give your Mac some breathing room",
                detail: "macOS reports critical memory pressure. Save your work, then quit apps you are not using normally and scan again.")]
        case .unknown:
            result = [MemoryRecommendation(id: "pressure-unavailable", title: "Check pressure in Activity Monitor",
                detail: "The system pressure signal could not be confirmed. A high RAM percentage alone does not mean your Mac needs optimization.")]
        }
        if pressure == .elevated || pressure == .critical,
           let largest = processes.first, largest.residentBytes >= max(1_073_741_824, totalBytes / 10) {
            let amount = ByteCountFormatter.string(fromByteCount: largest.residentBytes, countStyle: .memory)
            result.append(MemoryRecommendation(id: "largest-process", title: "Review \(largest.name)",
                detail: "This process has \(amount) resident in RAM. Inspect it in Activity Monitor before deciding whether to quit its app; shared pages may also appear in other processes."))
        }
        if swapUsedBytes > 0 {
            let amount = ByteCountFormatter.string(fromByteCount: swapUsedBytes, countStyle: .memory)
            result.append(MemoryRecommendation(id: "swap", title: "\(amount) of swap is in use",
                detail: "Swap uses startup disk space and may remain allocated after earlier demand. Its size alone does not prove active swapping or a current slowdown."))
        }
        return result
    }
}

struct MemoryMetrics: Equatable, Sendable {
    let totalBytes: Int64
    let usedBytes: Int64
    let availableBytes: Int64
    let compressedBytes: Int64

    static func calculate(totalBytes: Int64, pageSize: UInt64, internalPages: UInt64,
                          purgeablePages: UInt64, wiredPages: UInt64, compressorPages: UInt64) -> MemoryMetrics {
        let total = max(0, totalBytes)
        func bytes(_ pages: UInt64) -> Int64 {
            let (value, overflow) = pages.multipliedReportingOverflow(by: pageSize)
            return overflow ? Int64.max : Int64(clamping: value)
        }
        func sum(_ first: Int64, _ second: Int64) -> Int64 {
            let (value, overflow) = first.addingReportingOverflow(second)
            return overflow ? Int64.max : value
        }
        // Estimate in-use physical RAM as anonymous nonpurgeable + wired +
        // physical compressor storage. Purgeable pages are a subset of anonymous
        // pages, so subtract them rather than counting that reclaimable cache as
        // app use. Never add active/inactive queues to internal/external counts:
        // they describe overlapping page classifications. Likewise speculative
        // pages are already in free_count. The compressor's uncompressed logical
        // page count and disk swap are never added to physical RAM use.
        // compressedBytes is already included in usedBytes, not another segment.
        // availableBytes = total - used is an estimate including cached and
        // reclaimable RAM; it is not just free pages or an OS pressure signal.
        let anonymous = bytes(internalPages > purgeablePages ? internalPages - purgeablePages : 0)
        let compressed = min(total, bytes(compressorPages))
        let used = min(total, sum(sum(anonymous, bytes(wiredPages)), compressed))
        return MemoryMetrics(totalBytes: total, usedBytes: used,
            availableBytes: total - used, compressedBytes: compressed)
    }
}

private enum MemoryReadError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
