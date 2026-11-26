import SwiftUI

/// Go to (⌘K, or K in the sidebar): a glass bar over a quiet scrim. Type, arrow, Return; Escape closes.
struct RoomCommandBarView: View {
    let items: [RoomCommandBar.Item]
    let close: () -> Void
    /// Runs an item; `keyboard` is true for Return (keyboard actions never animate).
    let run: (RoomCommandBar.Item, Bool) -> Void
    /// Opened by the pointer: the glass arrives (mockup `.pal`); from the keyboard it is simply there.
    var animated = true

    @State private var bar = RoomCommandBar()
    @State private var arrived = false
    @Environment(\.roomMotion) private var motion
    @FocusState private var fieldFocused: Bool
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    var body: some View {
        let results = bar.results(in: items)
        ZStack(alignment: .top) {
            RoomTokens.Surface.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                TextField("Go to a place, or do something", text: Binding(get: { bar.query }, set: { bar.type($0) }))
                    .textFieldStyle(.plain)
                    .font(RoomTokens.Screen2.commandField)
                    .padding(.horizontal, RoomTokens.Space.row)
                    .frame(height: 40)
                    .focused($fieldFocused)
                    .onKeyPress(.downArrow) { bar.move(1, count: results.count); return .handled }
                    .onKeyPress(.upArrow) { bar.move(-1, count: results.count); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onSubmit { if let item = bar.chosen(in: results) { run(item, true) } }
                    .accessibilityLabel("Go to")
                    .accessibilityHint("Type a place or an action, then press Return")
                Rectangle().fill(RoomTokens.Surface.line).frame(height: 0.5)
                if results.isEmpty {
                    Text("Nothing by that name")
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .padding(.horizontal, RoomTokens.Space.row)
                        .padding(.vertical, 14)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, highlighted: index == bar.highlight)
                                    .onHover { if $0 { bar.point(at: index, count: results.count) } }
                                    .onTapGesture { run(item, false) }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxHeight: RoomTokens.Screen2.commandListMax)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(width: RoomTokens.Screen2.commandWidth)
            .background(RoomTokens.Surface.sheetGlass, in: RoundedRectangle(cornerRadius: RoomTokens.Screen2.commandRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: RoomTokens.Screen2.commandRadius, style: .continuous)
                .strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
            .shadow(color: RoomTokens.Surface.panelShadow, radius: 30, y: 30)
            .offset(y: arrived || !motion.isFull ? 0 : -10)
            .scaleEffect(arrived || !motion.isFull ? 1 : 0.96, anchor: UnitPoint(x: 0.12, y: 0))
            .opacity(arrived ? 1 : 0)
            .padding(.top, RoomTokens.Screen2.commandTop)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel("Go to")
        }
        .onAppear {
            fieldFocused = true
            if animated {
                withAnimation(motion.animation(RoomTokens.Motion.glass, fallback: RoomTokens.Motion.fade)) { arrived = true }
            } else {
                arrived = true
            }
        }
    }

    private func row(_ item: RoomCommandBar.Item, highlighted: Bool) -> some View {
        HStack(spacing: RoomTokens.Space.row) {
            RoomGlyphView(glyph: item.glyph).foregroundStyle(highlighted ? accent.text : RoomTokens.Ink.secondary)
            Text(item.title).foregroundStyle(RoomTokens.Ink.graphite).lineLimit(1)
            Spacer(minLength: RoomTokens.Space.row)
            RoomSidebarValueView(value: item.value)
        }
        .padding(.horizontal, RoomTokens.Space.row)
        .frame(height: RoomTokens.Screen2.commandRow)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: RoomTokens.Radius.row)
                    .fill(RoomTokens.Surface.pill)
                    .overlay(RoundedRectangle(cornerRadius: RoomTokens.Radius.row).strokeBorder(RoomTokens.Surface.line, lineWidth: 0.5))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(RoomSidebar.spokenValue(item.value, hidden: hide.masksNow))
        .accessibilityAddTraits(highlighted ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { run(item, false) }
    }
}

/// The sidebar's "Go to ⌘K" field (a button that opens the bar).
struct RoomGoToField: View {
    let labelled: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                RoomGlyphView(glyph: .search, size: 13, weight: 1.6)
                if labelled {
                    Text("Go to").font(RoomTokens.Nav.goFont)
                    Spacer(minLength: 0)
                    Text(verbatim: "⌘K").font(RoomTokens.Typography.micro)
                }
            }
            .foregroundStyle(RoomTokens.Ink.tertiary)
            .padding(.horizontal, labelled ? 9 : 0)
            .frame(maxWidth: .infinity, minHeight: RoomTokens.Nav.goHeight)
            .background(RoomTokens.Surface.tile, in: RoundedRectangle(cornerRadius: RoomTokens.Nav.goRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomPressStyle())
        .help("Go to (⌘K)")
        .accessibilityLabel("Go to")
        .accessibilityHint("Command K")
        .accessibilityIdentifier("RoomGoTo")
    }
}
