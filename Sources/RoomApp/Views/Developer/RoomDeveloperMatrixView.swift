import RoomCore
import SwiftUI

struct RoomDeveloperMatrixView: View {
    let summary: RoomDevSummary
    @Environment(\.roomHide) private var hide
    @State private var selected: CellID?

    private struct CellID: Hashable {
        let row: Int
        let column: Int
    }

    var body: some View {
        RoomDeveloperGroup(title: "Toolchain versions") {
            ScrollView(.horizontal) {
                matrix
            }
            HStack(spacing: RoomTokens.Space.tight) {
                RoundedRectangle(cornerRadius: RoomTokens.Radius.tile)
                    .fill(RoomTokens.Surface.press)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text("Shared by more than one project. Counted once.")
                    .font(RoomTokens.Typography.caption)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }

    private var matrix: some View {
        Grid(alignment: .leading, horizontalSpacing: RoomTokens.Space.row, verticalSpacing: RoomTokens.Space.tight) {
            GridRow {
                Text("Project").frame(minWidth: 112, alignment: .leading)
                ForEach(RoomDevMatrix.columns, id: \.self) { name in
                    Text(name).frame(minWidth: 60, alignment: .leading)
                }
            }
            .font(RoomTokens.Typography.section)
            .accessibilityAddTraits(.isHeader)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(RoomDevMatrix.rows(summary).enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    if rowIndex == summary.rows.count {
                        Text(row.title).font(RoomTokens.Typography.bodyStrong).lineLimit(2)
                    } else {
                        RoomMaskable(row.title, kind: .name).lineLimit(2)
                    }
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { column, cell in
                        matrixCell(cell, at: CellID(row: rowIndex, column: column))
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
        .font(RoomTokens.Typography.caption)
    }

    @ViewBuilder private func matrixCell(_ cell: RoomDevMatrixCell, at id: CellID) -> some View {
        let column = RoomDevMatrix.columns[id.column]
        let kind: RoomMaskKind = id.column == 4 ? .name : .figure
        if cell.text == "—" {
            Text("—")
                .foregroundStyle(RoomTokens.Ink.secondary)
                .padding(RoomTokens.Space.tight)
                .accessibilityLabel("\(column), no version recorded")
        } else {
            Button {
                selected = id
            } label: {
                RoomMaskable(cell.text, kind: kind)
                    .font(RoomTokens.Typography.version)
                    .padding(RoomTokens.Space.tight)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RoomHoverButtonStyle(cornerRadius: RoomTokens.Radius.tile, isActive: selected == id))
            .background(cell.shaded ? RoomTokens.Surface.press : .clear, in: .rect(cornerRadius: RoomTokens.Radius.tile))
            .help(cell.tooltip ?? "View version details")
            .accessibilityLabel("\(column), \(RoomHideSpeech.value(cell.text, hide: hide))" + (cell.shaded ? ", shared" : ""))
            .popover(isPresented: Binding(get: { selected == id }, set: { if !$0 { selected = nil } })) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
                    Text(column).font(RoomTokens.Typography.section)
                    RoomMaskable(cell.text, kind: kind).font(RoomTokens.Typography.version)
                    if let detail = cell.tooltip { Text(detail) }
                    if cell.shaded { Text("Shared by more than one project.") }
                }
                .font(RoomTokens.Typography.caption)
                .padding(RoomTokens.Space.group)
            }
        }
    }
}
