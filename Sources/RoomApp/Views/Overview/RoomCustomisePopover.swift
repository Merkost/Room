import SwiftUI

struct RoomCustomisePopover: View {
    @Bindable var rooms: RoomRoomsModel
    let capacityBytes: Int64
    @Binding var selected: UUID?
    let hidden: Bool
    var canChoosePlanStyle = false
    var hasRecentReceipts = false
    @AppStorage(RoomOverviewPreferences.densityKey) private var density = RoomTokens.Density.calm
    @AppStorage(RoomOverviewPreferences.recentReceiptKey) private var showRecent = true
    @AppStorage(RoomOverviewStyle.preferenceKey) private var style = RoomOverviewStyle.dots
    @AppStorage(RoomOverviewPreferences.greetingKey) private var greeting = true
    @AppStorage(RoomOverviewPreferences.roomsChapterKey) private var showRooms = true
    @AppStorage(RoomMenuBarSettings.goalBytesKey) private var goal = Int(RoomMenuBarSettings.defaultGoalBytes)
    @AppStorage("RoomGoalEnabled") private var useGoal = true
    @AppStorage("RoomAccent") private var accent = RoomTokens.Accent.teal
    @State private var resetBackup: (greeting: Bool, rooms: Bool, accent: RoomTokens.Accent)?
    private let resetID = "overview/reset"

    private var room: RoomPinnedRoom? {
        rooms.visibleRooms.first { $0.id == selected } ?? rooms.visibleRooms.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                Text("Customise Overview").font(RoomTokens.Typography.title).accessibilityAddTraits(.isHeader)
                RoomSettingsSwitch(title: "Greet me by name", isOn: $greeting)
                    .help("Uses your macOS full name. It stays on this Mac.")
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    Text("Free-space goal").font(RoomTokens.Typography.section)
                    RoomSettingsSwitch(title: "Use a goal", isOn: $useGoal)
                    if useGoal && !hidden {
                        RoomGoalRulerView(value: $goal, capacityBytes: capacityBytes)
                    }
                }
                Picker("Density", selection: $density) {
                    Text("Calm").tag(RoomTokens.Density.calm)
                    Text("Compact").tag(RoomTokens.Density.compact)
                }.pickerStyle(.segmented)
                if canChoosePlanStyle {
                    Picker("Overview style", selection: $style) {
                        ForEach(RoomOverviewStyle.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }.pickerStyle(.segmented)
                }
                RoomSettingsSwitch(title: "Your Rooms", isOn: $showRooms)
                if hasRecentReceipts {
                    RoomSettingsSwitch(title: "Recent receipt", isOn: $showRecent)
                }
                Picker("Accent", selection: $accent) {
                    ForEach(RoomTokens.Accent.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }.fixedSize()
                if let room {
                    Divider()
                    Picker("Room", selection: Binding(get: { room.id }, set: { selected = $0 })) {
                        ForEach(rooms.visibleRooms) { item in
                            Text(hidden ? RoomRoomsChapter.hiddenText(item.name, lettersToo: true) : item.name).tag(item.id)
                        }
                    }
                    RoomCustomiseEditor(rooms: rooms, room: room, hidden: hidden).id(room.id)
                }
                RoomInlineUndoRows(prefix: "room/unpin/")
                RoomInlineConfirmButton(id: resetID, title: "Reset Overview", confirmTitle: "Reset preferences?",
                    doneLine: "Overview preferences reset", stage: {
                        resetBackup = (greeting, showRooms, accent)
                        greeting = true
                        showRooms = true
                        accent = .teal
                    }, commit: {
                        resetBackup = nil
                    }, undo: {
                        guard let resetBackup else { return }
                        greeting = resetBackup.greeting
                        showRooms = resetBackup.rooms
                        accent = resetBackup.accent
                        self.resetBackup = nil
                    })
                RoomInlineUndoRows(prefix: resetID)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(RoomTokens.Space.group)
        }
        .frame(width: 320)
        .frame(idealHeight: 495, maxHeight: 580)
        .onAppear { if selected == nil { selected = rooms.selectedRoomID ?? rooms.rooms.first?.id } }
        .onChange(of: rooms.selectedRoomID) { _, new in if let new { selected = new } }
    }
}

