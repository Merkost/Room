import Darwin
import Foundation

public struct DiskMapItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int
    public let category: StorageCategory
    public let isHidden: Bool
    public let modifiedAt: Date?
    public let categoryAllocatedBytes: [StorageCategory: Int64]
    public let hiddenAllocatedBytes: Int64

    public init(url: URL, name: String, isDirectory: Bool, allocatedBytes: Int64,
                logicalBytes: Int64, fileCount: Int, category: StorageCategory? = nil,
                isHidden: Bool? = nil, modifiedAt: Date? = nil,
                categoryAllocatedBytes: [StorageCategory: Int64] = [:], hiddenAllocatedBytes: Int64 = 0) {
        self.id = url.path
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
        self.category = category ?? StorageClassification.category(for: url)
        self.isHidden = isHidden ?? StorageClassification.isHiddenPath(url)
        self.modifiedAt = modifiedAt
        self.categoryAllocatedBytes = categoryAllocatedBytes
        self.hiddenAllocatedBytes = hiddenAllocatedBytes
    }
}

public struct DiskScanProgress: Equatable, Sendable {
    public let visitedFiles: Int
    public let allocatedBytes: Int64
    public let currentName: String
}

public struct DiskMapReport: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let scannedAt: Date
    public let children: [DiskMapItem]
    public let largestFiles: [DiskMapItem]
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int
    public let issues: [ScanIssue]
    public let cancelled: Bool
    public let isPartial: Bool
    public let categories: [StorageCategorySummary]
    public let hiddenAllocatedBytes: Int64
    public let hiddenLogicalBytes: Int64
    public let hiddenFileCount: Int

    public init(id: UUID, url: URL, scannedAt: Date, children: [DiskMapItem], largestFiles: [DiskMapItem],
                allocatedBytes: Int64, logicalBytes: Int64, fileCount: Int, issues: [ScanIssue],
                cancelled: Bool, isPartial: Bool, categories: [StorageCategorySummary] = [],
                hiddenAllocatedBytes: Int64 = 0, hiddenLogicalBytes: Int64 = 0, hiddenFileCount: Int = 0) {
        self.id = id; self.url = url; self.scannedAt = scannedAt; self.children = children
        self.largestFiles = largestFiles; self.allocatedBytes = allocatedBytes; self.logicalBytes = logicalBytes
        self.fileCount = fileCount; self.issues = issues; self.cancelled = cancelled; self.isPartial = isPartial
        self.categories = categories; self.hiddenAllocatedBytes = hiddenAllocatedBytes
        self.hiddenLogicalBytes = hiddenLogicalBytes; self.hiddenFileCount = hiddenFileCount
    }
}

/// Reads metadata only. Directory drill-down is another scan of the selected child.
/// Retains immediate children and the largest 100 unique file allocations, not a full tree.
public actor DiskMapEngine {
    private let progressInterval: TimeInterval

    public init() { progressInterval = 0.25 }

    init(progressInterval: TimeInterval) { self.progressInterval = max(0, progressInterval) }

    public func scan(url: URL, progress: (@Sendable (DiskScanProgress) -> Void)? = nil) async -> DiskMapReport {
        let scoped = url.isFileURL && url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var walker = DiskMapWalker(url: url, progressInterval: progressInterval, progress: progress)
        return walker.run()
    }
}

private struct DiskMapWalker {
    let inputURL: URL
    let root: URL
    let progressInterval: TimeInterval
    let progress: (@Sendable (DiskScanProgress) -> Void)?
    private var children: [DiskMapItem] = []
    private var largest = LargestDiskFiles()
    private var measured = DiskTotals()
    private var details: [ScanIssue] = []
    private var omittedIssueCount = 0
    private var errorCount = 0
    private var symbolicLinks = 0
    private var specialItems = 0
    private var repeatedDirectories = 0
    private var sawSharedAllocation = false
    private var seenHardLinks: Set<DiskInode> = []
    private var seenDirectories: Set<DiskInode> = []
    private var cancelled = false
    private var lastProgress = Date.distantPast
    private var currentName: String

    init(url: URL, progressInterval: TimeInterval, progress: (@Sendable (DiskScanProgress) -> Void)?) {
        inputURL = url
        root = url.isFileURL ? url.roomLexicallyNormalized : url
        currentName = url.lastPathComponent
        self.progressInterval = progressInterval
        self.progress = progress
    }

