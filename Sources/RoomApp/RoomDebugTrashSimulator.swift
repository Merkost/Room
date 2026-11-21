#if DEBUG
import Foundation
import RoomCore

nonisolated enum RoomDebugTrashSimulator {
    /// Synthetic "every open item left the Trash and free space rose by exactly those bytes".
    /// The caller runs the result through `RoomMakeRoomLedger.advance` on an in-memory copy and never persists it.
    static func simulate(_ entries: [RoomMakeRoomEntry], now: Date)
        -> (observations: [UUID: RoomTrashObservation], sample: RoomCapacitySample)? {
        let open = entries.filter { $0.isObserved && $0.stage != .unobservable && $0.lastFree != nil && $0.volumeDevice != nil }
        guard let device = open.first?.volumeDevice, let base = open.compactMap(\.lastFree).max() else { return nil }
        let same = open.filter { $0.volumeDevice == device }
        var observations: [UUID: RoomTrashObservation] = [:]
        for e in same {
            observations[e.id] = RoomTrashObservation(presentBytes: 0, goneBytes: e.movedBytes - e.restoredBytes,
                                                      restoredBytes: e.restoredBytes, canObserve: true)
        }
        let rise = same.reduce(Int64(0)) { $0 + ($1.stillInTrashBytes) }
        return (observations, RoomCapacitySample(freeBytes: base + rise, device: device, at: now))
    }
}
#endif
