import AppKit
import SwiftUI

/// What the sidebar foot needs: free space, capacity, and what Make room would give back.
struct RoomSidebarPlate: Equatable {
    var freeBytes: Int64?
    var capacityBytes: Int64?
    var couldGoBytes: Int64 = 0
    var belowGoal = false
}

/// nav-v3 sidebar: Your Mac (Overview, Disk Map), Make room (Caches, Developer), Right now (Memory); History and Settings
/// at the bottom; a nameplate with the free-space meter. One glass pill marks the place: it slides with a spring for
/// the pointer and jumps for the keyboard.
struct RoomSidebar: View {
    let navigation: RoomWindowNavigation
    let rooms: RoomRoomsModel
    let mode: RoomSidebarMode
    let showsLabels: Bool
    var values = RoomSidebarValue.Input()
    var plate = RoomSidebarPlate()
    let canOpenRooms: Bool
    let openRoom: (UUID) -> Void
    var savedViews: RoomSavedViewsStore? = nil
    var openSavedView: (UUID) -> Void = { _ in }
    var activity: [RoomDestination: RoomRowActivity] = [:]
    var stop: (RoomDestination) -> Void = { _ in }
    var developerSection: RoomDeveloperSection = .rooms
    var selectDeveloperSection: (RoomDeveloperSection) -> Void = { _ in }
    var openGoTo: (_ keyboard: Bool) -> Void = { _ in }

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomHide) private var hide
    @State private var hoveredPlace: RoomDestination?
    @State private var peekPlace: RoomDestination?
    @State private var peekTask: Task<Void, Never>?
    @State private var lastPeekEnded: Date?
    @Environment(\.roomAccent) private var accent
    @FocusState private var focusedScreen: RoomDestination?
    @Namespace private var selection
    @State private var commandHeld = false

    /// The places as menu items (the Go menu and its tests read titles and ⌘ numbers from here).
    static let items: [NavigationItem] = RoomSidebarPlan.places.map { place in
        let menu = RoomMenuModel.Destination(rawValue: place.rawValue)
        return NavigationItem(destination: place, title: RoomSidebarPlan.title(place), symbol: menu?.symbol ?? "",
                              shortcut: Character(String(RoomSidebarPlan.shortcut(place))))
    }

    private var labelled: Bool { mode == .labelled && showsLabels }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoomGoToField(labelled: labelled) { openGoTo(RoomSelectionOrigin.controlActivation == .keyboard) }
                .padding(.horizontal, 2)
                .padding(.bottom, RoomTokens.Space.inner)
            ScrollView {
                VStack(alignment: .leading, spacing: RoomTokens.Nav.rowGap) {
                    ForEach([RoomSidebarPlan.Group.yourMac, .makeRoom, .rightNow], id: \.self) { group in
                        groupHeading(group, first: group == .yourMac)
                        ForEach(RoomSidebarPlan.places(in: group), id: \.self) { place in
                            placeRow(place)
                            if place == .developer {
                                RoomSidebarDeveloperRooms(open: labelled && navigation.route == .screen(.developer),
                                                          selected: developerSection, select: selectDeveloperSection)
                            }
                        }
                    }
                    if RoomSidebarPinned.hasContent(rooms: rooms, savedViews: savedViews) {
                        RoomSidebarPinned(navigation: navigation, rooms: rooms, labelled: labelled,
                                          canOpenRooms: canOpenRooms, openRoom: openRoom, savedViews: savedViews,
                                          openSavedView: openSavedView, selectionPill: AnyView(selectionPill))
                    }
                }
            }
            .scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: RoomTokens.Nav.rowGap) {
                ForEach(RoomSidebarPlan.places(in: .bottom), id: \.self) { place in placeRow(place) }
            }
            .padding(.top, RoomTokens.Space.tight)
            if labelled {
                RoomSidebarNameplate(freeBytes: plate.freeBytes, capacityBytes: plate.capacityBytes,
                                     couldGoBytes: plate.couldGoBytes, belowGoal: plate.belowGoal)
                    .padding(.top, RoomTokens.Space.inner)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, RoomTokens.Nav.columnPadding)
        .padding(.top, RoomTokens.Space.tight)
        .padding(.bottom, RoomTokens.Space.inner)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room places")
        .onModifierKeysChanged(mask: .command, initial: true) { _, keys in commandHeld = keys.contains(.command) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            commandHeld = false
        }
    }

    private func placeRow(_ place: RoomDestination) -> some View {
        let route = RoomRoute.screen(place)
        let selected = navigation.route == route
        let value = RoomSidebarValue.make(place, values)
        let title = RoomSidebarPlan.title(place)
        let row = activity[place] ?? RoomRowActivity()
        let hovering = hoveredPlace == place
        return Button {
            select(place, origin: RoomSelectionOrigin.controlActivation)
        } label: {
            RoomSidebarRow(place: place, value: value, selected: selected, labelled: labelled,
                           commandHeld: commandHeld, activity: row, hovering: hovering && row.isWorking)
                .background { if selected { selectionPill } }
                .contentShape(Rectangle())
        }
        .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Nav.pillRadius, showsFeedback: !selected))
        .overlay(alignment: .topTrailing) {
            if labelled, hovering, row.isWorking {
                Button("Stop") { stop(place) }
                    .roomLink(accent)
                    .font(RoomTokens.Nav.value.weight(.medium))
                    .padding(.trailing, RoomTokens.Nav.rowInsetTrailing)
                    .padding(.top, RoomTokens.Space.tight)
                    .accessibilityLabel("Stop \(title)")
            }
        }
        .onHover { inside in hover(place, inside: inside) }
        .popover(isPresented: Binding(get: { peekPlace == place && !labelled },
                                      set: { if !$0, peekPlace == place { peekPlace = nil } }),
                 arrowEdge: .trailing) {
            peek(place, value: value, row: row)
        }
        .focused($focusedScreen, equals: place)
        .onKeyPress(.return) { select(place, origin: .keyboard); return .handled }
        .onKeyPress(.space) { select(place, origin: .keyboard); return .handled }
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "kKhH"), phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            if press.characters.lowercased() == "k" { openGoTo(true) } else { RoomHideControl.shared.toggle() }
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.isEmpty, let number = Int(press.characters),
                  let target = RoomSidebarPlan.place(forShortcut: number) else { return .ignored }
            select(target, origin: .keyboard)
            focusedScreen = target
            return .handled
        }
        .help("\(title) (⌘\(RoomSidebarPlan.shortcut(place)))")
        .accessibilityLabel(title)
        .accessibilityValue(Self.spokenValue(value, activity: row, hidden: hide.masksNow))
        .accessibilityAction(named: "Stop") { if row.isWorking { stop(place) } }
        .accessibilityHint(Text(verbatim: "Command \(RoomSidebarPlan.shortcut(place))"))
        .accessibilityIdentifier("RoomNavigation-\(place.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    static func spokenValue(_ value: RoomSidebarValue, activity: RoomRowActivity = RoomRowActivity(),
                            hidden: Bool = false) -> String {
        var parts: [String] = []
        switch value {
        case .none, .sparkline: break
        case .size(let text): parts.append(hidden ? "size hidden" : text)
        case .words(let text): parts.append(text)
        }
        if activity.showsSentence { parts.append(hidden ? "working" : activity.sentence) }
        if activity.unseen { parts.append("new result") }
        return parts.joined(separator: ", ")
    }

    /// Rail peek: the first one waits 350 ms; moving to the next row while one is showing (or just after) is instant.
    private func hover(_ place: RoomDestination, inside: Bool) {
        if inside {
            hoveredPlace = place
            guard !labelled else { return }
            peekTask?.cancel()
            let warm = peekPlace != nil || (lastPeekEnded.map { Date().timeIntervalSince($0) < RoomTokens.Nav.peekWarm } ?? false)
            if warm {
                peekPlace = place
            } else {
                peekTask = Task { @MainActor in
                    do { try await Task.sleep(for: RoomTokens.Nav.peekDelay) } catch { return }
                    if hoveredPlace == place { peekPlace = place }
                }
            }
        } else {
            if hoveredPlace == place { hoveredPlace = nil }
            peekTask?.cancel()
            if peekPlace == place {
                lastPeekEnded = Date()
                peekPlace = nil
            }
        }
    }

    private func peek(_ place: RoomDestination, value: RoomSidebarValue, row: RoomRowActivity) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: RoomTokens.Space.row) {
                Text(RoomSidebarPlan.title(place)).font(RoomTokens.Typography.bodyStrong)
                RoomSidebarValueView(value: value, live: false)
            }
            if row.showsSentence {
                RoomMaskable(row.sentence).font(RoomTokens.Nav.sentence).foregroundStyle(accent.text)
            }
        }
        .padding(.horizontal, RoomTokens.Space.row)
        .padding(.vertical, RoomTokens.Space.inner)
    }

    private func select(_ place: RoomDestination, origin: RoomSelectionOrigin) {
        let route = RoomRoute.screen(place)
        if let animation = Self.selectionAnimation(origin: origin, motion: motion) {
            withAnimation(animation) { navigation.select(route, origin: origin) }
        } else {
            navigation.select(route, origin: origin)
        }
    }

    private func step(_ offset: Int) {
        let from = focusedScreen ?? navigation.route.highlightedScreen ?? .overview
        let target = RoomSidebarPlan.step(from: from, by: offset)
        select(target, origin: .keyboard)
        focusedScreen = target
    }

    /// Pointer selection slides the pill on the 260 ms critically damped spring. Keyboard and programmatic selection
    /// jump, and Reduce Motion drops the travel (FEATURES rule 7).
    static func selectionAnimation(origin: RoomSelectionOrigin, motion: RoomMotionPolicy) -> Animation? {
        origin == .pointer ? motion.animation(RoomTokens.Motion.ui, fallback: nil) : nil
    }

    private var pill: RoundedRectangle { RoundedRectangle(cornerRadius: RoomTokens.Nav.pillRadius) }

    private var selectionPill: some View {
        pill.fill(RoomTokens.Surface.pill)
            .overlay(pill.strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
            .shadow(color: RoomTokens.Surface.pillShadow, radius: RoomTokens.Nav.shadowRadius, y: RoomTokens.Nav.shadowY)
            .matchedGeometryEffect(id: "sidebar-selection", in: selection)
    }

    @ViewBuilder private func groupHeading(_ group: RoomSidebarPlan.Group, first: Bool) -> some View {
        if labelled, let title = group.title {
            Text(title)
                .font(RoomTokens.Nav.group)
                .foregroundStyle(RoomTokens.Ink.tertiary)
                .lineLimit(1)
                .padding(.horizontal, RoomTokens.Space.inner + 2)
                .padding(.top, first ? 0 : RoomTokens.Nav.groupTop)
                .padding(.bottom, RoomTokens.Nav.groupBottom)
                .accessibilityAddTraits(.isHeader)
        } else if !first {
            Color.clear.frame(height: RoomTokens.Space.inner)
        }
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