    mutating func run() -> DiskMapReport {
        publishProgress(force: true)
        if Task.isCancelled {
            cancelled = true
        } else if !inputURL.isFileURL || inputURL.path.isEmpty ||
                    (inputURL.host != nil && inputURL.host != "" && inputURL.host != "localhost") {
            recordIssue(root, "Choose a local folder to inspect.")
        } else {
            do {
                let descriptor = try openRoot(root)
                var info = stat()
                guard fstat(descriptor, &info) == 0 else {
                    let code = errno
                    close(descriptor)
                    throw DiskMapFailure("The selected folder could not be inspected: \(systemMessage(code)).")
                }
                let metadata = DiskMetadata(info)
                seenDirectories.insert(metadata.inode)
                // scanDirectory takes ownership of the descriptor on every path.
                _ = scanDirectory(descriptor, url: root, expected: metadata, depth: 0, collectChildren: true, inheritedHidden: StorageClassification.isHiddenPath(root) || metadata.isHidden)
                if !Task.isCancelled {
                    do {
                        let currentDescriptor = try openRoot(root)
                        defer { close(currentDescriptor) }
                        var current = stat()
                        if fstat(currentDescriptor, &current) != 0 || DiskMetadata(current).directoryIdentity != metadata.directoryIdentity {
                            recordIssue(root, "The selected folder changed during the scan. Scan it again before relying on these paths.")
                        }
                    } catch {
                        recordIssue(root, "The selected folder was moved, replaced, or became unavailable during the scan.")
                    }
                }
            } catch { recordIssue(root, error.localizedDescription) }
        }
        cancelled = cancelled || Task.isCancelled
        publishProgress(force: true)
        cancelled = cancelled || Task.isCancelled
        var issues = details
        if omittedIssueCount > 0 {
            issues.append(ScanIssue(url: root, message: "\(omittedIssueCount) additional unreadable or changing items were omitted from this list."))
        }
        if symbolicLinks > 0 {
            issues.append(ScanIssue(url: root, message: "\(symbolicLinks) symbolic links were skipped. Their linked targets were not scanned."))
        }
        if specialItems > 0 {
            issues.append(ScanIssue(url: root, message: "\(specialItems) special filesystem items were skipped; only regular file allocations are measured."))
        }
        if repeatedDirectories > 0 {
            issues.append(ScanIssue(url: root, message: "\(repeatedDirectories) repeated directory identities were skipped to prevent recursive cycles."))
        }
        if sawSharedAllocation {
            issues.append(ScanIssue(url: root, message: "Shared hardlinked file allocations are attributed once, to the first path inspected. Logical sizes and file counts include each file path; storage may also be shared outside this folder."))
        }
        return DiskMapReport(id: UUID(), url: root, scannedAt: Date(),
            children: children.sorted(by: largestFirst), largestFiles: largest.sorted(),
            allocatedBytes: measured.allocatedBytes, logicalBytes: measured.logicalBytes,
            fileCount: measured.fileCount, issues: issues, cancelled: cancelled,
            isPartial: cancelled || errorCount > 0 || symbolicLinks > 0 || specialItems > 0 || repeatedDirectories > 0,
            categories: StorageCategory.allCases.map { category in
                let counts = measured.categories[category] ?? DiskCategoryTotals()
                return StorageCategorySummary(category: category, allocatedBytes: counts.allocatedBytes,
                    logicalBytes: counts.logicalBytes, fileCount: counts.fileCount)
            }, hiddenAllocatedBytes: measured.hiddenAllocatedBytes, hiddenLogicalBytes: measured.hiddenLogicalBytes,
            hiddenFileCount: measured.hiddenFileCount)
    }

