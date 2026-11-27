import SwiftUI

/// Caches' evidence: everything found, grouped by what you can do with it. Safe places are ticked for you,
/// recently used ones are yours to tick, and places whose app is open wait until it is closed.
struct RoomCachesPlaces: View {
    let model: RoomViewModel
    let inspect: (RoomSource) -> Void
    var neverSuggest: ((RoomSource) -> Void)?

    @Environment(\.roomAccent) private var accent
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomHide) private var hide
    @FocusState private var focused: String?

    private var safe: [RoomSource] {
        model.sources.filter(\.isAvailable).sorted { $0.eligibleBytes > $1.eligibleBytes }
    }

    private var inUseTitle: String {
        #if ROOM_APP_STORE
        "Can’t tick here"
        #else
        "Open right now"
        #endif
    }

    private var inUseHint: String {
        #if ROOM_APP_STORE
        "this version can’t see running apps"
        #else
        "quit the app to tick"
        #endif
    }

    private var keys: [String] { safe.map(\.id) + model.recentRows.map(\.id) }

    var body: some View {
        let safe = safe
        VStack(alignment: .leading, spacing: 2) {
            if !safe.isEmpty {
                head("Safe to remove", bytes: safe.reduce(0) { $0 + $1.eligibleBytes }, hint: "ticked for you", first: true)
                ForEach(Array(safe.enumerated()), id: \.element.id) { index, source in
                    row(key: source.id, source: source, name: source.name, note: source.subtitle, path: source.path,
                        bytes: source.eligibleBytes)
                        .roomEnter(2 + index)
                        .transition(transition(index))
                }
            }
            if !model.recentRows.isEmpty {
                head("Used recently", bytes: model.recentBytes, hint: "tick if you want them gone", first: safe.isEmpty)
                ForEach(model.recentRows) { item in
                    row(key: item.id, source: model.sources.first { $0.id == item.sourceID }, name: item.name,
                        note: item.note, path: item.path, bytes: item.bytes)
                }
            }
            if !model.inUseRows.isEmpty {
                head(inUseTitle, bytes: model.inUseRows.reduce(0) { $0 + $1.bytes }, hint: inUseHint,
                     first: safe.isEmpty && model.recentRows.isEmpty)
                ForEach(model.inUseRows) { waitingRow($0) }
            }
        }
        .animation(motion.animation(RoomTokens.Motion.ui, fallback: RoomTokens.Motion.fade), value: keys)
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
    }

    private func head(_ title: String, bytes: Int64, hint: String, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.inner) {
            Text(title).font(RoomTokens.Screen2.listName).foregroundStyle(RoomTokens.Ink.graphite)
            RoomMaskable(RoomFormat.gb(bytes)).font(RoomTokens.Screen2.listMeta).foregroundStyle(RoomTokens.Ink.secondary)
            Spacer(minLength: RoomTokens.Space.row)
            Text(hint).font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Ink.tertiary)
        }
        .padding(.top, first ? 0 : RoomTokens.Space.group)
        .padding(.bottom, RoomTokens.Space.tight)
        .overlay(alignment: .bottom) { Rectangle().fill(RoomTokens.Surface.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(key: String, source: RoomSource?, name: String, note: String, path: String, bytes: Int64) -> some View {
        let on = model.selection.contains(key)
        let partial = model.partiallySelectedSource(key)
        return Button {
            model.toggleSelection(id: key)
        } label: {
            RoomEvidenceRow(name: name, meta: note, bytes: bytes, masksName: false, barColor: accent.text,
                            dimmed: !on, nameColumn: RoomTokens.Screen2.listNameColumnWide) {
                HStack(spacing: RoomTokens.Space.row) {
                    RoomTick(on: on, partial: partial)
                    RoomThingIcon(path: path, name: name, fallback: .box)
                }
            }
            .padding(.horizontal, RoomTokens.Space.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.row))
        .padding(.horizontal, -RoomTokens.Space.row)
        .disabled(!model.canEditSelection)
        .focused($focused, equals: key)
        .accessibilityLabel("\(name), \(note)")
        .accessibilityValue("\(hide.masksNow ? "size hidden" : RoomFormat.gb(bytes)), \(on ? (partial ? "partly chosen" : "chosen") : "not chosen")")
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityHint("Toggles this place in the review")
        .contextMenu {
            if let source {
                Button("Show Details…") { inspect(source) }
                Button("Show in Finder") { model.reveal(source: source) }
                if let neverSuggest { Button("Don’t Suggest Again") { neverSuggest(source) } }
            }
        }
    }

    /// Not a button: there is nothing to tick until its app is closed.
    private func waitingRow(_ item: RoomCacheRow) -> some View {
        RoomEvidenceRow(name: item.name, meta: item.note, bytes: item.bytes, masksName: false, dimmed: true,
                        nameColumn: RoomTokens.Screen2.listNameColumnWide) {
            HStack(spacing: RoomTokens.Space.row) {
                Circle()
                    .strokeBorder(RoomTokens.Ink.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                    .frame(width: RoomTokens.Screen2.tick, height: RoomTokens.Screen2.tick)
                    .accessibilityHidden(true)
                RoomThingIcon(path: item.path, name: item.name, fallback: .box)
            }
        }
        .contextMenu {
            if let source = model.sources.first(where: { $0.id == item.sourceID }) {
                Button("Show Details…") { inspect(source) }
                Button("Show in Finder") { model.reveal(source: source) }
            }
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
        let ids = keys
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
