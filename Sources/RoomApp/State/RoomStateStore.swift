import Foundation
import OSLog

nonisolated protocol RoomStateDisk: Sendable {
    /// Nil means the file does not exist. Any other read problem leaves its contents alone.
    func read(_ url: URL, maximumBytes: Int) throws -> Data?
    func replace(_ data: Data, at url: URL) throws
    func createDirectory(_ url: URL) throws
    func move(_ source: URL, to destination: URL) throws
    func remove(_ url: URL) throws
    func names(in url: URL) throws -> [String]
}

nonisolated struct RoomFileStateDisk: RoomStateDisk {
    private let beforeSwap: @Sendable (URL, URL) throws -> Void

    init(beforeSwap: @escaping @Sendable (URL, URL) throws -> Void = { _, _ in }) {
        self.beforeSwap = beforeSwap
    }

    func read(_ url: URL, maximumBytes: Int) throws -> Data? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch CocoaError.fileNoSuchFile {
            return nil
        }
        defer { try? handle.close() }
        // One extra byte distinguishes an exactly capped file from an oversized one.
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw RoomStateError.tooLarge(url.lastPathComponent, data.count) }
        return data
    }

    func replace(_ data: Data, at url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try createDirectory(folder)
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent)-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try beforeSwap(temporary, url)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func move(_ source: URL, to destination: URL) throws { try FileManager.default.moveItem(at: source, to: destination) }
    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
    func names(in url: URL) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: url.path) }
}

