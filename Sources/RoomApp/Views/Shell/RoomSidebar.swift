import AppKit
import SwiftUI

struct RoomSidebar: View {
    let navigation: RoomWindowNavigation
    let rooms: RoomRoomsModel
    let mode: RoomSidebarMode
    let showsLabels: Bool
    let foot: RoomSidebarFoot
    let canOpenRooms: Bool
    let openRoom: (UUID) -> Void
    var savedViews: RoomSavedViewsStore? = nil
    var openSavedView: (UUID) -> Void = { _ in }

    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @FocusState private var focusedScreen: RoomDestination?
    @Namespace private var selection
    @State private var editingSavedView: RoomSavedView?
    private let deleteViewPrefix = "sidebar:delete-view:"
    private let unpinPrefix = "sidebar:unpin:"
    private let confirmation = RoomInlineConfirmCenter.shared

    static let items: [NavigationItem] = RoomMenuModel.Destination.allCases.compactMap { menu in
        guard let destination = RoomDestination(rawValue: menu.rawValue) else { return nil }
        return NavigationItem(destination: destination, title: menu.item.title, symbol: menu.symbol,
                              shortcut: menu.shortcut?.key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            ScrollView {
                VStack(alignment: .leading, spacing: RoomTokens.Sidebar.pitchGap) {
                    ForEach(Self.items) { item in
                        if item.destination == .disk { groupHeading(Text("Tools")) }
                        screenRow(item)
                    }
                    groupHeading(Text("nav.rooms", bundle: RoomCopy.bundle))
                    roomRow
                    RoomInlineUndoRows(prefix: unpinPrefix, hidesPrivateName: true)
                    savedViewRows
                }
            }
            .scrollIndicators(.hidden)
            if mode == .labelled, showsLabels, let freeText = foot.freeText, let used = foot.usedFraction {
                volumeFoot(freeText: freeText, used: used)
            }
        }
        .padding(.horizontal, RoomTokens.Space.row)
        .padding(.vertical, RoomTokens.Space.inner)
        .frame(maxHeight: .infinity, alignment: .top)
        .disabled(RoomCommandWindowContext.current == .modal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room views")
        .onDisappear { finishPendingChanges() }
        .onChange(of: navigation.route) { _, _ in finishPendingChanges() }
        .sheet(item: $editingSavedView) { view in
            RoomSavedViewNameEditor(title: "Rename View", action: "Rename", name: hide.masksNow ? "" : view.name) {
                savedViews?.rename(view.id, to: $0) == true
            }
        }
    }

    private func screenRow(_ item: NavigationItem) -> some View {
        let route = RoomRoute.screen(item.destination)
        let selected = navigation.route == route
        return Button {
            let origin = RoomSelectionOrigin.controlActivation
            withAnimation(origin == .pointer ? motion.animation(RoomTokens.Motion.standard, fallback: nil) : nil) {
                navigation.select(route, origin: origin)
            }
        } label: {
            row(icon: {
                Group {
                    if item.destination == .overview {
                        RoomMark().fill(style: FillStyle(eoFill: true))
                    } else {
                        Image(systemName: item.symbol)
                    }
                }
                .scaleEffect(selected ? 1 : RoomTokens.Motion.pressScale)
            }, iconColor: selected ? accent.text : RoomTokens.Ink.secondary) {
                Text(item.title)
                    .font(selected || item.destination == .overview ? RoomTokens.Typography.bodyStrong : RoomTokens.Typography.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let shortcut = item.shortcut {
                    Text(verbatim: "⌘\(shortcut)").font(RoomTokens.Typography.micro)
                        .monospacedDigit()
                        .foregroundStyle(selected ? accent.text : RoomTokens.Ink.secondary)
                        .accessibilityHidden(true)
                }
            }
            .background { if selected { selectionPill } }
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomHoverButtonStyle(showsFeedback: !selected))
        .focused($focusedScreen, equals: item.destination)
        .onKeyPress(.return) {
            navigation.select(route, origin: .keyboard)
            return .handled
        }
        .onKeyPress(.space) {
            navigation.select(route, origin: .keyboard)
            return .handled
        }
        .onMoveCommand(perform: moveFocus)
        .help(item.help)
        .accessibilityLabel(item.title)
        .accessibilityHint(Text(verbatim: item.shortcut.map { "Command \($0)" } ?? ""))
        .accessibilityIdentifier("RoomNavigation-\(item.id)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var pill: RoundedRectangle { RoundedRectangle(cornerRadius: RoomTokens.Radius.row) }

    private var selectionPill: some View {
        pill.fill(accent.wash)
            .overlay(pill.strokeBorder(RoomTokens.Surface.line))
            .matchedGeometryEffect(id: "sidebar-selection", in: selection)
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        guard let focusedScreen, let current = Self.items.firstIndex(where: { $0.destination == focusedScreen }) else { return }
        let next: Int
        switch direction {
        case .up: next = max(0, current - 1)
        case .down: next = min(Self.items.count - 1, current + 1)
        default: return
        }
        self.focusedScreen = Self.items[next].destination
    }

    @ViewBuilder private func groupHeading(_ label: Text) -> some View {
        if mode == .labelled && showsLabels {
            label
                .font(RoomTokens.Typography.sidebarGroup)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .padding(.horizontal, RoomTokens.Space.row)
                .padding(.top, RoomTokens.Space.group)
                .padding(.bottom, RoomTokens.Sidebar.pitchGap)
                .accessibilityAddTraits(.isHeader)
        } else {
            Color.clear.frame(height: RoomTokens.Space.inner)
        }
    }

    @ViewBuilder private var roomRow: some View {
        ForEach(rooms.visibleRooms) { room in
            if rooms.unavailable.contains(room.id) {
                pinned(room, size: String(localized: "nav.room.needsAccess", defaultValue: "Needs access", bundle: RoomCopy.bundle),
                       spokenSize: nil, needsAccess: true)
            } else if let sample = rooms.log(for: room.id)?.latest {
                let size = RoomFormat.bytes(sample.bytes)
                pinned(room, size: sample.partial ? "≥ \(size)" : size,
                       spokenSize: sample.partial ? "at least \(size)" : size)
            } else {
                pinned(room, size: "—", spokenSize: String(localized: "nav.room.notMeasured",
                       defaultValue: "Not measured yet", bundle: RoomCopy.bundle))
            }
        }
        Button(action: rooms.chooseFolder) {
            row(icon: { Image(systemName: "pin") }, iconColor: RoomTokens.Ink.secondary) {
                Text("nav.rooms.pin", bundle: RoomCopy.bundle).font(RoomTokens.Typography.body).lineLimit(1)
            }
        }
        .buttonStyle(RoomHoverButtonStyle())
        .disabled(!rooms.canChooseFolder)
        .accessibilityLabel(Text("nav.rooms.pin", bundle: RoomCopy.bundle))
    }

    @ViewBuilder private var savedViewRows: some View {
        if let savedViews, !savedViews.visible.isEmpty {
            groupHeading(Text("Saved views"))
            ForEach(savedViews.visible) { view in savedViewRow(view, in: savedViews) }
        }
        RoomInlineUndoRows(prefix: deleteViewPrefix, hidesPrivateName: true)
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
                    .font(RoomTokens.Typography.body).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .background { if selected { selectionPill } }
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomHoverButtonStyle(showsFeedback: !selected))
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

    private func finishPendingChanges() {
        confirmation.finishAll(prefix: unpinPrefix)
        confirmation.finishAll(prefix: deleteViewPrefix)
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
            withAnimation(origin == .pointer ? motion.animation(RoomTokens.Motion.standard, fallback: nil) : nil) {
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
                RoomMaskable(room.name, kind: .name).font(RoomTokens.Typography.body).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: RoomTokens.Sidebar.pitchGap)
                RoomMaskable(size, spoken: spokenSize ?? size).font(RoomTokens.Typography.micro).monospacedDigit().lineLimit(1)
                    .foregroundStyle(needsAccess ? accent.text : RoomTokens.Ink.secondary)
            }
            .background { if selected { selectionPill } }
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomHoverButtonStyle(showsFeedback: !selected))
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
        HStack(spacing: RoomTokens.Space.row) {
            icon()
                .frame(width: RoomTokens.Sidebar.iconWidth, height: RoomTokens.Sidebar.iconWidth)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            if mode == .labelled {
                label().opacity(showsLabels ? 1 : 0)
            }
        }
        .padding(.horizontal, RoomTokens.Sidebar.innerPadding)
        .frame(maxWidth: mode == .labelled ? .infinity : nil,
               minHeight: RoomSidebarLayout.rowHeight, alignment: .leading)
    }

    private func volumeFoot(freeText: String, used: Double) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            HStack(spacing: RoomTokens.Space.tight) {
                if let name = foot.volumeName {
                    RoomMaskable(name, kind: .name).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if foot.belowGoal {
                    Image(nsImage: RoomPocketMark.image(fill: 0.5, pointSize: 11))
                        .foregroundStyle(RoomTokens.Status.elevated)
                }
                RoomMaskable(freeText)
                    .fontWeight(foot.belowGoal ? .semibold : .regular)
                    .foregroundStyle(foot.belowGoal ? RoomTokens.Status.elevated : RoomTokens.Ink.secondary)
                    .monospacedDigit().fixedSize()
            }
            .font(RoomTokens.Typography.micro)
            .foregroundStyle(RoomTokens.Ink.secondary)
            GeometryReader { geometry in
                Capsule().fill(RoomTokens.Surface.track)
                    .overlay(alignment: .leading) {
                        Capsule().fill(RoomTokens.Surface.used).frame(width: geometry.size.width * used)
                    }
            }
            .frame(height: RoomTokens.Sidebar.barHeight)
        }
        .padding(RoomTokens.Space.row)
        .background(RoomTokens.Surface.group, in: pill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hide.masksNow ? "Free space hidden" : foot.accessibilityLabel)
    }
}

nonisolated struct NavigationItem: Identifiable, Sendable {
    let destination: RoomDestination
    let title: String
    let symbol: String
    let shortcut: Character?
    var id: String { destination.rawValue }
    var help: String { shortcut.map { "\(title) (⌘\($0))" } ?? title }
}
