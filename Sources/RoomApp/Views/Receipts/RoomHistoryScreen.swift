import SwiftUI

/// History's numbers, kept pure for tests: bytes made this month, receipts by month, how many can still come back.
nonisolated struct RoomHistoryPresentation: Equatable, Sendable {
    struct Month: Equatable, Sendable {
        let start: Date
        let receiptIDs: [UUID]
    }

    let madeThisMonth: Int64
    let receipts: Int
    let restorable: Int
    let months: [Month]

    static func make(_ activity: [(id: UUID, date: Date, bytes: Int64, canRestore: Bool, restoredAll: Bool)],
                     now: Date, calendar: Calendar = .current) -> RoomHistoryPresentation {
        let thisMonth = calendar.dateInterval(of: .month, for: now)
        let made = activity.filter { thisMonth?.contains($0.date) == true && !$0.restoredAll }.reduce(Int64(0)) { $0 + $1.bytes }
        let grouped = Dictionary(grouping: activity) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        let months = grouped.keys.sorted(by: >).map { start in
            Month(start: start, receiptIDs: grouped[start]!.sorted { $0.date > $1.date }.map(\.id))
        }
        return RoomHistoryPresentation(madeThisMonth: made, receipts: activity.count,
                                       restorable: activity.filter(\.canRestore).count, months: months)
    }

    var headline: RoomHeadline {
        receipts == 0
            ? .words(String(localized: "history.empty.headline", defaultValue: "Nothing moved yet", bundle: RoomCopy.bundle))
            : RoomHeadline(figure: RoomFormat.gb(madeThisMonth),
                           words: String(localized: "history.headline.words", defaultValue: "made this month", bundle: RoomCopy.bundle))
    }

    var supporting: String {
        if receipts == 0 { return "Anything Room moves goes to Trash first, with a receipt here." }
        let noun = receipts == 1 ? "1 receipt" : "\(receipts) receipts"
        if restorable == receipts { return receipts == 1 ? "\(noun), still in Trash" : "\(noun), all still in Trash" }
        if restorable == 0 { return "\(noun), none left to restore" }
        return "\(noun), \(restorable) still in Trash"
    }
}

/// History (nav-v3): "28 GB made this month", receipts by month, Restore per receipt, Open Trash. No filled button.
struct RoomHistoryScreen: View {
    let model: RoomViewModel
    let restore: (RoomActivity) -> Void
    /// Folder receipts from the Disk Map (Direct), shown beside cache receipts.
    var extraActivity: [RoomActivity] = []

    private var activity: [RoomActivity] { (model.activity + extraActivity).sorted { $0.date > $1.date } }
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide

    private var presentation: RoomHistoryPresentation {
        RoomHistoryPresentation.make(activity.map {
            (id: $0.id, date: $0.date, bytes: $0.bytes, canRestore: $0.canRestore,
             restoredAll: $0.itemCount > 0 && $0.restoredCount >= $0.itemCount)
        }, now: Date())
    }

    var body: some View {
        let presentation = presentation
        RoomScreenFrame(headline: presentation.headline, supporting: presentation.supporting,
                        note: presentation.receipts == 0 ? nil : "Restore puts everything back where it was",
                        scrollsEvidence: true, entersEvidence: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(presentation.months, id: \.start) { month in
                    RoomGroupLabel(text: month.start.formatted(.dateTime.month(.wide)))
                    ForEach(month.receiptIDs, id: \.self) { id in
                        if let receipt = activity.first(where: { $0.id == id }) {
                            row(receipt).roomEnter(2 + (activity.firstIndex { $0.id == id } ?? 0))
                        }
                    }
                }
                if presentation.receipts > 0 {
                    HStack(spacing: RoomTokens.Space.row) {
                        Text("In Trash until you empty it.").foregroundStyle(RoomTokens.Ink.secondary)
                        Button("Open Trash", action: model.openTrash).roomLink(accent)
                    }
                    .font(RoomTokens.Typography.body)
                    .padding(.top, RoomTokens.Space.row)
                }
            }
        } action: {
            EmptyView()
        }
        .task { await model.refreshHistory() }
    }

    /// Mockup `.li .lnk`: Restore waits at the end of the row and shows on hover or keyboard focus (VoiceOver always
    /// reaches it); a receipt that cannot come back says why in the quiet ink.
    private func row(_ receipt: RoomActivity) -> some View {
        RoomHoverReveal { revealed in
            RoomEvidenceRow(name: receipt.title, meta: Self.when(receipt.date), bytes: receipt.bytes, masksName: false) {
                RoomQuietTile(glyph: receipt.details.first?.source == "diskMap" ? .diskMap : .box)
            } trailing: {
                Group {
                    if receipt.canRestore {
                        Button("Restore") { restore(receipt) }
                            .roomLink(accent)
                            .disabled(model.isScanning || model.isWorking)
                            .opacity(revealed ? 1 : 0)
                            .accessibilityLabel(hide.masksNow ? "Restore receipt" : "Restore \(receipt.title)")
                    } else {
                        Text(receipt.restoredCount > 0 ? "Restored" : "In Trash").foregroundStyle(RoomTokens.Ink.tertiary)
                    }
                }
                .font(RoomTokens.Typography.bodyStrong)
                .frame(minWidth: 64, alignment: .trailing)
            }
        }
    }

    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide))
    }
}
