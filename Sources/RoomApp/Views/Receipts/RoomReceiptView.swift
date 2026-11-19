import RoomCore
import SwiftUI

struct RoomReceiptView: View {
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    let receipt: RoomActivity
    let entry: RoomMakeRoomEntry?
    let restore: (() -> Void)?

    private var lines: [(source: String, bytes: Int64)] {
        Dictionary(grouping: receipt.details.filter { $0.canRestore || $0.isRestored }, by: { $0.source ?? $0.name })
            .map { (source: $0.key, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            HStack {
                Label("Receipt", systemImage: receipt.canRestore ? "trash" : "checkmark.circle")
                    .font(RoomTokens.Typography.section)
                Spacer()
                Text(receipt.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute()))
            }
            ForEach(lines, id: \.source) { line in
                dottedLine(line.source, bytes: line.bytes)
            }
            Divider()
            dottedLine(totalLabel, bytes: observedGain > 0 ? observedGain : receipt.bytes)
                .font(RoomTokens.Typography.section)
            HStack {
                if let word = RoomMakeRoomCopy.footerWord(entry, receiptCanRestore: receipt.canRestore) {
                    Text(word)
                } else {
                    let count = receipt.details.filter(\.canRestore).count
                    Text(hidden ? "Items in Trash" : "\(count) \(count == 1 ? "item" : "items") in Trash")
                    if let restore { Button("Restore", action: restore).buttonStyle(.glass) }
                }
            }
            .foregroundStyle(RoomTokens.Ink.secondary)
        }
        .font(RoomTokens.Typography.caption)
        .padding(RoomTokens.Space.group)
        .background(RoomTokens.Surface.group, in: RoundedRectangle(cornerRadius: RoomTokens.Radius.group))
    }

    private var observedGain: Int64 {
        guard let entry, entry.stage == .emptied || entry.stage == .partlyEmptied else { return 0 }
        return entry.observedGain
    }

    private var totalLabel: String {
        observedGain > 0 ? "Made room" : receipt.bytes > 0 ? "Moved to Trash" : "Nothing moved"
    }

    private func dottedLine(_ name: String, bytes: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.row) {
            Text(name).fixedSize(horizontal: false, vertical: true)
            Canvas { context, size in
                let path = Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: size.width, y: 0)) }
                context.stroke(path, with: .color(RoomTokens.Surface.line2), style: .init(lineWidth: 1.5, dash: [1, 3]))
            }
            .frame(height: 2)
            .accessibilityHidden(true)
            Text(RoomCachesVisibility.bytes(bytes, hidden: hidden)).monospacedDigit().fixedSize()
                .accessibilityLabel(hidden ? "Size hidden" : RoomFormat.overviewBytes(bytes))
        }
        .accessibilityElement(children: .combine)
    }
}
