import RoomCore
import SwiftUI

struct RoomDeveloperMatrixView: View {
    let summary: RoomDevSummary
    @Environment(\.roomHide) private var hide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("Project").fontWeight(.semibold)
                    ForEach(RoomDevMatrix.columns, id: \.self) { Text($0).fontWeight(.semibold) }
                }.accessibilityAddTraits(.isHeader)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(RoomDevMatrix.rows(summary).enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        if rowIndex == summary.rows.count {
                            Text(row.title).lineLimit(2)
                        } else {
                            RoomMaskable(row.title, kind: .name).lineLimit(2)
                        }
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                            RoomMaskable(cell.text, kind: index == 4 ? .name : .figure)
                                .font(RoomTokens.Typography.version)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5).padding(.horizontal, 6)
                                .background(cell.shaded ? RoomTokens.Surface.press : .clear, in: .rect(cornerRadius: RoomTokens.Radius.tile))
                                .help(cell.tooltip ?? "")
                                .accessibilityLabel("\(RoomDevMatrix.columns[index]), \(RoomHideSpeech.value(cell.text, hide: hide))")
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .font(RoomTokens.Typography.caption)
            Text("Shaded: shared by more than one room, counted once")
                .font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
        }
    }
}
