import AppKit
import SwiftUI

/// Pinned Rooms and saved Disk Map views, as a row of chips on Disk Map, only when the person has some (pinning
/// lives in the Disk Map inspector line and File › Pin Folder as a Room).
struct RoomPinnedChips: View {
    let navigation: RoomWindowNavigation
    let rooms: RoomRoomsModel
    let canOpenRooms: Bool
    let openRoom: (UUID) -> Void
    var savedViews: RoomSavedViewsStore?
    var openSavedView: (UUID) -> Void

    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomScreenInsets) private var insets
    @State private var editingSavedView: RoomSavedView?
    @State private var editingRoom: RoomPinnedRoom?
    private let deleteViewPrefix = "pinned:delete-view:"
    private let unpinPrefix = "pinned:unpin:"
    private let confirmation = RoomInlineConfirmCenter.shared

    static func hasContent(rooms: RoomRoomsModel, savedViews: RoomSavedViewsStore?) -> Bool {
        !rooms.visibleRooms.isEmpty || !(savedViews?.visible.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            if Self.hasContent(rooms: rooms, savedViews: savedViews) {
                ScrollView(.horizontal) {
                    HStack(spacing: RoomTokens.Space.inner) {
                        roomRows
                        savedViewRows
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Pinned folders and saved views")
            }
            RoomInlineUndoRows(prefix: unpinPrefix, hidesPrivateName: true)
            RoomInlineUndoRows(prefix: deleteViewPrefix, hidesPrivateName: true)
        }
        .padding(.leading, insets.leading)
        .padding(.trailing, insets.trailing)
        .onDisappear { finishPendingChanges() }
        .onChange(of: navigation.route) { _, _ in finishPendingChanges() }
        .sheet(item: $editingSavedView) { view in
            RoomSavedViewNameEditor(title: "Rename View", action: "Rename", name: hide.masksNow ? "" : view.name) {
                savedViews?.rename(view.id, to: $0) == true
            }
        }
        .sheet(item: $editingRoom) { snapshot in
            if let room = rooms.visibleRooms.first(where: { $0.id == snapshot.id }) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    Text("Edit Room").font(RoomTokens.Typography.title).accessibilityHeading(.h1)
                    RoomPinnedRoomEditor(rooms: rooms, room: room, hidden: hide.masksNow) { editingRoom = nil }
                }
                .padding(RoomTokens.Space.group)
                .frame(width: 320)
            } else {
                Button("Done") { editingRoom = nil }
                    .padding(RoomTokens.Space.group)
            }
        }
    }

    private var pill: Capsule { Capsule() }

    private func chipBackground(selected: Bool) -> some View {
        pill.fill(selected ? RoomTokens.Surface.pill : RoomTokens.Surface.tile)
            .overlay(pill.strokeBorder(selected ? accent.text : RoomTokens.Surface.line, lineWidth: 0.5))
    }

    @ViewBuilder private var roomRows: some View {
        ForEach(rooms.visibleRooms) { room in
            if rooms.unavailable.contains(room.id) {
                pinned(room, size: String(localized: "nav.room.needsAccess", defaultValue: "Needs access", bundle: RoomCopy.bundle),
                       spokenSize: nil, needsAccess: true)
            } else if let sample = rooms.log(for: room.id)?.latest {
                let size = RoomFormat.gb(sample.bytes)
                pinned(room, size: sample.partial ? "≥ \(size)" : size,
                       spokenSize: sample.partial ? "at least \(size)" : size)
            } else {
                pinned(room, size: RoomFormat.notMeasured, spokenSize: String(localized: "nav.room.notMeasured",
                       defaultValue: "Not measured yet", bundle: RoomCopy.bundle))
            }
        }
    }

    @ViewBuilder private var savedViewRows: some View {
        if let savedViews, !savedViews.visible.isEmpty {
            ForEach(savedViews.visible) { view in savedViewRow(view, in: savedViews) }
        }
    }

    private func savedViewRow(_ view: RoomSavedView, in store: RoomSavedViewsStore) -> some View {
        let selected = navigation.route == .savedView(view.id)
        let actionID = deleteViewPrefix + view.id.uuidString
        let maskedName = RoomHideMask.display(view.name, kind: .name, hide: hide)
        let question = "Delete \(maskedName)?"
        let done = "Deleted \(maskedName)."
        return Button { openSavedView(view.id) } label: {
            row(icon: { Image(systemName: "bookmark") },
                iconColor: selected ? accent.text : RoomTokens.Ink.secondary) {
                RoomMaskable(view.name, kind: .name)
                    .font(RoomTokens.Nav.label).lineLimit(1)
            }
            .background { chipBackground(selected: selected) }
            .contentShape(Capsule())
        }
        .buttonStyle(RoomPressStyle())
        .disabled(!canOpenRooms)
        .help(hide.masksNow ? "Saved view, name hidden" : view.name)
        .accessibilityLabel(hide.masksNow ? "Saved view, name hidden" : view.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("RoomSavedView-\(view.id.uuidString)")
        .contextMenu {
            Button("Rename…") { editingSavedView = view }.disabled(!store.canEdit)
            Button("Delete…") {
                confirmation.press(actionID, doneLine: done, stage: { store.stageRemoval(view.id) },
                    commit: { store.commitRemoval(view.id) }, undo: { store.undoRemoval(view.id) })
            }
            .disabled(!store.canEdit)
        }
        .overlay(alignment: .bottomLeading) {
            if case .armed = confirmation.phase(actionID) {
                RoomInlineConfirmButton(id: actionID, title: "Delete…", confirmTitle: question, doneLine: done,
                    isAllowed: store.canEdit, stage: { store.stageRemoval(view.id) },
                    commit: { store.commitRemoval(view.id) }, undo: { store.undoRemoval(view.id) })
                    .padding(.horizontal, RoomTokens.Space.row)
                    .background(.regularMaterial, in: pill)
            }
        }
    }


    private func pinned(_ room: RoomPinnedRoom, size: String, spokenSize: String?, needsAccess: Bool = false) -> some View {
        let selected = navigation.route == .room(room.id)
        let unpinID = unpinPrefix + room.id.uuidString
        let question = String(localized: "confirm.unpin", defaultValue: "Unpin %@?", bundle: RoomCopy.bundle)
        let done = String(localized: "confirm.unpin.done", defaultValue: "Unpinned %@.", bundle: RoomCopy.bundle)
        let confirmTitle = String.localizedStringWithFormat(question, RoomHideMask.display(room.name, kind: .name, hide: hide))
        let doneLine = String.localizedStringWithFormat(done, RoomHideMask.display(room.name, kind: .name, hide: hide))
        let spokenFormat = String(localized: "nav.room.a11y", defaultValue: "%1$@, Room, %2$@", bundle: RoomCopy.bundle)
        let kind = RoomTokens.Kind(rawValue: room.resolvedColour.rawValue) ?? .developer
        let siblings = rooms.visibleRooms
        let position = siblings.firstIndex(where: { $0.id == room.id })
        let earlierOrder = position.flatMap { $0 > 0 ? siblings[$0 - 1].order : nil }
        let laterOrder = position.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].order : nil }

        return Button {
            let origin = RoomSelectionOrigin.controlActivation
            withAnimation(RoomDock.selectionAnimation(origin: origin, motion: motion)) {
                openRoom(room.id)
            }
        } label: {
            row(icon: {
                Image(systemName: room.resolvedGlyph.rawValue)
                    .font(RoomTokens.Typography.micro)
                    .foregroundStyle(RoomTokens.Kind.tileInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(kind.fill, in: .rect(cornerRadius: RoomTokens.Radius.tile))
            }, iconColor: selected ? accent.text : RoomTokens.Ink.secondary) {
                RoomMaskable(room.name, kind: .name).font(RoomTokens.Nav.label).lineLimit(1)
                RoomMaskable(size, spoken: spokenSize ?? size).font(RoomTokens.Nav.value).monospacedDigit().lineLimit(1)
                    .foregroundStyle(needsAccess ? accent.text : RoomTokens.Ink.tertiary)
            }
            .background { chipBackground(selected: selected) }
            .contentShape(Capsule())
        }
        .buttonStyle(RoomPressStyle())
        .disabled(!canOpenRooms)
        .help(RoomHideSpeech.labelled(room.name, value: spokenSize ?? size, labelIsName: true, hide: hide))
        .accessibilityLabel(hide.masksNow ? "Room, hidden" : String.localizedStringWithFormat(spokenFormat, room.name, spokenSize ?? size))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .draggable(room.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard rooms.canUnpin, let first = values.first, let id = UUID(uuidString: first),
                  id != room.id, rooms.visibleRooms.contains(where: { $0.id == id }) else { return false }
            rooms.move(id: id, to: room.order)
            return true
        }
        .contextMenu {
            Button("Edit Room…") { editingRoom = room }
                .disabled(!rooms.canUnpin || hide.masksNow)
            if let url = rooms.url(for: room.id) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            if let earlierOrder {
                Button("Move Up") { rooms.move(id: room.id, to: earlierOrder) }
                    .disabled(!rooms.canUnpin)
            }
            if let laterOrder {
                Button("Move Down") { rooms.move(id: room.id, to: laterOrder) }
                    .disabled(!rooms.canUnpin)
            }
            Button("Unpin…") {
                confirmation.press(unpinID, doneLine: doneLine,
                    stage: { rooms.stageUnpin(room.id) }, commit: { rooms.commitUnpin(room.id) },
                    undo: { rooms.undoUnpin(room.id) })
            }
                .disabled(!rooms.canUnpin)
        }
        .overlay(alignment: .bottomLeading) {
            if case .armed = confirmation.phase(unpinID) {
                RoomInlineConfirmButton(id: unpinID, title: "Unpin…", confirmTitle: confirmTitle,
                    doneLine: doneLine, isAllowed: rooms.canUnpin, stage: { rooms.stageUnpin(room.id) },
                    commit: { rooms.commitUnpin(room.id) }, undo: { rooms.undoUnpin(room.id) })
                    .padding(.horizontal, RoomTokens.Space.row)
                    .background(.regularMaterial, in: pill)
            }
        }
    }

    private func row<Icon: View, Label: View>(@ViewBuilder icon: () -> Icon, iconColor: Color,
                                              @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: RoomTokens.Space.inner) {
            icon()
                .frame(width: RoomTokens.Nav.tile - 10, height: RoomTokens.Nav.tile - 10)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            label()
        }
        .padding(.horizontal, RoomTokens.Space.row)
        .frame(height: RoomTokens.Control.height)
        .fixedSize()
    }

    private func finishPendingChanges() {
        confirmation.finishAll(prefix: unpinPrefix)
        confirmation.finishAll(prefix: deleteViewPrefix)
    }
}
