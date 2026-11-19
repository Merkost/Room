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

    private(set) var rooms: [RoomPinnedRoom]
    private var sizes: [String: RoomSizeLog]
    private var stagedUnpins: Set<UUID> = []
    private var historySuspended = false
    private var failedMeasurements: Set<UUID> = []
    private(set) var selectedRoomID: UUID?
    private(set) var notice: String?
    private(set) var isMeasuring = false
    private(set) var isStateLoading = false
    private(set) var isReadOnly = false
    @ObservationIgnored private let store: RoomRoomsStore
    @ObservationIgnored private let access: RoomFileAccess
    @ObservationIgnored private let measurer: RoomRoomMeasurer
    @ObservationIgnored private let isWorking: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let folderPicker: @MainActor (String, String, String, URL?) async -> URL?
    @ObservationIgnored private var measurementTask: Task<Void, Never>?
    @ObservationIgnored private var measurementGeneration = UUID()
    @ObservationIgnored private var pinQueue: [UUID] = []
    @ObservationIgnored private var measuringRoomID: UUID?
    @ObservationIgnored private var measurementOwner: MeasurementOwner?
    @ObservationIgnored private var popoverActive = false
    @ObservationIgnored private var overviewChapterActive = false

    private enum MeasurementOwner { case pin, overview, popover, manual }
    private var pickerTask: Task<Void, Never>?
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
        let loadsAsynchronously = store.loadsAsynchronously
        isStateLoading = loadsAsynchronously
        rooms = loadsAsynchronously ? [] : store.loadRooms()
        sizes = loadsAsynchronously ? [:] : store.loadSizes()
        if loadsAsynchronously {
            Task { [weak self] in
                let saved = await store.loadState()
                guard let self else { return }
                self.rooms = saved.rooms
                self.sizes = saved.sizes
                self.isReadOnly = saved.readOnly
                self.isStateLoading = false
                if self.popoverActive || self.overviewChapterActive { self.measureNext() }
            }
        }
        observeWorking()
    }

    var visibleRooms: [RoomPinnedRoom] { rooms.filter { !stagedUnpins.contains($0.id) } }
    var popoverRoom: RoomPinnedRoom? { visibleRooms.first }
    var savedRoomID: UUID? { rooms.first?.id }
    var canUnpin: Bool { !isWorking() && !isStateLoading && !isReadOnly }
    var pinnedRoom: RoomPinnedRoom? { popoverRoom }
    var pinnedURL: URL? { popoverRoom.flatMap { url(for: $0.id) } }

    var unavailable: Set<UUID> {
        Set(rooms.lazy.filter { self.failedMeasurements.contains($0.id) || self.url(for: $0.id) == nil }.map(\.id))
    }

    func log(for id: UUID) -> RoomSizeLog? { historySuspended ? nil : sizes[id.uuidString] }

    func url(for id: UUID) -> URL? {
        guard let room = rooms.first(where: { $0.id == id }),
              let folder = access.folders.first(where: { $0.id == room.accessFolderID }) else { return nil }
        let scoped = folder.url.startAccessingSecurityScopedResource()
        defer { if scoped { folder.url.stopAccessingSecurityScopedResource() } }
        // URL metadata can be cached after the folder has been removed.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return folder.url
    }

    var state: State {
        guard let room = popoverRoom else { return .empty }
        guard pinnedURL != nil, !failedMeasurements.contains(room.id) else { return .unavailable(room) }
        guard let log = log(for: room.id), log.latest != nil else { return .measuring(room) }
        return .measured(room, log)
    }

    var canChooseFolder: Bool { pickerTask == nil && !isWorking() && !isStateLoading && !isReadOnly }

    func chooseFolder() { chooseFolder(replacingApprovalFor: nil) }

    func chooseFolder(replacingApprovalFor id: UUID?) {
        guard canChooseFolder else { return }
        let generation = UUID()
        pickerGeneration = generation
        #if ROOM_APP_STORE
        let home = RoomStoreEnvironment.userHome ?? FileManager.default.homeDirectoryForCurrentUser
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        #endif
        let previous = id.flatMap { id in rooms.first(where: { $0.id == id }) }
            .flatMap { room in access.folders.first(where: { $0.id == room.accessFolderID })?.url }
        pickerTask = Task { [weak self, folderPicker] in
            let selected = await folderPicker("Pin a folder", "Room reads sizes here. It never changes anything in this folder.", "Pin", previous ?? home)
            guard let self, self.pickerGeneration == generation else { return }
            self.pickerTask = nil
            guard !Task.isCancelled, let selected, !self.isWorking() else { return }
            self.pin(url: selected, replacingApprovalFor: id)
        }
    }

    func pin(url: URL) { pin(url: url, replacingApprovalFor: nil) }

    private func pin(url: URL, replacingApprovalFor id: UUID?) {
        guard !isStateLoading, !isReadOnly else { return }
        guard !isWorking() else { return }
        notice = nil
        if RoomRoomsCatalog.maximumRooms <= rooms.count, id == nil,
           !access.folders.contains(where: { folder in
               folder.url.standardizedFileURL.path == url.standardizedFileURL.path
                   && rooms.contains(where: { $0.accessFolderID == folder.id })
           }) {
            notice = "Room keeps up to 64 Rooms. Unpin one first."
            return
        }
        do {
            let approved = try access.remember(url)
            guard let folder = access.folders.first(where: { $0.url.standardizedFileURL == approved.standardizedFileURL }) else { return }
            if let id, let index = rooms.firstIndex(where: { $0.id == id }),
               !rooms.contains(where: { $0.id != id && $0.accessFolderID == folder.id }) {
                rooms[index].accessFolderID = folder.id
                failedMeasurements.remove(id)
                selectAndQueue(id)
                store.saveRooms(rooms)
                return
            }
            switch RoomRoomsCatalog.add(rooms, id: UUID(), accessFolderID: folder.id, name: folder.name) {
            case .added(let updated, let room):
                rooms = updated
                store.saveRooms(rooms)
                selectAndQueue(room.id)
            case .alreadyPinned(let id):
                selectedRoomID = id
            case .full:
                notice = "Room keeps up to 64 Rooms. Unpin one first."
            }
        } catch {
            access.setNote("Folder access could not be saved. Pin this folder again.")
        }
    }

    private func selectAndQueue(_ id: UUID) {
        selectedRoomID = id
        if !pinQueue.contains(id) { pinQueue.append(id) }
        measureNext()
    }

    func stageUnpin(_ id: UUID) {
        guard canUnpin, rooms.contains(where: { $0.id == id }) else { return }
        if measuringRoomID == id { cancelCurrentMeasurement() }
        stagedUnpins.insert(id)
    }

    func undoUnpin(_ id: UUID) { stagedUnpins.remove(id) }

    func commitUnpin(_ id: UUID) {
        guard stagedUnpins.remove(id) != nil else { return }
        removeRoom(id)
    }

    func suspendSizeHistory(_ suspended: Bool) {
        historySuspended = suspended
        if suspended { cancelCurrentMeasurement() }
    }

    func clearSizeHistory() {
        cancelCurrentMeasurement()
        sizes = [:]
        failedMeasurements = []
        store.discardPendingSizes()
    }

    func applyMap(_ map: RoomStoredTree, root: URL) {
        guard !historySuspended, !isStateLoading, !isReadOnly, !map.cancelled else { return }
        var changed = false
        for room in visibleRooms {
            guard let url = url(for: room.id), RoomFileAccess.contains(parent: root, child: url) else { continue }
            let components = url.standardizedFileURL.pathComponents.dropFirst(root.standardizedFileURL.pathComponents.count)
            guard let node = map.tree.descendant(at: components.joined(separator: "/")) else { continue }
            var log = sizes[room.id.uuidString] ?? RoomSizeLog()
            if let last = log.latest, last.at >= map.scannedAt { continue }
            log.record(.init(at: map.scannedAt, bytes: node.allocatedBytes, partial: node.isPartial), calendar: calendar)
            sizes[room.id.uuidString] = log
            failedMeasurements.remove(room.id)
            changed = true
        }
        if changed { store.saveSizes(sizes) }
    }

    func unpin() {
        guard let room = popoverRoom else { return }
        unpin(id: room.id)
    }

    func unpin(id: UUID) {
        guard !isStateLoading, !isReadOnly else { return }
        guard !isWorking() else { return }
        removeRoom(id)
    }

    private func removeRoom(_ id: UUID) {
        guard rooms.contains(where: { $0.id == id }) else { return }
        if measuringRoomID == id { cancelCurrentMeasurement() }
        pinQueue.removeAll(where: { $0 == id })
        rooms = RoomRoomsCatalog.remove(rooms, id: id)
        sizes = RoomRoomsCatalog.prunedSizes(sizes, rooms: rooms)
        failedMeasurements.remove(id)
        if selectedRoomID == id { selectedRoomID = nil }
        store.saveRooms(rooms)
        store.saveSizes(sizes)
    }

    func move(id: UUID, to index: Int) {
        updateRooms(RoomRoomsCatalog.move(rooms, id: id, to: index))
    }

    func rename(id: UUID, to name: String) {
        updateRooms(RoomRoomsCatalog.rename(rooms, id: id, to: name))
    }

    func setLook(id: UUID, glyph: RoomRoomGlyph? = nil, colour: RoomRoomColour? = nil) {
        updateRooms(RoomRoomsCatalog.setLook(rooms, id: id, glyph: glyph, colour: colour))
    }

    @discardableResult
    func setBudget(id: UUID, gb: Int?) -> Bool {
        guard let rooms = RoomRoomsCatalog.setBudget(rooms, id: id, gb: gb) else { return false }
        updateRooms(rooms)
        return true
    }

    private func updateRooms(_ updated: [RoomPinnedRoom]) {
        guard !isStateLoading, !isReadOnly else { return }
        guard !isWorking(), updated != rooms else { return }
        rooms = updated
        store.saveRooms(rooms)
    }

    /// A one-shot request, used by the Overview menu command. The menu-bar timer never calls it.
    func measureIfNeeded() { measureNext() }

    func setPopoverActive(_ active: Bool) {
        guard popoverActive != active else { return }
        popoverActive = active
        if active { measureNext() }
        else { cancelUnownedMeasurement() }
    }

    func setOverviewChapterActive(_ active: Bool) {
        guard overviewChapterActive != active else { return }
        overviewChapterActive = active
        if active { measureNext() }
        else { cancelUnownedMeasurement() }
    }

    private func cancelUnownedMeasurement() {
        guard !popoverActive, !overviewChapterActive,
              measurementOwner == .overview || measurementOwner == .popover else { return }
        cancelCurrentMeasurement()
    }

    func cancelMeasurement() {
        pinQueue.removeAll()
        cancelCurrentMeasurement()
        pickerGeneration = UUID()
        pickerTask?.cancel()
        pickerTask = nil
    }

    private func cancelCurrentMeasurement() {
        measurementGeneration = UUID()
        measurementTask?.cancel()
        // Retain the handle until the worker exits so cancellation-resistant work cannot overlap a new walk.
    }

    private func observeWorking() {
        withObservationTracking {
            if isWorking() { cancelMeasurement() }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeWorking() }
        }
    }

    func measureNext() {
        guard !historySuspended, !isStateLoading, !isReadOnly else { return }
        guard measurementTask == nil, pickerTask == nil, !isWorking() else { return }
        let unavailable = self.unavailable
        pinQueue.removeAll { unavailable.contains($0) }
        let owner: MeasurementOwner
        let id: UUID
        if !pinQueue.isEmpty {
            id = pinQueue.removeFirst()
            owner = .pin
        } else {
            guard let next = RoomRoomsMeasureQueue.next(rooms: visibleRooms, sizes: sizes, unavailable: unavailable, now: now()) else { return }
            id = next
            owner = overviewChapterActive ? .overview : popoverActive ? .popover : .manual
        }
        guard let url = url(for: id) else { return }
        #if ROOM_APP_STORE
        let scopes = access.folders.map(\.url)
        #else
        let scopes = [url]
        #endif
        let generation = UUID()
        measurementGeneration = generation
        measuringRoomID = id
        measurementOwner = owner
        isMeasuring = true
        measurementTask = Task { [weak self, measurer] in
            let result = await measurer.measure(url: url, approvedScopes: scopes)
            guard let self else { return }
            let acceptsResult = !Task.isCancelled && self.measurementGeneration == generation
                && self.url(for: id) != nil && !self.isWorking()
            self.measurementTask = nil
            self.measuringRoomID = nil
            self.measurementOwner = nil
            self.isMeasuring = false
            if acceptsResult {
                switch result {
                case let .measured(point):
                    var log = self.sizes[id.uuidString] ?? RoomSizeLog()
                    log.record(point, calendar: self.calendar)
                    self.sizes[id.uuidString] = log
                    self.store.saveSizes(self.sizes)
                    self.failedMeasurements.remove(id)
                case .unavailable:
                    self.failedMeasurements.insert(id)
                }
            }
            if !self.pinQueue.isEmpty || self.overviewChapterActive || self.popoverActive { self.measureNext() }
        }
    }
}
