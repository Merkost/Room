#if ROOM_APP_STORE
import Foundation

/// The Store edition never discovers or executes an external model runtime.
actor LocalModelRuntime {
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, startupTimeout: TimeInterval = 90) { }
    func availability() -> StorageAIAvailability {
        StorageAIAvailability(isAvailable: false,
            reason: "The App Store edition uses Apple Intelligence when available, with rule-based analysis otherwise.")
    }
    func generate(_ candidates: [StorageModelCandidate]) throws -> LocalModelResult {
        throw LocalModelFailure.unavailableInStore
    }
    static func shutdownOwnedWorkers() { }
}
struct LocalModelResult: Sendable { let labels: [StorageModelLabel]; let availability: StorageAIAvailability }
enum LocalModelFailure: Error {
    case unavailableInStore
    var reason: String { "External model runtimes are unavailable in the App Store edition. Rule-based results remain available." }
}
#else
import Darwin
import Foundation
import Synchronization

/// Runs an already installed official runtime as a private, text-only owned child.
/// No model/runtime downloads, LM Studio daemon, remote device, or app settings.
actor LocalModelRuntime {
    private let home: URL
    private let startupTimeout: TimeInterval
    private let client = LocalModelClient()
    private var isGenerating = false

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, startupTimeout: TimeInterval = 90) {
        self.home = home; self.startupTimeout = startupTimeout
    }

    func availability() -> StorageAIAvailability {
        let ready = runtimeExecutable() != nil && (try? discoveredModel()) != nil
        return StorageAIAvailability(isAvailable: ready,
            reason: ready ? "An existing local model can analyze up to 3 items on this Mac. CPU analysis may take a few minutes; its private worker is stopped afterwards."
                : "Local analysis needs an installed runtime and a supported GGUF model within the memory budget. Room does not download models or runtimes.",
            provider: "Local model")
    }

    func generate(_ candidates: [StorageModelCandidate]) async throws -> LocalModelResult {
        guard !isGenerating else { throw LocalModelFailure.busy }
        guard !candidates.isEmpty, candidates.count <= 3 else { throw LocalModelFailure.invalidResponse }
        isGenerating = true
        defer { isGenerating = false }
        guard let executable = runtimeExecutable() else { throw LocalModelFailure.missingRuntime }
        let model = try discoveredModel()
        let identifier = "room-" + UUID().uuidString.lowercased()
        let token = UUID().uuidString + UUID().uuidString
        let port = try Self.unoccupiedPort()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        let keyURL = directory.appendingPathComponent("api-key", isDirectory: false)
        let keyFD = open(keyURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard keyFD >= 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw LocalModelFailure.serviceUnavailable
        }
        let key = Array(token.utf8)
        let written = key.withUnsafeBytes { Darwin.write(keyFD, $0.baseAddress, key.count) }
        close(keyFD)
        guard written == key.count else {
            try? FileManager.default.removeItem(at: directory)
            throw LocalModelFailure.serviceUnavailable
        }
        let endpoint = OwnedLocalEndpoint(port: port, token: token, identifier: identifier)
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.serverArguments(modelURL: model.url, endpoint: endpoint, keyURL: keyURL)
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var registered = false
        do {
            try Task.checkCancellation()
            try OwnedModelWorkers.shared.start(id: identifier, process: process, directory: directory)
            registered = true
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(startupTimeout))
            var ready = false
            while clock.now < deadline {
                try Task.checkCancellation()
                guard process.isRunning else { throw LocalModelFailure.serviceUnavailable }
                if try await Self.listenerIsOwned(process: process, port: port) {
                    if (try? await client.isReady(endpoint: endpoint)) == true { ready = true; break }
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            guard ready else { throw LocalModelFailure.timedOut }
            var labels: [StorageModelLabel] = []
            for candidate in candidates {
                try Task.checkCancellation()
                guard process.isRunning, try await Self.listenerIsOwned(process: process, port: port),
                      try await client.isReady(endpoint: endpoint) else { throw LocalModelFailure.serviceUnavailable }
                labels += try await client.generate(endpoint: endpoint, candidates: [candidate])
            }
            try Task.checkCancellation()
            let stopped = await OwnedModelWorkers.shared.stop(id: identifier)
            guard stopped else { throw LocalModelFailure.releaseFailed }
            return LocalModelResult(labels: labels, availability: StorageAIAvailability(isAvailable: true,
                reason: "Metadata was analyzed by a private CPU worker on this Mac. The worker exited and its temporary key was removed.",
                provider: "Local model", modelName: model.url.deletingPathExtension().lastPathComponent))
        } catch {
            if registered { _ = await OwnedModelWorkers.shared.stop(id: identifier) }
            else { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }

    static func shutdownOwnedWorkers() { OwnedModelWorkers.shared.shutdown() }

    private func runtimeExecutable() -> URL? {
        var choices: [URL] = []
        for relative in [".lmstudio/extensions/backends", ".cache/lm-studio/extensions/backends"] {
            let root = home.appendingPathComponent(relative, isDirectory: true)
            guard Self.isPhysicalItem(root, directory: true),
                  let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            #if arch(arm64)
            let runtimePrefix = "llama.cpp-mac-arm64-"
            #elseif arch(x86_64)
            let runtimePrefix = "llama.cpp-mac-x64-"
            #else
            let runtimePrefix = "unsupported-runtime-architecture-"
            #endif
            for entry in entries where entry.lastPathComponent.hasPrefix(runtimePrefix) {
                let executable = entry.appendingPathComponent("llama-server", isDirectory: false)
                if Self.isPhysicalItem(executable, directory: false), access(executable.path, X_OK) == 0 { choices.append(executable) }
            }
        }
        return choices.sorted { $0.path.compare($1.path, options: .numeric) == .orderedDescending }.first
    }

    func discoveredModel() throws -> LocalModelFile {
        var choices: [LocalModelFile] = []
        for root in Self.modelRoots(home: home) {
            guard Self.isPhysicalItem(root, directory: true),
                  let owners = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for owner in owners.prefix(100) where Self.isPhysicalItem(owner, directory: true) {
                guard let repositories = try? FileManager.default.contentsOfDirectory(at: owner, includingPropertiesForKeys: nil) else { continue }
                for repository in repositories.prefix(100) where Self.isPhysicalItem(repository, directory: true) {
                    guard let files = try? FileManager.default.contentsOfDirectory(at: repository, includingPropertiesForKeys: nil) else { continue }
                    for url in files.prefix(200) where url.pathExtension.lowercased() == "gguf" && !url.lastPathComponent.lowercased().hasPrefix("mmproj") {
                        guard let model = try? Self.inspectModel(url) else { continue }
                        choices.append(model)
                    }
                }
            }
        }
        guard let model = choices.min(by: { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes < $1.bytes }) else {
            throw LocalModelFailure.missingModel
        }
        return model
    }

    static let modelMemoryBudget = Int64(min(UInt64(8) * 1_024 * 1_024 * 1_024, ProcessInfo.processInfo.physicalMemory / 4))

    static func inspectModel(_ url: URL, maximumBytes: Int64 = modelMemoryBudget) throws -> LocalModelFile {
        guard isPhysicalItem(url, directory: false), url.pathExtension.lowercased() == "gguf",
              !url.lastPathComponent.lowercased().hasPrefix("mmproj") else { throw LocalModelFailure.missingModel }
        let descriptor = try openPhysicalItem(url, directory: false)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size > 0, maximumBytes > 0, Int64(info.st_size) <= maximumBytes else { throw LocalModelFailure.missingModel }
        // This is the installed model's format metadata, never scanned user-file contents.
        let prefix = try handle.read(upToCount: 65_536) ?? Data()
        var reader = GGUFMetadataReader(data: prefix)
        let architecture = try reader.architecture()
        let supported: Set<String> = ["gemma4", "gemma3", "gemma2", "gemma", "llama", "qwen2", "qwen2moe", "qwen3", "qwen3moe", "qwen35", "qwen35moe", "mistral", "phi3", "phi2", "gpt2", "gptneox", "falcon", "granite", "starcoder2", "olmo", "olmo2", "internlm2", "deepseek2"]
        guard supported.contains(architecture) else { throw LocalModelFailure.missingModel }
        return LocalModelFile(url: url, bytes: Int64(info.st_size), architecture: architecture)
    }

    static func serverArguments(modelURL: URL, endpoint: OwnedLocalEndpoint, keyURL: URL) -> [String] {
        ["--model", modelURL.path, "--alias", endpoint.identifier, "--host", "127.0.0.1", "--port", String(endpoint.port),
         "--api-key-file", keyURL.path, "--offline", "--no-webui", "--no-agent", "--no-ui-mcp-proxy", "--no-slots", "--no-mmproj",
         "--device", "none", "--gpu-layers", "0", "--no-op-offload", "--no-kv-offload", "--load-mode", "mmap", "--lazy-mode", "off",
         "--no-repack", "--ctx-size", "2048", "--parallel", "1", "--batch-size", "64", "--ubatch-size", "64", "--cache-ram", "0",
         "--ctx-checkpoints", "0", "--no-cache-prompt", "--no-warmup", "--reasoning", "off", "--reasoning-budget", "0", "--predict", "128",
         "--threads", "4", "--threads-batch", "4", "--threads-http", "1", "--poll", "0", "--sleep-idle-seconds", "120", "--log-disable"]
    }

    static func listenerIsOwned(process: Process, port: Int) async throws -> Bool {
        guard process.isRunning, (1_024...65_535).contains(port) else { return false }
        let output = try await runCLI(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-p", String(process.processIdentifier), "-iTCP:\(port)", "-sTCP:LISTEN"], timeout: 3,
            allowNonzero: true)
        return process.isRunning && output.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count > 8 && fields[1] == String(process.processIdentifier) &&
                line.contains("127.0.0.1:\(port) (LISTEN)") && !line.contains("*: \(port)")
        }
    }

    static func validModelKey(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 160 && value.first != "-" && value.first != "/" &&
            !value.contains("..") && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/").contains($0)
            }
    }

    static func unoccupiedPort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw LocalModelFailure.serviceUnavailable }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        guard bound == 0, named == 0 else { throw LocalModelFailure.serviceUnavailable }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private static func modelRoots(home: URL) -> [URL] {
        [".lmstudio/models", ".cache/lm-studio/models"].map { home.appendingPathComponent($0, isDirectory: true) }
    }
    static func isPhysicalItem(_ url: URL, directory: Bool) -> Bool {
        guard let descriptor = try? openPhysicalItem(url, directory: directory) else { return false }
        close(descriptor)
        return true
    }
    private static func openPhysicalItem(_ url: URL, directory: Bool) throws -> Int32 {
        let components = url.roomLexicallyNormalized.pathComponents.filter { $0 != "/" }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LocalModelFailure.missingModel }
        for (index, component) in components.enumerated() {
            let final = index == components.count - 1
            let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | ((!final || directory) ? O_DIRECTORY : O_NONBLOCK)
            let next = openat(descriptor, component, flags)
            close(descriptor)
            guard next >= 0 else { throw LocalModelFailure.missingModel }
            descriptor = next
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & UInt16(S_IFMT) == UInt16(directory ? S_IFDIR : S_IFREG),
              directory || info.st_size > 0 else { close(descriptor); throw LocalModelFailure.missingModel }
        return descriptor
    }
    static func runCLI(executable: URL, arguments: [String], timeout: TimeInterval, allowNonzero: Bool = false) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { throw LocalModelFailure.serviceUnavailable }
        var output = Data()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        try process.run()
        // Parent must not keep a write end open, otherwise EOF is impossible.
        try? pipe.fileHandleForWriting.close()
        defer {
            if process.isRunning { process.interrupt() }
            try? pipe.fileHandleForReading.close()
        }
        func drain() throws -> Bool {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    guard output.count + count <= 128_000 else { throw LocalModelFailure.oversizedResponse }
                    output.append(contentsOf: buffer.prefix(count))
                } else if count == 0 { return true }
                else if errno == EAGAIN || errno == EWOULDBLOCK { return false }
                else if errno != EINTR { throw LocalModelFailure.serviceUnavailable }
            }
        }
        do {
            while process.isRunning {
                _ = try drain()
                try Task.checkCancellation()
                guard clock.now < deadline else { throw LocalModelFailure.timedOut }
                try await Task.sleep(for: .milliseconds(25))
            }
            // A final drain after exit retains bytes written between EAGAIN and
            // termination. A descendant retaining stdout cannot hang this task.
            let finalDeadline = clock.now.advanced(by: .milliseconds(300))
            while try !drain() {
                try Task.checkCancellation()
                guard clock.now < finalDeadline else { throw LocalModelFailure.timedOut }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch {
            // Interrupt the trusted tool first. Escalation targets only this
            // owned child, never another app or a global service.
            await Task.detached(priority: .utility) {
                if process.isRunning { process.interrupt() }
                let first = ContinuousClock.now.advanced(by: .milliseconds(300))
                while process.isRunning, ContinuousClock.now < first { try? await Task.sleep(for: .milliseconds(20)) }
                if process.isRunning { process.terminate() }
                let second = ContinuousClock.now.advanced(by: .milliseconds(300))
                while process.isRunning, ContinuousClock.now < second { try? await Task.sleep(for: .milliseconds(20)) }
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            }.value
            throw error
        }
        guard process.terminationStatus == 0 || allowNonzero else { throw LocalModelFailure.serviceUnavailable }
        return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LocalModelFile: Sendable { let url: URL; let bytes: Int64; let architecture: String }
struct LocalModelResult: Sendable { let labels: [StorageModelLabel]; let availability: StorageAIAvailability }
struct OwnedLocalEndpoint: Sendable { let port: Int; let token: String; let identifier: String }

enum LocalModelFailure: Error {
    case missingRuntime, missingModel, serviceUnavailable, invalidResponse, oversizedResponse, timedOut, busy, releaseFailed
    var reason: String {
        switch self {
        case .missingRuntime: "No supported installed local runtime was found. Room does not download runtimes."
        case .missingModel: "No supported local GGUF language model fits the memory budget in the default model folders. Room uses at most one quarter of physical memory or 8 GB of model weights and does not download models."
        case .serviceUnavailable: "The private local worker could not start or complete this request. Rule-based results remain available."
        case .invalidResponse: "The local model response could not be validated. Rule-based results are shown."
        case .oversizedResponse: "The local response exceeded the bounded size limit. Rule-based results are shown."
        case .timedOut: "The local model exceeded its time limit. Rule-based results are shown."
        case .busy: "A local analysis is already finishing. Try again shortly."
        case .releaseFailed: "The private worker is still stopping. Its idle limit releases model memory; rule-based results are shown."
        }
    }
}

final class OwnedModelWorkers: Sendable {
    static let shared = OwnedModelWorkers()
    struct Worker: Sendable { let process: Process; let directory: URL }
    struct State: Sendable { var shuttingDown = false; var workers: [String: Worker] = [:] }
    private let state = Mutex(State())
    func start(id: String, process: Process, directory: URL) throws {
        try state.withLock { value in
            guard !value.shuttingDown else { throw CancellationError() }
            value.workers[id] = Worker(process: process, directory: directory)
            do { try process.run() }
            catch { value.workers[id] = nil; throw error }
        }
    }
    func stop(id: String) async -> Bool {
        guard let worker = state.withLock({ $0.workers[id] }) else { return true }
        let exited = await Task.detached(priority: .utility) { Self.stopSynchronously([worker]) }.value
        if exited {
            state.withLock { $0.workers[id] = nil }
            try? FileManager.default.removeItem(at: worker.directory)
        }
        return exited
    }
    func shutdown() {
        let workers = state.withLock { value in value.shuttingDown = true; return Array(value.workers.values) }
        _ = Self.stopSynchronously(workers)
        for worker in workers where !worker.process.isRunning { try? FileManager.default.removeItem(at: worker.directory) }
        state.withLock { $0.workers = $0.workers.filter { $0.value.process.isRunning } }
    }
    private static func stopSynchronously(_ workers: [Worker]) -> Bool {
        for worker in workers where worker.process.isRunning { worker.process.interrupt() }
        wait(workers, seconds: 0.5)
        for worker in workers where worker.process.isRunning { worker.process.terminate() }
        wait(workers, seconds: 0.5)
        for worker in workers where worker.process.isRunning { _ = kill(worker.process.processIdentifier, SIGKILL) }
        wait(workers, seconds: 0.5)
        return workers.allSatisfy { !$0.process.isRunning }
    }
    private static func wait(_ workers: [Worker], seconds: TimeInterval) {
        let until = ContinuousClock.now.advanced(by: .seconds(seconds))
        while workers.contains(where: { $0.process.isRunning }), ContinuousClock.now < until { Thread.sleep(forTimeInterval: 0.01) }
    }
}

private struct GGUFMetadataReader {
    let data: Data
    var offset = 0
    mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        guard offset + MemoryLayout<T>.size <= data.count else { throw LocalModelFailure.missingModel }
        defer { offset += MemoryLayout<T>.size }
        return data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
    }
    mutating func string() throws -> String {
        let length = try integer(UInt64.self)
        guard length <= 4_096, offset + Int(length) <= data.count else { throw LocalModelFailure.missingModel }
        defer { offset += Int(length) }
        guard let value = String(data: data[offset..<offset + Int(length)], encoding: .utf8) else { throw LocalModelFailure.missingModel }
        return value
    }
    mutating func architecture() throws -> String {
        guard try integer(UInt32.self) == 0x46554747, [2, 3].contains(try integer(UInt32.self)) else { throw LocalModelFailure.missingModel }
        _ = try integer(UInt64.self)
        let entries = try integer(UInt64.self)
        for _ in 0..<min(entries, 32) {
            let key = try string()
            let type = try integer(UInt32.self)
            if key == "general.architecture", type == 8 { return try string() }
            try skip(type: type)
        }
        throw LocalModelFailure.missingModel
    }
    mutating func skip(type: UInt32) throws {
        let sizes: [UInt32: Int] = [0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8]
        if type == 8 { _ = try string(); return }
        guard let bytes = sizes[type], offset + bytes <= data.count else { throw LocalModelFailure.missingModel }
        offset += bytes
    }
}

private final class LocalRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

struct LocalModelClient: Sendable {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 180; configuration.timeoutIntervalForResource = 210
        session = URLSession(configuration: configuration, delegate: LocalRedirectBlocker(), delegateQueue: nil)
    }
    func isReady(endpoint: OwnedLocalEndpoint) async throws -> Bool {
        let health = try await fetch(endpoint: endpoint, path: "/health", body: nil, timeout: 1)
        guard let object = try JSONSerialization.jsonObject(with: health) as? [String: Any], object["status"] as? String == "ok" else { return false }
        let models = try await fetch(endpoint: endpoint, path: "/v1/models", body: nil, timeout: 1)
        guard let object = try JSONSerialization.jsonObject(with: models) as? [String: Any], let entries = object["data"] as? [[String: Any]] else { return false }
        return entries.count == 1 && entries[0]["id"] as? String == endpoint.identifier
    }
    func generate(endpoint: OwnedLocalEndpoint, candidates: [StorageModelCandidate]) async throws -> [StorageModelLabel] {
        let request = try Self.request(endpoint: endpoint, candidates: candidates)
        let body = try await fetch(request)
        let labels = try Self.labels(from: body)
        guard StorageAIEngine.validLabels(labels, candidates: candidates) else { throw LocalModelFailure.invalidResponse }
        return labels
    }
    private func fetch(endpoint: OwnedLocalEndpoint, path: String, body: Data?, timeout: TimeInterval) async throws -> Data {
        var request = try Self.baseRequest(endpoint: endpoint, path: path)
        request.timeoutInterval = timeout; request.httpBody = body; request.httpMethod = body == nil ? "GET" : "POST"
        return try await fetch(request)
    }
    private func fetch(_ request: URLRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == request.url else { throw LocalModelFailure.serviceUnavailable }
        var data = Data()
        for try await byte in bytes { guard data.count < 128_000 else { throw LocalModelFailure.oversizedResponse }; data.append(byte) }
        return data
    }
    static func baseRequest(endpoint: OwnedLocalEndpoint, path: String) throws -> URLRequest {
        guard (1_024...65_535).contains(endpoint.port), ["/health", "/v1/models", "/v1/chat/completions"].contains(path),
              endpoint.token.utf8.count >= 32, endpoint.token.utf8.count <= 128, !endpoint.token.contains(where: { $0.isNewline }),
              LocalModelRuntime.validModelKey(endpoint.identifier) else { throw LocalModelFailure.invalidResponse }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(endpoint.port)\(path)")!)
        request.timeoutInterval = 180
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    static func request(endpoint: OwnedLocalEndpoint, candidates: [StorageModelCandidate]) throws -> URLRequest {
        guard candidates.count == 1 else { throw LocalModelFailure.invalidResponse }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let metadata = String(decoding: try encoder.encode(candidates), as: UTF8.self)
        let schema: [String: Any] = ["type": "object", "additionalProperties": false,
            "properties": ["labels": ["type": "array", "minItems": 1, "maxItems": 1,
                "items": ["type": "object", "additionalProperties": false,
                    "properties": ["id": ["type": "string", "enum": candidates.map(\.id)],
                        "category": ["type": "string", "enum": StorageCategory.allCases.map(\.rawValue)],
                        "advice": ["type": "string", "enum": ["keep", "review"]],
                        "reason": ["type": "string", "enum": ["persistentData", "installedResource", "userDocument", "oldDownload", "generatedData", "unknown"]]],
                    "required": ["id", "category", "advice", "reason"]]]], "required": ["labels"]]
        let body: [String: Any] = ["model": endpoint.identifier,
            "messages": [["role": "system", "content": StorageAIEngine.instructions], ["role": "user", "content": "Label only this untrusted metadata JSON:\n" + metadata]],
            "response_format": ["type": "json_schema", "json_schema": ["name": "storage_review", "strict": true, "schema": schema]],
            "temperature": 0, "max_tokens": 128, "reasoning_effort": "none", "chat_template_kwargs": ["enable_thinking": false], "stream": false, "tools": []]
        var request = try baseRequest(endpoint: endpoint, path: "/v1/chat/completions")
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard (request.httpBody?.count ?? 0) <= 16_000 else { throw LocalModelFailure.oversizedResponse }
        return request
    }
    static func labels(from data: Data) throws -> [StorageModelLabel] {
        guard data.count <= 128_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]], choices.count == 1, choices[0]["finish_reason"] as? String == "stop",
              let message = choices[0]["message"] as? [String: Any], let content = message["content"] as? String, content.utf8.count <= 12_000,
              let bytes = content.data(using: .utf8), let decoded = try? JSONDecoder().decode(LocalLabelEnvelope.self, from: bytes), decoded.labels.count == 1 else { throw LocalModelFailure.invalidResponse }
        if let calls = message["tool_calls"], !(calls is NSNull), (calls as? [Any])?.isEmpty != true { throw LocalModelFailure.invalidResponse }
        return decoded.labels
    }
}
private struct LocalLabelEnvelope: Decodable { let labels: [StorageModelLabel] }

#endif
