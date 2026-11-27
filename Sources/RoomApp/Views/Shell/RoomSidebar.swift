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
    var openGoTo: (_ keyboard: Bool) -> Void = { _ in }
    var fold: () -> Void = {}

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomHide) private var hide
    @State private var hoveredPlace: RoomDestination?
    @State private var peekPlace: RoomDestination?
    @State private var peekTask: Task<Void, Never>?
    @State private var lastPeekEnded: Date?
    @Environment(\.roomAccent) private var accent
    @FocusState private var focusedScreen: RoomDestination?
    /// The panel itself holds focus when no row does, so the window always has a focused view (the menu bar's
    /// screen commands read the scene's focused values) and 1 to 7, the arrows, K and H work from the first frame.
    @FocusState private var panelFocused: Bool
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
            lightsRow
            RoomGoToField(labelled: labelled) { openGoTo(RoomSelectionOrigin.controlActivation == .keyboard) }
                .padding(.horizontal, labelled ? 2 : 8)
                .padding(.bottom, RoomTokens.Nav.goBottom)
            ScrollView {
                VStack(alignment: .leading, spacing: RoomTokens.Nav.rowGap) {
                    ForEach([RoomSidebarPlan.Group.yourMac, .makeRoom, .rightNow], id: \.self) { group in
                        groupHeading(group, first: group == .yourMac)
                        ForEach(RoomSidebarPlan.places(in: group), id: \.self) { place in
                            placeRow(place)
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
            } else if let meter = RoomNameplateMeter.make(capacityBytes: plate.capacityBytes, freeBytes: plate.freeBytes,
                                                         couldGoBytes: plate.couldGoBytes) {
                // The rail keeps the meter (mockup `.rail .plate`: name and line fade, the meter stays).
                RoomNameplateMeterView(meter: meter)
                    .padding(.horizontal, 6)
                    .padding(.top, RoomTokens.Space.group)
                    .padding(.bottom, RoomTokens.Space.tight)
                    .overlay(alignment: .top) { Rectangle().fill(RoomTokens.Surface.line).frame(height: 0.5) }
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, RoomTokens.Nav.columnPadding)
        .padding(.top, RoomTokens.Nav.panelTop)
        .padding(.bottom, RoomTokens.Nav.panelBottom)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoomTrafficLights(hidden: !labelled))
        .overlayPreferenceValue(RoomPeekAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let anchor, !labelled {
                    let rect = geometry[anchor.bounds]
                    let place = anchor.place
                    peek(place, value: RoomSidebarValue.make(place, values), row: activity[place] ?? RoomRowActivity())
                        .fixedSize()
                        .background(RoomTokens.Surface.glass, in: RoundedRectangle(cornerRadius: RoomTokens.Nav.peekRadius, style: .continuous))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: RoomTokens.Nav.peekRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: RoomTokens.Nav.peekRadius, style: .continuous)
                            .strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
                        .shadow(color: RoomTokens.Surface.panelShadow, radius: 14, y: 10)
                        .frame(height: rect.height)
                        .offset(x: geometry.size.width + RoomTokens.Nav.peekGap, y: rect.minY)
                        .transition(.roomPeek(motion))
                        .id(place)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($panelFocused)
        .onAppear { if focusedScreen == nil { panelFocused = true } }
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
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room places")
        .onModifierKeysChanged(mask: .command, initial: true) { _, keys in commandHeld = keys.contains(.command) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            commandHeld = false
        }
    }

    /// The window's traffic lights sit in this row (drawn by the system); the fold button is on its right. On the rail
    /// the lights step aside and the fold button takes the row's centre (mockup `.rail .lights`).
    private var lightsRow: some View {
        HStack(spacing: 0) {
            if labelled { Spacer(minLength: 0) }
            Button(action: fold) {
                RoomGlyphView(glyph: .fold, size: 16, weight: 1.3)
                    .foregroundStyle(RoomTokens.Ink.secondary)
                    .frame(width: RoomTokens.Nav.foldSize, height: RoomTokens.Nav.foldSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Nav.foldRadius))
            .help(labelled ? "Collapse sidebar (⌃⌘S)" : "Expand sidebar (⌃⌘S)")
            .accessibilityLabel(labelled ? "Collapse sidebar" : "Expand sidebar")
            .padding(.trailing, labelled ? 6 : 0)
            .offset(y: labelled ? RoomTokens.Nav.foldLift : 0)
        }
        .frame(maxWidth: .infinity, alignment: labelled ? .trailing : .center)
        .frame(height: RoomTokens.Nav.lightsRow - RoomTokens.Nav.lightsBottom + RoomTokens.Nav.lightsBottom / 2)
        .padding(.bottom, RoomTokens.Nav.lightsBottom / 2)
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
        .anchorPreference(key: RoomPeekAnchorKey.self, value: .bounds) { anchor in
            peekPlace == place && !labelled ? RoomPeekAnchor(place: place, bounds: anchor) : nil
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
                // The rest are instant (mockup `.peek.instant`).
                withAnimation(nil) { peekPlace = place }
            } else {
                peekTask = Task { @MainActor in
                    do { try await Task.sleep(for: RoomTokens.Nav.peekDelay) } catch { return }
                    if hoveredPlace == place {
                        withAnimation(motion.animation(RoomTokens.Motion.peek, fallback: RoomTokens.Motion.fade)) { peekPlace = place }
                    }
                }
            }
        } else {
            if hoveredPlace == place { hoveredPlace = nil }
            peekTask?.cancel()
            if peekPlace == place {
                lastPeekEnded = Date()
                withAnimation(motion.animation(RoomTokens.Motion.peekOut, fallback: RoomTokens.Motion.fade)) { peekPlace = nil }
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
                .padding(.top, RoomTokens.Nav.groupTop)
                .padding(.bottom, RoomTokens.Nav.groupBottom)
                .accessibilityAddTraits(.isHeader)
        } else if !first {
            Color.clear.frame(height: RoomTokens.Nav.railGroupGap)
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

/// The window's close, minimise and zoom buttons sit in the panel's top row (the shell keeps an empty unified toolbar
/// so the title bar is 52 pt tall and centres them there); they step aside while the sidebar is a rail (mockup
/// `.rail .lights i`).
private struct RoomTrafficLights: NSViewRepresentable {
    let hidden: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let hidden = hidden
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = hidden
            }
        }
    }
}

/// Where the rail's peek points: the hovered row's bounds.
struct RoomPeekAnchor {
    let place: RoomDestination
    let bounds: Anchor<CGRect>
}

struct RoomPeekAnchorKey: PreferenceKey {
    static let defaultValue: RoomPeekAnchor? = nil
    static func reduce(value: inout RoomPeekAnchor?, nextValue: () -> RoomPeekAnchor?) {
        value = value ?? nextValue()
    }
}

/// The peek is glass that arrives (mockup `.peek`): from 6 pt left and 97 %, anchored on its leading edge.
private struct RoomPeekArrival: ViewModifier {
    let shown: Bool
    func body(content: Content) -> some View {
        content.offset(x: shown ? 0 : -6).scaleEffect(shown ? 1 : 0.97, anchor: .leading).opacity(shown ? 1 : 0)
    }
}

extension AnyTransition {
    @MainActor static func roomPeek(_ motion: RoomMotionPolicy) -> AnyTransition {
        motion.isFull ? .modifier(active: RoomPeekArrival(shown: false), identity: RoomPeekArrival(shown: true)) : .opacity
    }
}
