import Foundation
import Observation

@Observable @MainActor
final class RoomRoomsModel {
    nonisolated enum State: Equatable, Sendable {
        case empty
        case measuring(RoomPinnedRoom)
        case measured(RoomPinnedRoom, RoomSizeLog)
        case unavailable(RoomPinnedRoom)
    }

    private var rooms: [RoomPinnedRoom]
    private var sizes: [String: RoomSizeLog]
    private var unavailableRoomID: UUID?
    private(set) var isMeasuring = false
    @ObservationIgnored private let store: RoomRoomsStore
    @ObservationIgnored private let access: RoomFileAccess
    @ObservationIgnored private let measurer: RoomRoomMeasurer
    @ObservationIgnored private let isWorking: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let folderPicker: @MainActor (String, String, String, URL?) async -> URL?
    @ObservationIgnored private var measurementTask: Task<Void, Never>?
    @ObservationIgnored private var measurementGeneration = UUID()
    @ObservationIgnored private var pendingPinMeasurementID: UUID?
    @ObservationIgnored private var pickerTask: Task<Void, Never>?
    @ObservationIgnored private var pickerGeneration = UUID()

    init(store: RoomRoomsStore = .init(), access: RoomFileAccess = .shared,
         measurer: RoomRoomMeasurer = .init(),
         isWorking: @escaping @MainActor () -> Bool = { false },
         now: @escaping @MainActor () -> Date = { Date() }, calendar: Calendar = .current,
         folderPicker: (@MainActor (String, String, String, URL?) async -> URL?)? = nil) {
        self.store = store
        self.access = access
        self.measurer = measurer
        self.isWorking = isWorking
        self.now = now
        self.calendar = calendar
        self.folderPicker = folderPicker ?? { title, message, prompt, initial in
            await RoomNativeFolderPicker.shared.choose(title: title, message: message, prompt: prompt, initialURL: initial)
        }
        rooms = store.loadRooms()
        sizes = store.loadSizes()
        observeWorking()
    }

    var pinnedRoom: RoomPinnedRoom? { rooms.first }

    var pinnedURL: URL? {
        guard let room = pinnedRoom, let folder = access.folders.first(where: { $0.id == room.accessFolderID }) else { return nil }
        let scoped = folder.url.startAccessingSecurityScopedResource()
        defer { if scoped { folder.url.stopAccessingSecurityScopedResource() } }
        // FileManager asks the file system each time; URL.resourceValues can answer from a value cached on the URL
        // and keep reporting a folder that has since been deleted.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return folder.url
    }

    var state: State {
        guard let room = pinnedRoom else { return .empty }
        guard pinnedURL != nil, unavailableRoomID != room.id else { return .unavailable(room) }
        guard let log = sizes[room.id.uuidString], log.latest != nil else { return .measuring(room) }
        return .measured(room, log)
    }

    func chooseFolder() {
        guard pickerTask == nil, !isWorking() else { return }
        let generation = UUID()
        pickerGeneration = generation
        #if ROOM_APP_STORE
        let home = RoomStoreEnvironment.userHome ?? FileManager.default.homeDirectoryForCurrentUser
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        #endif
        pickerTask = Task { [weak self, folderPicker] in
            let selected = await folderPicker("Pin a folder", "Room reads sizes here. It never changes anything in this folder.", "Pin", home)
            guard let self, self.pickerGeneration == generation else { return }
            self.pickerTask = nil
            guard !Task.isCancelled, let selected, !self.isWorking() else { return }
            self.pin(url: selected)
        }
    }

    func pin(url: URL) {
        guard !isWorking() else { return }
        do {
            let approved = try access.remember(url)
            guard let folder = access.folders.first(where: { $0.url.standardizedFileURL == approved.standardizedFileURL }) else { return }
            let previous = pinnedRoom
            cancelMeasurement()
            let room: RoomPinnedRoom
            if let previous, previous.accessFolderID == folder.id {
                room = RoomPinnedRoom(id: previous.id, accessFolderID: folder.id, name: folder.name, order: previous.order)
            } else {
                room = RoomPinnedRoom(id: UUID(), accessFolderID: folder.id, name: folder.name, order: previous?.order ?? 0)
                if let previous { sizes.removeValue(forKey: previous.id.uuidString) }
            }
            if rooms.isEmpty { rooms.append(room) } else { rooms[0] = room }
            unavailableRoomID = nil
            store.saveRooms(rooms)
            store.saveSizes(sizes)
            requestMeasurement(force: true)
        } catch {
            access.setNote("Folder access could not be saved. Pin this folder again.")
        }
    }

    func unpin() {
        cancelMeasurement()
        guard let room = pinnedRoom else { return }
        rooms.removeFirst()
        sizes.removeValue(forKey: room.id.uuidString)
        unavailableRoomID = nil
        store.saveRooms(rooms)
        store.saveSizes(sizes)
    }

    /// Called on popover open, never by the 20-second monitor loop.
    func measureIfNeeded() { requestMeasurement(force: false) }

    func cancelMeasurement() {
        measurementGeneration = UUID()
        pendingPinMeasurementID = nil
        measurementTask?.cancel()
        // Keep the handle until the worker exits: cancellation may be ignored by
        // an injected operation, and a second worker must not overlap it.
        pickerGeneration = UUID()
        pickerTask?.cancel()
        pickerTask = nil
    }

    private func observeWorking() {
        withObservationTracking {
            if isWorking() { cancelMeasurement() }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeWorking() }
        }
    }

    private func requestMeasurement(force: Bool) {
        guard let room = pinnedRoom, !isWorking(), let url = pinnedURL,
              unavailableRoomID != room.id else { return }
        guard measurementTask == nil else {
            if force { pendingPinMeasurementID = room.id }
            return
        }
        if !force, let latest = sizes[room.id.uuidString]?.latest,
           now().timeIntervalSince(latest.at) <= 3600 { return }
        #if ROOM_APP_STORE
        let scopes = access.folders.map(\.url)
        #else
        let scopes = [url]
        #endif
        let generation = UUID()
        measurementGeneration = generation
        isMeasuring = true
        measurementTask = Task { [weak self, measurer] in
            let result = await measurer.measure(url: url, approvedScopes: scopes)
            guard let self else { return }
            let acceptsResult = !Task.isCancelled && self.measurementGeneration == generation
                && self.pinnedRoom?.id == room.id && self.pinnedURL != nil && !self.isWorking()
            self.measurementTask = nil
            self.isMeasuring = false
            if acceptsResult {
                switch result {
                case let .measured(point):
                    var log = self.sizes[room.id.uuidString] ?? RoomSizeLog()
                    log.record(point, calendar: self.calendar)
                    self.sizes[room.id.uuidString] = log
                    self.store.saveSizes(self.sizes)
                    self.unavailableRoomID = nil
                case .unavailable:
                    self.unavailableRoomID = room.id
                }
            }
            let pending = self.pendingPinMeasurementID
            self.pendingPinMeasurementID = nil
            if pending != nil, pending == self.pinnedRoom?.id { self.requestMeasurement(force: true) }
        }
    }
}
