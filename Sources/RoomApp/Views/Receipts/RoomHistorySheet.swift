import RoomCore
import SwiftUI

struct RoomHistorySheet: View {
    let model: RoomViewModel
    @Environment(\.dismiss) private var dismiss
    #if ROOM_APP_STORE
    @State private var review: RoomActivity?
    #endif

    private var days: [(date: Date, receipts: [RoomActivity])] {
        Dictionary(grouping: model.activity) { Calendar.current.startOfDay(for: $0.date) }
            .map { (date: $0.key, receipts: $0.value) }.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
            Text("History").font(RoomTokens.Typography.figure).accessibilityHeading(.h1)
            if let header = model.makeRoomStore?.summary.header(format: RoomFormat.overviewBytes,
                month: { $0.formatted(.dateTime.month(.wide).year()) }) {
                Text(header).font(RoomTokens.Typography.lead).fixedSize(horizontal: false, vertical: true)
            } else if model.activity.isEmpty {
                Text("Nothing moved yet. Anything you move goes to Trash first, with a receipt.")
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    ForEach(days, id: \.date) { day in
                        Text(Calendar.current.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            .font(RoomTokens.Typography.section).accessibilityHeading(.h2)
                        ForEach(day.receipts) { receipt in
                            let entry = model.makeRoomStore?.entry(for: receipt.id)
                            RoomReceiptView(receipt: receipt, entry: entry,
                                restore: model.isScanning || model.isWorking ? nil : { restore(receipt) })
                            details(receipt)
                        }
                    }
                }
            }
            .frame(maxHeight: 430)
            HStack {
                Button("Open Trash", action: model.openTrash).roomSecondary()
                Spacer()
                Button("Done") { dismiss() }.roomSecondary().keyboardShortcut(.cancelAction)
            }
        }
        .padding(RoomTokens.Space.breath1)
        .frame(width: 560)
        .task { await model.refreshHistory() }
        #if ROOM_APP_STORE
        .sheet(item: $review) { receipt in RoomStoreRestoreSheet(model: model, record: receipt) }
        #endif
    }

    private func details(_ receipt: RoomActivity) -> some View {
        DisclosureGroup("Item details") {
            ForEach(receipt.details) { item in
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Text(item.name).font(RoomTokens.Typography.section)
                    Text(item.message)
                    Text(item.path).font(RoomTokens.Typography.caption.monospaced()).textSelection(.enabled)
                }
                .foregroundStyle(RoomTokens.Ink.secondary)
                .padding(.vertical, RoomTokens.Space.tight)
            }
        }
        .font(RoomTokens.Typography.caption)
    }

    private func restore(_ receipt: RoomActivity) {
        #if ROOM_APP_STORE
        review = receipt
        #else
        Task { await model.restore(record: receipt) }
        #endif
    }
}