private struct RoomCustomiseEditor: View {
    @Bindable var rooms: RoomRoomsModel
    let room: RoomPinnedRoom
    let hidden: Bool
    @State private var name = ""
    @State private var budget = ""
    @State private var budgetIssue = false
    @FocusState private var focus: Field?
    private enum Field { case name, budget }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            if !hidden {
                TextField("Room name", text: $name)
                    .focused($focus, equals: .name)
                    .onSubmit { rename() }
            }
            Text("Icon").font(RoomTokens.Typography.caption)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 6), spacing: 8) {
                ForEach(RoomRoomGlyph.allCases, id: \.self) { glyph in
                    Button {
                        rooms.setLook(id: room.id, glyph: glyph)
                    } label: {
                        Image(systemName: glyph.rawValue)
                            .frame(width: 30, height: 26)
                            .background(room.resolvedGlyph == glyph ? RoomTokens.Surface.press : .clear,
                                        in: .rect(cornerRadius: RoomTokens.Radius.field))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(glyph.rawValue.replacingOccurrences(of: ".", with: " ").capitalized)
                        .accessibilityAddTraits(room.resolvedGlyph == glyph ? .isSelected : [])
                }
            }
            Text("Colour").font(RoomTokens.Typography.caption)
            HStack(spacing: 8) {
                ForEach(RoomRoomColour.allCases, id: \.self) { colour in
                    let kind = RoomTokens.Kind(rawValue: colour.rawValue) ?? .developer
                    Button {
                        rooms.setLook(id: room.id, colour: colour)
                    } label: {
                        RoundedRectangle(cornerRadius: RoomTokens.Radius.field).fill(kind.fill)
                            .frame(width: 25, height: 22)
                            .overlay {
                                if room.resolvedColour == colour {
                                    Image(systemName: "checkmark").foregroundStyle(RoomTokens.Kind.tileInk)
                                }
                            }
                    }.buttonStyle(.plain)
                        .accessibilityLabel(colour.rawValue.capitalized)
                        .accessibilityAddTraits(room.resolvedColour == colour ? .isSelected : [])
                }
            }
            if !hidden {
                TextField("Budget (GB)", text: $budget).focused($focus, equals: .budget)
                    .help("Use a whole number from 1 to 9,999 GB. Clear to remove the budget.")
                    .onSubmit { saveBudget() }
                if budgetIssue {
                    Text("Enter 1–9,999 GB or leave the budget blank.")
                        .font(RoomTokens.Typography.caption).foregroundStyle(RoomTokens.Status.elevated)
                }
            }
            HStack(spacing: RoomTokens.Space.row) {
                Button("Move Up") { rooms.move(id: room.id, to: room.order - 1) }.disabled(room.order == 0)
                Button("Move Down") { rooms.move(id: room.id, to: room.order + 1) }
                    .disabled(room.order >= rooms.rooms.count - 1)
            }
            RoomInlineConfirmButton(id: "room/unpin/" + room.id.uuidString, title: "Forget this Room",
                confirmTitle: "Forget this Room?", doneLine: "Room forgotten", isAllowed: rooms.canUnpin,
                stage: { rooms.stageUnpin(room.id) }, commit: { rooms.commitUnpin(room.id) },
                undo: { rooms.undoUnpin(room.id) })
                .help("Removes its Room and size history. Folder access is kept.")
        }
        .onAppear {
            name = room.name
            budget = room.budgetBytes.map { String($0 / RoomRoomsCatalog.bytesPerGB) } ?? ""
        }
        .onChange(of: focus) { previous, _ in
            if previous == .name { rename() }
            if previous == .budget { saveBudget() }
        }
    }

    private func rename() {
        rooms.rename(id: room.id, to: name)
        name = rooms.rooms.first { $0.id == room.id }?.name ?? room.name
    }

    private func saveBudget() {
        let trimmed = budget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty || Int(trimmed) != nil else { budgetIssue = true; return }
        budgetIssue = !rooms.setBudget(id: room.id, gb: Int(trimmed))
    }
}
