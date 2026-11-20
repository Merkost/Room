import SwiftUI

struct RoomChapterRooms: View {
    let rooms: RoomRoomsModel
    let calendar: Calendar
    let editing: UUID?
    let openRoom: (URL) -> Void
    let showAll: () -> Void
    @Environment(\.roomAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        let shown = RoomRoomsChapter.shown(rooms.visibleRooms, editing: editing)
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            heading(showsHistory: !shown.rows.isEmpty)
            roomList(shown.rows)
                .roomPanelChange(shown.rows.isEmpty)
            footer(more: shown.more)
            if let notice = rooms.notice {
                Text(notice)
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.popover))
        .accessibilityIdentifier("RoomOverviewRooms")
        .onScrollVisibilityChange(threshold: 0.1) { isVisible in
            visible = isVisible
            updateMeasuring()
        }
        .onChange(of: scenePhase) { _, _ in updateMeasuring() }
        .onDisappear { rooms.setOverviewChapterActive(false) }
    }

    private func heading(showsHistory: Bool) -> some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Label("Your Rooms", systemImage: "folder")
                .font(RoomTokens.Typography.title)
                .accessibilityHeading(.h2)
            if showsHistory {
                Text("12-week history")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }

    @ViewBuilder
    private func roomList(_ pinned: [RoomPinnedRoom]) -> some View {
        if pinned.isEmpty {
            Text("Pin a folder to watch it here.")
                .font(RoomTokens.Typography.body)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let unavailable = rooms.unavailable
            let now = Date()
            VStack(spacing: RoomTokens.Space.tight) {
                ForEach(pinned) { room in
                    let needsAccess = unavailable.contains(room.id)
                    let row = RoomRoomsChapter.row(room, log: rooms.log(for: room.id), unavailable: needsAccess,
                                                  now: now, calendar: calendar, hidden: false, format: RoomFormat.bytes)
                    RoomChapterRow(room: room, row: row) {
                        if !needsAccess, let url = rooms.url(for: room.id) { openRoom(url) }
                        else { rooms.chooseFolder(replacingApprovalFor: room.id) }
                    }
                    .disabled(needsAccess && !rooms.canChooseFolder)
                }
            }
        }
    }

    private func footer(more: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RoomTokens.Space.inner) {
                addButton.fixedSize()
                Spacer(minLength: 0)
                if more > 0 { moreButton(more).fixedSize() }
            }
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                addButton
                if more > 0 { moreButton(more) }
            }
        }
    }

    private var addButton: some View {
        Button(action: rooms.chooseFolder) {
            Label("Add a Room…", systemImage: "plus")
        }
        .roomLink(accent)
        .disabled(!rooms.canChooseFolder)
        .accessibilityIdentifier("RoomOverviewAddRoom")
    }

    private func moreButton(_ count: Int) -> some View {
        Button("\(count) more Rooms", action: showAll)
            .buttonStyle(RoomPressStyle())
            .font(RoomTokens.Typography.caption)
            .foregroundStyle(RoomTokens.Ink.secondary)
            .frame(minHeight: 24)
    }

    private func updateMeasuring() {
        rooms.setOverviewChapterActive(visible && scenePhase == .active)
    }
}

private struct RoomChapterRow: View {
    let room: RoomPinnedRoom
    let row: RoomRoomRow
    let open: () -> Void
    @Environment(\.roomHide) private var hide

    private var kind: RoomTokens.Kind {
        RoomTokens.Kind(rawValue: room.resolvedColour.rawValue) ?? .developer
    }
    private var help: String {
        row.isUnavailable ? "Choose this folder again to renew access." : "Open in Disk Map."
    }
    private var spoken: String {
        if hide.masksNow {
            return "Room, name hidden, size hidden. \(row.isUnavailable ? "Choose folder." : "Open in Disk Map.")"
        }
        return row.isUnavailable ? "\(row.name), needs access. Choose folder." : row.spoken
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: RoomTokens.Space.inner) {
                glyph
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RoomTokens.Space.group) {
                        details.frame(minWidth: 128, maxWidth: .infinity, alignment: .leading)
                        indicator
                        size
                    }
                    VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                        HStack(alignment: .top, spacing: RoomTokens.Space.row) {
                            details.frame(maxWidth: .infinity, alignment: .leading)
                            size
                        }
                        if row.budget != nil || !row.sparkline.isEmpty { indicator }
                    }
                }
            }
            .padding(RoomTokens.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: RoomTokens.Radius.row))
        }
        .buttonStyle(RoomHoverButtonStyle())
        .help(hide.masksNow ? help : row.name + " · " + help)
        .accessibilityLabel(spoken)
    }

    private var glyph: some View {
        Image(systemName: room.resolvedGlyph.rawValue)
            .font(RoomTokens.Typography.caption)
            .foregroundStyle(RoomTokens.Kind.tileInk)
            .frame(width: 28, height: 28)
            .background(kind.fill, in: .rect(cornerRadius: RoomTokens.Radius.row))
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            RoomMaskable(row.name, kind: .name)
                .font(RoomTokens.Typography.section)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if let emphasis = row.trendEmphasis {
                    RoomMaskable(emphasis).fontWeight(.semibold).fixedSize()
                }
                Text(row.trendRest)
            }
            .font(RoomTokens.Typography.caption)
            .foregroundStyle(RoomTokens.Ink.secondary)
            .lineLimit(2)
        }
    }

    private var size: some View {
        RoomMaskable(row.size)
            .font(RoomTokens.Typography.lead)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 76, alignment: .trailing)
            .roomNumericTransition(row.size)
    }

    private var indicator: some View {
        Group {
            if let budget = row.budget {
                RoomBudgetFrameView(layout: budget, color: kind.mark)
            } else {
                sparkline
            }
        }
        .frame(width: 72, height: 20)
        .accessibilityHidden(true)
    }

    private var sparkline: some View {
        Canvas { context, _ in
            var path = Path()
            for segment in row.sparkline {
                guard let first = segment.first else { continue }
                path.move(to: first)
                path.addLines(segment)
            }
            context.stroke(path, with: .color(kind.mark), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let end = row.sparkline.last?.last {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 2.3, y: end.y - 2.3, width: 4.6, height: 4.6)),
                             with: .color(RoomTokens.Surface.group))
                context.fill(Path(ellipseIn: CGRect(x: end.x - 1.5, y: end.y - 1.5, width: 3, height: 3)),
                             with: .color(kind.mark))
            }
        }
    }
}
