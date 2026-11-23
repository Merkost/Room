import Foundation

nonisolated struct RoomVolumeCapacity: Equatable, Sendable {
    let capacityBytes: Int64
    let freeBytes: Int64
    let volumeID: String?
    let volumeName: String?

    init?(capacityBytes: Int64?, freeBytes: Int64?, volumeID: String? = nil, volumeName: String? = nil) {
        guard let capacityBytes, let freeBytes,
              capacityBytes > 0, freeBytes >= 0, freeBytes <= capacityBytes else { return nil }
        self.capacityBytes = capacityBytes
        self.freeBytes = freeBytes
        self.volumeID = volumeID
        self.volumeName = volumeName
    }

    static func read() throws -> Self? {
        let values = try FileManager.default.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeUUIDStringKey, .volumeLocalizedNameKey])
        return Self(capacityBytes: values.volumeTotalCapacity.map(Int64.init),
                    freeBytes: values.volumeAvailableCapacity.map(Int64.init),
                    volumeID: values.volumeUUIDString, volumeName: values.volumeLocalizedName)
    }
}
