import SwiftUI

/// Caches' evidence (nav-v3): one row per place that can go, with a tick, its real icon, counted dots in the accent and
/// the size. Unticking a place recounts the button. A quiet line says what Room keeps safe.
struct RoomCachesPlaces: View {
    let model: RoomViewModel
    let inspect: (RoomSource) -> Void
    let showKept: () -> Void
    var neverSuggest: ((RoomSource) -> Void)?

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomHide) private var hide
    @FocusState private var focused: String?

    private var places: [RoomSource] { model.sources.filter(\.isAvailable).sorted { $0.eligibleBytes > $1.eligibleBytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, source in
                row(source)
                    .roomEnter(2 + index)
                    .transition(transition(index))
            }
            keptLine
                .padding(.top, RoomTokens.Space.row)
                .roomEnter(2 + places.count)
        }
        .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade), value: places.map(\.id))
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
    }

    private func row(_ source: RoomSource) -> some View {
        let on = model.selection.contains(source.id)
        let partial = model.partiallySelectedSource(source.id)
        let canSelect = model.canEditSelection
        return Button {
            model.toggleSelection(id: source.id)
        } label: {
            RoomEvidenceRow(name: source.name, meta: source.subtitle, bytes: source.eligibleBytes, masksName: false,
                            barColor: accent.text, dimmed: !on,
                            nameColumn: RoomTokens.Screen2.listNameColumnWide) {
                HStack(spacing: RoomTokens.Space.row) {
                    RoomTick(on: on, partial: partial)
                    RoomThingIcon(path: source.path, name: source.name, fallback: .box)
                }
            }
            .padding(.horizontal, RoomTokens.Space.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.row))
        .padding(.horizontal, -RoomTokens.Space.row)
        .disabled(!canSelect)
        .focused($focused, equals: source.id)
        .accessibilityLabel(source.name)
        .accessibilityValue("\(hide.masksNow ? "size hidden" : RoomFormat.gb(source.eligibleBytes)), \(on ? (partial ? "partly chosen" : "chosen") : "not chosen")")
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityHint("Toggles this place in the review")
        .contextMenu {
            Button("Show Details…") { inspect(source) }
            Button("Show in Finder") { model.reveal(source: source) }
            if let neverSuggest { Button("Don’t Suggest Again") { neverSuggest(source) } }
        }
    }

    @ViewBuilder private var keptLine: some View {
        let held = model.heldBytes + model.protectedSources.reduce(Int64(0)) { $0 + $1.bytes }
        let places = model.protectedSources.count + model.sources.filter { !$0.heldReasons.isEmpty }.count
        if held > 0 || places > 0 {
            Button(action: showKept) {
                HStack(spacing: 4) {
                    RoomMaskable(held > 0 ? "\(RoomFormat.gb(held)) kept safe" : "Kept safe")
                    Text(places == 1 ? "in 1 place Room will not touch" : "in \(places) places Room will not touch")
                    Text(verbatim: "›").foregroundStyle(RoomTokens.Ink.tertiary)
                }
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
            }
            .buttonStyle(RoomPressStyle())
            .accessibilityHint("Shows what stays and why")
        }
    }

    private func transition(_ index: Int) -> AnyTransition {
        guard !hide.masksNow, motion.isFull else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 8).combined(with: .opacity)
                .animation(RoomTokens.Motion.ui.delay(RoomDS.Motion.stagger(index))),
            removal: .opacity)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let ids = places.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let current = focused.flatMap { ids.firstIndex(of: $0) } ?? (delta > 0 ? -1 : ids.count)
        focused = ids[min(ids.count - 1, max(0, current + delta))]
        return .handled
    }
}

/// The round tick: filled accent with a check when chosen, an empty ring when not, a dash when partly chosen.
struct RoomTick: View {
    let on: Bool
    var partial = false
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion

    var body: some View {
        let size = RoomTokens.Screen2.tick
        ZStack {
            Circle().fill(on ? accent.text : Color.clear)
            Circle().strokeBorder(on ? Color.clear : RoomTokens.Ink.tertiary, lineWidth: 1.5)
            if partial {
                Capsule().fill(RoomTokens.Surface.canvas).frame(width: size * 0.45, height: 2)
            } else {
                RoomTickMark()
                    .trim(from: 0, to: on ? 1 : 0)
                    .stroke(RoomTokens.Surface.canvas,
                            style: StrokeStyle(lineWidth: RoomTokens.Screen2.tickStroke, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: on)
        .accessibilityHidden(true)
    }
}

/// The tick's check in its 18 x 18 box (mockup `M5.2 9.4l2.6 2.6L12.8 6.6`).
nonisolated struct RoomTickMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 5.2 * s, y: rect.minY + 9.4 * s))
        path.addLine(to: CGPoint(x: rect.minX + 7.8 * s, y: rect.minY + 12 * s))
        path.addLine(to: CGPoint(x: rect.minX + 12.8 * s, y: rect.minY + 6.6 * s))
        return path
    }
}