actor RoomStateStore {
    static let shared = RoomStateStore()
    nonisolated static let logger = Logger(subsystem: "com.merkost.room", category: "state")

    nonisolated static var defaultDirectory: URL {
        #if DEBUG
        if let testOutput = ProcessInfo.processInfo.environment["ROOM_MAIN_MENU_TEST_OUTPUT"] {
            return URL(fileURLWithPath: testOutput).deletingLastPathComponent()
                .appendingPathComponent("State", isDirectory: true)
        }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Room/State", isDirectory: true)
    }

    nonisolated let directory: URL
    private let appVersion: String
    private let now: @Sendable () -> Date
    private let disk: any RoomStateDisk
    private var writeGate = RoomStateWriteGate()
    private var readOnly: Set<String> = []
    private(set) var damagedFileNames: [String] = []

    init(directory: URL = defaultDirectory,
         appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0",
         now: @Sendable @escaping () -> Date = Date.init, disk: any RoomStateDisk = RoomFileStateDisk()) {
        self.directory = directory
        self.appVersion = appVersion
        self.now = now
        self.disk = disk
    }

    func load<Value: Codable & Sendable>(_ type: Value.Type, from file: RoomStateFile,
                                        legacy: (@Sendable (Data) throws -> Value)? = nil,
                                        migrate: (@Sendable (Int, Data) throws -> Value)? = nil) -> RoomStateLoad<Value> {
        do {
            let url = try location(for: file)
            let data = try disk.read(url, maximumBytes: file.maxBytes)
            let result = RoomStateCodec.decode(data, as: type, file: file, legacy: legacy, migrate: migrate)
            switch result {
            case .loaded(let value, rewrite: true):
                do {
                    try replace(value, file: file, at: url)
                    return .loaded(value, rewrite: false)
                } catch {
                    Self.logger.error("Could not migrate \(file.name, privacy: .private): \(error.localizedDescription, privacy: .private)")
                }
            case .damaged: quarantine(file, from: url)
            case .newerReadOnly: readOnly.insert(file.name)
            case .missing, .loaded: break
            }
            return result
        } catch {
            Self.logger.error("Could not read \(file.name, privacy: .private): \(error.localizedDescription, privacy: .private)")
            // A failed or oversized read must never turn a subsequent empty model state into a write.
            readOnly.insert(file.name)
            return .damaged
        }
    }

    func write<Value: Codable & Sendable>(_ value: Value, to file: RoomStateFile, generation: UInt64) throws {
        var next = writeGate
        guard next.admit(file, generation: generation) else { return }
        guard !readOnly.contains(file.name) else { throw RoomStateError.readOnlyNewerSchema(file.name) }
        let url = try location(for: file)
        if let existing = try disk.read(url, maximumBytes: file.maxBytes),
           case .newer = RoomStateCodec.classify(existing, currentSchema: file.schema) {
            readOnly.insert(file.name)
            throw RoomStateError.readOnlyNewerSchema(file.name)
        }
        try replace(value, file: file, at: url)
        writeGate = next
    }

    @discardableResult
    func writeIfMissing<Value: Codable & Sendable>(_ value: Value, to file: RoomStateFile) throws -> Bool {
        let url = try location(for: file)
        guard !readOnly.contains(file.name),
              try disk.read(url, maximumBytes: file.maxBytes) == nil else { return false }
        try replace(value, file: file, at: url)
        return true
    }

    func remove(_ file: RoomStateFile) {
        do {
            let url = try location(for: file)
            guard !readOnly.contains(file.name) else { return }
            if let data = try disk.read(url, maximumBytes: file.maxBytes),
               case .newer = RoomStateCodec.classify(data, currentSchema: file.schema) {
                readOnly.insert(file.name)
                return
            }
            try disk.remove(url)
        } catch CocoaError.fileNoSuchFile {
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            Self.logger.error("Could not remove \(file.name, privacy: .private): \(error.localizedDescription, privacy: .private)")
        }
    }

    func forgetHistory() -> [String] {
        let history: [RoomStateFile] = [.roomSizes, .volumeSamples, .reports, .weeklyCheck, .pressure, .treeIndex]
        let treeFolder = directory.appendingPathComponent("trees", isDirectory: true)
        let treeNames = (try? disk.names(in: treeFolder)) ?? []
        let trees = treeNames.compactMap { name -> RoomStateFile? in
            guard name.hasSuffix(".json"), name != "index.json" else { return nil }
            let file = RoomStateFile.tree(rootID: String(name.dropLast(5)))
            return file.name == "trees/\(name)" ? file : nil
        }
        return RoomStateForget.filesToRemove(present: history + trees).compactMap { file in
            guard let url = try? location(for: file) else { return nil }
            let existed = (try? disk.read(url, maximumBytes: file.maxBytes)) != nil
            guard existed else { return nil }
            remove(file)
            guard !readOnly.contains(file.name),
                  (try? disk.read(url, maximumBytes: file.maxBytes)) == nil else { return nil }
            return file.name
        }
    }

    private func replace<Value: Codable & Sendable>(_ value: Value, file: RoomStateFile, at url: URL) throws {
        let data = try RoomStateCodec.encode(value, file: file, writtenAt: now(), appVersion: appVersion)
        try disk.createDirectory(directory)
        try disk.replace(data, at: url)
    }

    private func location(for file: RoomStateFile) throws -> URL {
        let components = file.name.split(separator: "/", omittingEmptySubsequences: false)
        guard file.maxBytes > 0, file.maxBytes < Int.max, !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw RoomStateError.unsafeLocation(file.name)
        }
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw RoomStateError.unsafeLocation(file.name)
        }
        var url = directory
        for component in components {
            url.appendPathComponent(String(component))
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw RoomStateError.unsafeLocation(file.name)
            }
        }
        return url
    }

    private func quarantine(_ file: RoomStateFile, from url: URL) {
        do {
            let folder = directory.appendingPathComponent("Damaged", isDirectory: true)
            guard (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                throw RoomStateError.unsafeLocation(file.name)
            }
            try disk.createDirectory(directory)
            try disk.createDirectory(folder)
            var date = now()
            let existing = Set(try disk.names(in: folder))
            var name = RoomStateDamaged.name(for: file, at: date)
            while existing.contains(name) {
                date = date.addingTimeInterval(1)
                name = RoomStateDamaged.name(for: file, at: date)
            }
            try disk.move(url, to: folder.appendingPathComponent(name))
            if !damagedFileNames.contains(file.name) { damagedFileNames.append(file.name) }
            for old in RoomStateDamaged.toDelete(existing: Array(existing) + [name], for: file) {
                try disk.remove(folder.appendingPathComponent(old))
            }
        } catch {
            readOnly.insert(file.name)
            Self.logger.error("Could not set aside \(file.name, privacy: .private): \(error.localizedDescription, privacy: .private)")
        }
    }
}