    private mutating func scanDirectory(_ descriptor: Int32, url: URL, expected: DiskMetadata,
                                        depth: Int, collectChildren: Bool, inheritedHidden: Bool) -> DiskTotals {
        guard let directory = fdopendir(descriptor) else {
            let code = errno
            close(descriptor)
            recordIssue(url, "This folder could not be read: \(systemMessage(code)).")
            return DiskTotals()
        }
        defer { closedir(directory) }
        var totals = DiskTotals()
        while true {
            if Task.isCancelled {
                cancelled = true
                break
            }
            currentName = url.lastPathComponent
            publishProgress()
            errno = 0
            guard let entry = readdir(directory) else {
                let code = errno
                if code != 0 { recordIssue(url, "This folder could not be completely read: \(systemMessage(code)).") }
                break
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(validatingCString: $0)
                }
            }
            guard let name else {
                recordIssue(url, "A filename could not be decoded safely and was skipped.")
                continue
            }
            guard name != ".", name != ".." else { continue }
            let childURL = url.appendingPathComponent(name, isDirectory: false)
            let child = scanItem(parent: descriptor, name: name, url: childURL, depth: depth + 1, inheritedHidden: inheritedHidden)
            totals.add(child.totals)
            if collectChildren { children.append(child.item) }
            if cancelled { break }
        }
        if !cancelled {
            var finished = stat()
            if fstat(descriptor, &finished) != 0 || DiskMetadata(finished).directoryIdentity != expected.directoryIdentity {
                recordIssue(url, "This folder changed during the scan. Its displayed size is based on the entries that were inspected.")
            }
        }
        return totals
    }

    private mutating func scanItem(parent: Int32, name: String, url: URL, depth: Int, inheritedHidden: Bool) -> (item: DiskMapItem, totals: DiskTotals) {
        if Task.isCancelled {
            cancelled = true
            return (item(url, isDirectory: false, totals: DiskTotals()), DiskTotals())
        }
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            recordIssue(url, "This item could not be inspected: \(systemMessage(errno)).")
            return (item(url, isDirectory: false, totals: DiskTotals()), DiskTotals())
        }
        let metadata = DiskMetadata(info)
        let hidden = inheritedHidden || name.hasPrefix(".") || metadata.isHidden
        currentName = name
        if metadata.isSymbolicLink {
            symbolicLinks += 1
            return (item(url, isDirectory: false, totals: DiskTotals()), DiskTotals())
        }
        if metadata.isRegular {
            var attributedBytes = metadata.allocatedBytes
            var isFirstAllocation = true
            if metadata.linkCount > 1 {
                sawSharedAllocation = true
                isFirstAllocation = seenHardLinks.insert(metadata.inode).inserted
                if !isFirstAllocation { attributedBytes = 0 }
            }
            let category = StorageClassification.category(for: url)
            let totals = DiskTotals.file(allocatedBytes: attributedBytes, logicalBytes: metadata.logicalBytes,
                category: category, isHidden: hidden)
            measured.add(totals)
            let result = item(url, isDirectory: false, totals: totals, isHidden: hidden, modifiedAt: metadata.modifiedAt)
            if isFirstAllocation { largest.offer(result) }
            publishProgress()
            return (result, totals)
        }
        guard metadata.isDirectory else {
            specialItems += 1
            return (item(url, isDirectory: false, totals: DiskTotals()), DiskTotals())
        }
        guard depth < 128 else {
            recordIssue(url, "The folder nesting is unusually deep. Scan this folder separately to inspect its contents.")
            return (item(url, isDirectory: true, totals: DiskTotals()), DiskTotals())
        }
        guard seenDirectories.insert(metadata.inode).inserted else {
            repeatedDirectories += 1
            return (item(url, isDirectory: true, totals: DiskTotals()), DiskTotals())
        }
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            recordIssue(url, "This folder could not be opened without following links: \(systemMessage(errno)).")
            return (item(url, isDirectory: true, totals: DiskTotals()), DiskTotals())
        }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, DiskMetadata(opened).directoryIdentity == metadata.directoryIdentity else {
            close(descriptor)
            recordIssue(url, "This folder was replaced or changed before it could be inspected.")
            return (item(url, isDirectory: true, totals: DiskTotals()), DiskTotals())
        }
        let totals = scanDirectory(descriptor, url: url, expected: metadata, depth: depth, collectChildren: false, inheritedHidden: hidden)
        return (item(url, isDirectory: true, totals: totals, isHidden: hidden, modifiedAt: metadata.modifiedAt), totals)
    }

    private func item(_ url: URL, isDirectory: Bool, totals: DiskTotals, isHidden: Bool? = nil, modifiedAt: Date? = nil) -> DiskMapItem {
        DiskMapItem(url: url, name: url.lastPathComponent, isDirectory: isDirectory,
            allocatedBytes: totals.allocatedBytes, logicalBytes: totals.logicalBytes, fileCount: totals.fileCount,
            isHidden: isHidden, modifiedAt: modifiedAt,
            categoryAllocatedBytes: totals.categories.mapValues(\.allocatedBytes), hiddenAllocatedBytes: totals.hiddenAllocatedBytes)
    }

    private mutating func recordIssue(_ url: URL, _ message: String) {
        errorCount += 1
        if details.count < 100 { details.append(ScanIssue(url: url, message: message)) }
        else { omittedIssueCount += 1 }
    }

    private mutating func publishProgress(force: Bool = false) {
        guard let progress else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastProgress) >= progressInterval else { return }
        lastProgress = now
        progress(DiskScanProgress(visitedFiles: measured.fileCount, allocatedBytes: measured.allocatedBytes,
            currentName: currentName))
    }

    private func openRoot(_ url: URL) throws -> Int32 {
        let components = url.pathComponents.filter { $0 != "/" }
        // Approved child access needs search permission through its ancestors,
        // not permission to enumerate those broader folders.
        var descriptor = open("/", (components.isEmpty ? O_RDONLY : O_SEARCH) | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DiskMapFailure("The filesystem root could not be opened.") }
        for (index, component) in components.enumerated() {
            let accessMode = index == components.count - 1 ? O_RDONLY : O_SEARCH
            let next = openat(descriptor, component, accessMode | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let code = errno
            close(descriptor)
            guard next >= 0 else {
                throw DiskMapFailure("The selected path is unavailable, is not a folder, or contains a symbolic link: \(systemMessage(code)).")
            }
            descriptor = next
        }
        return descriptor
    }
}

