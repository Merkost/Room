import AppKit
import SwiftUI

/// The window's navigation: five places with their figures and engine states, then the open screen's next step in a
/// slot that never moves. History, Settings and Go to sit in the top bar.
struct RoomDock: View {
    let navigation: RoomWindowNavigation
    var values = RoomPlaceValue.Input()
    var activity: [RoomDestination: RoomRowActivity] = [:]
    var belowGoal = false
    var actions: RoomDockActions? = nil
    var stop: (RoomDestination) -> Void = { _ in }
    var openGoTo: (_ keyboard: Bool) -> Void = { _ in }

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomHide) private var hide
    @Environment(\.roomAccent) private var accent
    @State private var hoveredPlace: RoomDestination?
    @State private var commandHeld = false
    @FocusState private var focusedPlace: RoomDestination?
    /// The dock itself holds focus when no item does, so the window always has a focused view (the menu bar's screen
    /// commands read the scene's focused values) and 1 to 7, the arrows, K and H work from the first frame.
    @FocusState private var dockFocused: Bool
    @Namespace private var selection

    /// The places as menu items (the Go menu and its tests read titles and ⌘ numbers from here).
    static let items: [NavigationItem] = RoomPlacePlan.places.map { place in
        let menu = RoomMenuModel.Destination(rawValue: place.rawValue)
        return NavigationItem(destination: place, title: RoomPlacePlan.title(place), symbol: menu?.symbol ?? "",
                              shortcut: Character(String(RoomPlacePlan.shortcut(place))))
    }

    /// Stop exists where an engine can stop; a cleanup that is moving files has none.
    static func canStop(_ place: RoomDestination) -> Bool { [.clean, .developer, .disk].contains(place) }

    var body: some View {
        HStack(spacing: RoomTokens.Dock.itemGap) {
            ForEach(RoomPlacePlan.dock, id: \.self) { item($0) }
            Rectangle().fill(RoomTokens.Surface.line)
                .frame(width: 0.5, height: RoomTokens.Dock.dividerHeight)
                .padding(.horizontal, RoomTokens.Space.row)
            slot
        }
        .padding(RoomTokens.Dock.padding)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: RoomTokens.Dock.radius, style: .continuous))
        .shadow(color: RoomTokens.Surface.panelShadow, radius: RoomTokens.Nav.panelShadowRadius, y: RoomTokens.Nav.panelShadowY)
        .fixedSize()
        .focusable()
        .focusEffectDisabled()
        .focused($dockFocused)
        .onAppear { if focusedPlace == nil { dockFocused = true } }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "kKhH"), phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            if press.characters.lowercased() == "k" { openGoTo(true) } else { RoomHideControl.shared.toggle() }
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard press.modifiers.isEmpty, let number = Int(press.characters),
                  let target = RoomPlacePlan.place(forShortcut: number) else { return .ignored }
            select(target, origin: .keyboard)
            return .handled
        }
        .onModifierKeysChanged(mask: .command, initial: true) { _, keys in commandHeld = keys.contains(.command) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            commandHeld = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room places")
    }

    // MARK: Places

    private func item(_ place: RoomDestination) -> some View {
        let selected = navigation.route.highlightedScreen == place
        let value = RoomPlaceValue.make(place, values)
        let title = RoomPlacePlan.title(place)
        let row = activity[place] ?? RoomRowActivity()
        let raised = hoveredPlace == place || focusedPlace == place
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Dock.itemRadius, style: .continuous)
        return Button {
            select(place, origin: RoomSelectionOrigin.controlActivation)
        } label: {
            VStack(spacing: 2) {
                RoomPlaceTile(glyph: RoomPlacePlan.glyph(place), selected: selected, activity: row)
                Text(title)
                    .font(selected ? RoomTokens.Dock.titleSelected : RoomTokens.Dock.title)
                    .foregroundStyle(RoomTokens.Ink.graphite)
                    .lineLimit(1)
                figure(place, value: value, row: row)
                    .frame(height: RoomTokens.Dock.figureHeight)
                    // A finished scan bumps its figure once.
                    .phaseAnimator([false, true, false], trigger: row.finishedAt) { figure, bumped in
                        figure.scaleEffect(bumped && row.finishedAt != nil && motion.isFull ? 1.25 : 1)
                    } animation: { _ in RoomTokens.Motion.check }
            }
            .offset(y: raised && !selected && motion.isFull ? -RoomTokens.Dock.hoverLift : 0)
            .frame(width: RoomTokens.Dock.itemWidth, height: RoomTokens.Dock.itemHeight)
            .background {
                if selected {
                    shape.fill(RoomTokens.Surface.pill)
                        .overlay(shape.strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
                        .matchedGeometryEffect(id: "dock-selection", in: selection)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Dock.itemRadius, showsFeedback: !selected))
        .focused($focusedPlace, equals: place)
        .onKeyPress(.return) { select(place, origin: .keyboard); return .handled }
        .onKeyPress(.space) { select(place, origin: .keyboard); return .handled }
        .overlay(alignment: .bottom) {
            if raised, row.showsSentence {
                bubble(place, row: row)
                    // The padding reaches down to the item, so the pointer can travel up to Stop without losing it.
                    .padding(.bottom, RoomTokens.Dock.itemHeight + RoomTokens.Dock.padding)
                    .transition(.opacity)
            }
        }
        .onHover { inside in
            withAnimation(motion.animation(RoomTokens.Motion.hover, fallback: RoomTokens.Motion.fade)) {
                if inside { hoveredPlace = place } else if hoveredPlace == place { hoveredPlace = nil }
            }
        }
        .help("\(title) (⌘\(RoomPlacePlan.shortcut(place)))")
        .accessibilityLabel(title)
        .accessibilityValue(Self.spokenValue(value, activity: row, hidden: hide.masksNow)
            + (place == .overview && belowGoal ? ", under your goal" : ""))
        .accessibilityAction(named: "Stop") { if row.isWorking, Self.canStop(place) { stop(place) } }
        .accessibilityHint(Text(verbatim: "Command \(RoomPlacePlan.shortcut(place))"))
        .accessibilityIdentifier("RoomNavigation-\(place.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private func figure(_ place: RoomDestination, value: RoomPlaceValue, row: RoomRowActivity) -> some View {
        if commandHeld {
            caption("⌘\(RoomPlacePlan.shortcut(place))")
        } else if row.isWorking {
            caption(row.of.map { "\(row.done)/\($0)" } ?? "…")
        } else if row.phase == .failed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(RoomTokens.Typography.micro)
                .foregroundStyle(RoomTokens.Status.elevated)
        } else if place == .overview, belowGoal, case .size(let text) = value {
            RoomMaskable(text).font(RoomTokens.Nav.valueUnseen).foregroundStyle(RoomTokens.Status.elevated)
        } else if value == .none {
            caption("—")
        } else {
            RoomPlaceValueView(value: value, emphasised: row.unseen)
                .contentTransition(.numericText())
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(RoomTokens.Nav.value).foregroundStyle(RoomTokens.Ink.tertiary)
            .contentTransition(.numericText()).accessibilityHidden(true)
    }

    /// What the place's engine is doing, with Stop where it can stop.
    private func bubble(_ place: RoomDestination, row: RoomRowActivity) -> some View {
        let shape = RoundedRectangle(cornerRadius: RoomTokens.Nav.peekRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            RoomMaskable(row.sentence)
                .font(RoomTokens.Nav.sentence)
                .foregroundStyle(row.showsCheck ? accent.text : RoomTokens.Ink.graphite)
            if let dots = row.dots { RoomCountedDots(total: dots.total, filled: dots.filled) }
            if row.isWorking, Self.canStop(place) {
                Button("Stop") { stop(place) }
                    .roomLink(accent)
                    .font(RoomTokens.Nav.value.weight(.medium))
                    .accessibilityLabel("Stop \(RoomPlacePlan.title(place))")
            }
        }
        .padding(.horizontal, RoomTokens.Space.row)
        .padding(.vertical, RoomTokens.Space.inner)
        .background(RoomTokens.Surface.toastGlass, in: shape)
        .overlay(shape.strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
        .shadow(color: RoomTokens.Surface.panelShadow, radius: 14, y: 8)
        .fixedSize()
    }

    // MARK: The action slot

    /// Fixed width, so the places never shift as the screen's next step changes.
    private var slot: some View {
        HStack(spacing: RoomTokens.Space.inner) {
            ZStack {
                if let side = actions?.side { sideButton(side) }
            }
            .frame(width: RoomTokens.Dock.sideSize, height: RoomTokens.Dock.sideSize)
            ZStack {
                if let main = actions?.main { mainButton(main) }
            }
            .frame(width: RoomTokens.Dock.mainWidth, height: RoomTokens.Dock.itemHeight)
        }
        .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade), value: actions)
    }

    @ViewBuilder private func mainButton(_ action: RoomDockAction) -> some View {
        let button = Button(action: action.perform) {
            HStack(spacing: RoomTokens.Space.inner) {
                if let symbol = action.symbol { Image(systemName: symbol) }
                Text(action.title).contentTransition(.numericText())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: RoomTokens.Dock.mainLabelWidth)
        }
        .disabled(!action.enabled)
        .help(action.hint ?? action.title)
        .accessibilityHint(action.hint ?? "")
        .accessibilityIdentifier(action.identifier)
        if action.filled {
            button.roomScreenPrimary(accent) // one-filled: the dock's, the window's only filled button
        } else {
            button.roomQuiet(large: true)
        }
    }

    private func sideButton(_ action: RoomDockAction) -> some View {
        Button(action: action.perform) {
            Image(systemName: action.symbol ?? "arrow.clockwise")
                .font(RoomTokens.Typography.bodyStrong)
                .frame(width: RoomTokens.Dock.sideSize, height: RoomTokens.Dock.sideSize)
                .background(RoomTokens.Surface.tile, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(RoomPressStyle())
        .foregroundStyle(action.enabled ? RoomTokens.Ink.graphite : RoomTokens.Ink.tertiary)
        .disabled(!action.enabled)
        .help(action.title)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier(action.identifier)
    }

    // MARK: Moving

    static func spokenValue(_ value: RoomPlaceValue, activity: RoomRowActivity = RoomRowActivity(),
                            hidden: Bool = false) -> String {
        var parts: [String] = []
        switch value {
        case .none: break
        case .size(let text): parts.append(hidden ? "size hidden" : text)
        case .words(let text): parts.append(text)
        }
        if activity.showsSentence { parts.append(hidden ? "working" : activity.sentence) }
        if activity.unseen { parts.append("new result") }
        return parts.joined(separator: ", ")
    }

    /// Pointer selection slides the pill on the 260 ms critically damped spring. Keyboard and programmatic selection
    /// jump, and Reduce Motion drops the travel.
    static func selectionAnimation(origin: RoomSelectionOrigin, motion: RoomMotionPolicy) -> Animation? {
        origin == .pointer ? motion.animation(RoomTokens.Motion.ui, fallback: nil) : nil
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
        let from = focusedPlace ?? navigation.route.highlightedScreen ?? .disk
        let target = RoomPlacePlan.step(from: from, by: offset)
        select(target, origin: .keyboard)
        if RoomPlacePlan.dock.contains(target) { focusedPlace = target }
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
