import SwiftUI

struct RoomChapterRooms: View {
    let rooms: RoomRoomsModel
    let calendar: Calendar
    let editing: UUID?
    let openRoom: (URL) -> Void
    let showAll: () -> Void
    @AppStorage("RoomHideSizes") private var hidden = false
    @Environment(\.roomAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    var body: some View {
        let shown = RoomRoomsChapter.shown(rooms.rooms, editing: editing)
        let unavailable = rooms.unavailable
        let now = Date()
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Your Rooms").font(RoomTokens.Typography.title).accessibilityAddTraits(.isHeader)
                Text("folders you pinned · 12 weeks").font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            }
            if shown.rows.isEmpty {
                Text("Pin a folder to watch it here.").font(RoomTokens.Typography.body).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(shown.rows) { room in
                        roomRow(room, now: now, unavailable: unavailable.contains(room.id))
                    }
                }.padding(.top, 10)
            }
            HStack(spacing: 12) {
                Button("Add a Room…", action: rooms.chooseFolder)
                    .roomLink(accent).disabled(!rooms.canChooseFolder)
                if shown.more > 0 {
                    Button("\(shown.more) more Rooms", action: showAll)
                        .buttonStyle(.plain).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
                }
            }
            if let notice = rooms.notice {
                Text(notice).font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0; updateMeasuring() }
        .onChange(of: scenePhase) { _, _ in updateMeasuring() }
        .onDisappear { rooms.setOverviewChapterActive(false) }
    }

    private func updateMeasuring() {
        rooms.setOverviewChapterActive(visible && scenePhase == .active)
    }

    private func roomRow(_ room: RoomPinnedRoom, now: Date, unavailable: Bool) -> some View {
        let row = RoomRoomsChapter.row(room, log: rooms.log(for: room.id), unavailable: unavailable,
                                       now: now, calendar: calendar, hidden: hidden, format: RoomFormat.bytes)
        let kind = RoomTokens.Kind(rawValue: room.resolvedColour.rawValue) ?? .developer
        let help = unavailable ? "Choose this folder again to renew access." : "Opens Disk Map and measures this folder."
        return Button {
            if !unavailable, let url = rooms.url(for: room.id) { openRoom(url) }
            else { rooms.chooseFolder(replacingApprovalFor: room.id) }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: room.resolvedGlyph.rawValue)
                    .font(RoomTokens.Typography.roomGlyph).foregroundStyle(RoomTokens.Kind.tileInk)
                    .frame(width: 20, height: 20).background(kind.fill, in: .rect(cornerRadius: RoomTokens.Radius.field))
                    .frame(width: 22)
                Text(row.name).font(RoomTokens.Typography.bodyStrong).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let budget = row.budget {
                        RoomBudgetFrameView(layout: budget, color: kind.mark)
                    } else {
                        sparkline(row.sparkline, color: kind.mark)
                    }
                }.frame(width: 72, height: 20)
                Text(row.size).font(RoomTokens.Typography.lead).monospacedDigit().lineLimit(1)
                    .frame(width: 76, alignment: .trailing)
                (Text(row.trendEmphasis ?? "").fontWeight(.semibold) + Text(row.trendRest))
                    .font(RoomTokens.Typography.caption).foregroundStyle(.secondary).lineLimit(2)
                    .frame(width: 124, alignment: .leading)
            }
            .frame(height: 36).padding(.horizontal, 8).contentShape(.rect(cornerRadius: RoomTokens.Radius.row))
        }
        .buttonStyle(RoomChapterRowButtonStyle())
        .help(hidden ? help : row.name + " · " + help)
        .accessibilityLabel(unavailable && !hidden ? "\(row.name), needs access. Choose folder." : row.spoken)
    }

    private func sparkline(_ segments: [[CGPoint]], color: Color) -> some View {
        Canvas { context, _ in
            var path = Path()
            for segment in segments {
                guard let first = segment.first else { continue }
                path.move(to: first)
                path.addLines(segment)
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let end = segments.last?.last {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 2.3, y: end.y - 2.3, width: 4.6, height: 4.6)),
                             with: .color(RoomTokens.Surface.canvas))
                context.fill(Path(ellipseIn: CGRect(x: end.x - 1.5, y: end.y - 1.5, width: 3, height: 3)), with: .color(color))
            }
        }.accessibilityHidden(true)
    }
}

private struct RoomChapterRowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering || configuration.isPressed ? RoomTokens.Surface.hover : .clear, in: .rect(cornerRadius: RoomTokens.Radius.row))
            .onHover { hovering = $0 }
    }
}