private struct DiskCategoryTotals {
    var allocatedBytes: Int64 = 0
    var logicalBytes: Int64 = 0
    var fileCount: Int = 0
}

private struct DiskTotals {
    var allocatedBytes: Int64 = 0
    var logicalBytes: Int64 = 0
    var fileCount: Int = 0
    var categories: [StorageCategory: DiskCategoryTotals] = [:]
    var hiddenAllocatedBytes: Int64 = 0
    var hiddenLogicalBytes: Int64 = 0
    var hiddenFileCount: Int = 0

    static func file(allocatedBytes: Int64, logicalBytes: Int64, category: StorageCategory, isHidden: Bool) -> DiskTotals {
        DiskTotals(allocatedBytes: allocatedBytes, logicalBytes: logicalBytes, fileCount: 1,
            categories: [category: DiskCategoryTotals(allocatedBytes: allocatedBytes, logicalBytes: logicalBytes, fileCount: 1)],
            hiddenAllocatedBytes: isHidden ? allocatedBytes : 0, hiddenLogicalBytes: isHidden ? logicalBytes : 0,
            hiddenFileCount: isHidden ? 1 : 0)
    }

    mutating func add(_ other: DiskTotals) {
        allocatedBytes += other.allocatedBytes; logicalBytes += other.logicalBytes; fileCount += other.fileCount
        hiddenAllocatedBytes += other.hiddenAllocatedBytes; hiddenLogicalBytes += other.hiddenLogicalBytes
        hiddenFileCount += other.hiddenFileCount
        for (category, counts) in other.categories {
            var current = categories[category] ?? DiskCategoryTotals()
            current.allocatedBytes += counts.allocatedBytes; current.logicalBytes += counts.logicalBytes
            current.fileCount += counts.fileCount; categories[category] = current
        }
    }
}

private struct DiskInode: Hashable {
    let device: Int32
    let inode: UInt64
}

private struct DiskDirectoryIdentity: Equatable {
    let inode: DiskInode
    let mode: UInt16
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

private struct DiskMetadata {
    let inode: DiskInode
    let directoryIdentity: DiskDirectoryIdentity
    let mode: UInt16
    let allocatedBytes: Int64
    let logicalBytes: Int64
    let linkCount: UInt16
    let isHidden: Bool
    let modifiedAt: Date
    var type: UInt16 { mode & UInt16(S_IFMT) }
    var isDirectory: Bool { type == UInt16(S_IFDIR) }
    var isRegular: Bool { type == UInt16(S_IFREG) }
    var isSymbolicLink: Bool { type == UInt16(S_IFLNK) }

    init(_ info: stat) {
        inode = DiskInode(device: info.st_dev, inode: UInt64(info.st_ino))
        directoryIdentity = DiskDirectoryIdentity(inode: inode, mode: info.st_mode,
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
        mode = info.st_mode
        allocatedBytes = max(0, Int64(info.st_blocks) * 512)
        logicalBytes = max(0, Int64(info.st_size))
        linkCount = info.st_nlink
        isHidden = info.st_flags & UInt32(UF_HIDDEN) != 0
        modifiedAt = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }
}

private struct DiskMapFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private func systemMessage(_ code: Int32) -> String { String(cString: strerror(code)) }

private func largestFirst(_ lhs: DiskMapItem, _ rhs: DiskMapItem) -> Bool {
    if lhs.allocatedBytes != rhs.allocatedBytes { return lhs.allocatedBytes > rhs.allocatedBytes }
    if lhs.logicalBytes != rhs.logicalBytes { return lhs.logicalBytes > rhs.logicalBytes }
    return lhs.id < rhs.id
}

/// A fixed-size min heap keeps only the largest allocations during streaming traversal.
private struct LargestDiskFiles {
    private var heap: [DiskMapItem] = []

    mutating func offer(_ item: DiskMapItem) {
        if heap.count < 100 {
            heap.append(item)
            var index = heap.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard largestFirst(heap[parent], heap[index]) else { break }
                heap.swapAt(parent, index)
                index = parent
            }
        } else if let minimum = heap.first, largestFirst(item, minimum) {
            heap[0] = item
            var index = 0
            while true {
                let left = index * 2 + 1
                guard left < heap.count else { break }
                let right = left + 1
                let smaller = right < heap.count && largestFirst(heap[left], heap[right]) ? right : left
                guard largestFirst(heap[index], heap[smaller]) else { break }
                heap.swapAt(index, smaller)
                index = smaller
            }
        }
    }

    func sorted() -> [DiskMapItem] { heap.sorted(by: largestFirst) }
}
