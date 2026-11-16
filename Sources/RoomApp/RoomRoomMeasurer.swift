import Foundation
import RoomCore

nonisolated enum RoomRoomMeasurement: Equatable, Sendable {
    case measured(RoomSizePoint)
    case unavailable
}

/// Owns the background work boundary; injected measurements need no filesystem scan.
nonisolated struct RoomRoomMeasurer: Sendable {
    private let operation: @Sendable (URL) async -> RoomRoomMeasurement
    private let beginScope: @Sendable (URL) -> Bool
    private let endScope: @Sendable (URL) -> Void

    init(measure: (@Sendable (URL) async -> RoomRoomMeasurement)? = nil,
         beginScope: @escaping @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         endScope: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        operation = measure ?? Self.scan
        self.beginScope = beginScope
        self.endScope = endScope
    }

    func measure(url: URL, approvedScopes: [URL] = []) async -> RoomRoomMeasurement {
        let operation = operation
        let beginScope = beginScope
        let endScope = endScope
        let scopes = approvedScopes.isEmpty ? [url] : approvedScopes
        let worker = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return RoomRoomMeasurement.unavailable }
            let active = scopes.map { ($0, beginScope($0)) }
            defer { for (scope, started) in active where started { endScope(scope) } }
            guard !Task.isCancelled else { return RoomRoomMeasurement.unavailable }
            return await operation(url)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func scan(_ url: URL) async -> RoomRoomMeasurement {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true,
              FileManager.default.isReadableFile(atPath: url.path) else { return .unavailable }
        let report = await DiskMapEngine().scan(url: url)
        return .measured(RoomSizePoint(at: report.scannedAt, bytes: report.allocatedBytes,
            partial: report.isPartial || !report.issues.isEmpty || report.cancelled))
    }
}
