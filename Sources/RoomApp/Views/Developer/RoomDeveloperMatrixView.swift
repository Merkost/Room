import RoomCore
import SwiftUI

struct RoomDeveloperMatrixView: View {
    let summary: RoomDevSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("Project").fontWeight(.semibold)
                    ForEach(RoomDevMatrix.columns, id: \.self) { Text($0).fontWeight(.semibold) }
                }.accessibilityAddTraits(.isHeader)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(RoomDevMatrix.rows(summary).enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.title).lineLimit(2)
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                            Text(cell.text)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5).padding(.horizontal, 6)
                                .background(cell.shaded ? RoomTokens.Surface.press : .clear, in: .rect(cornerRadius: 4))
                                .help(cell.tooltip ?? "")
                                .accessibilityLabel("\(RoomDevMatrix.columns[index]), \(cell.text)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .font(.system(size: 12))
            Text("Shaded: shared by more than one room, counted once")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
