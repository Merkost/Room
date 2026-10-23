import SwiftUI

enum RoomFormat {
    static func bytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func memoryBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    static func splitBytes(_ bytes: Int64, memory: Bool = false) -> (value: String, unit: String) {
        let text = memory ? self.memoryBytes(bytes) : self.bytes(bytes)
        guard let separator = text.lastIndex(where: { $0.isWhitespace }) else { return (text, "") }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }
}

/// Each alternative keeps its unit and baseline together. Narrow windows choose
/// the next complete size rather than clipping a unit or compressing its glyphs.
struct RoomByteMetric: View {
    let bytes: Int64
    var maximumSize: CGFloat = 38
    var memory = false
    var valueColor: Color = .primary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metric(size: maximumSize).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.82).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.66).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(memory ? RoomFormat.memoryBytes(bytes) : RoomFormat.bytes(bytes))
    }

    private func metric(size: CGFloat) -> some View {
        let amount = RoomFormat.splitBytes(bytes, memory: memory)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(amount.value)
                .foregroundStyle(valueColor)
                .font(RoomType.figure(size))
                .tracking(size > 30 ? -0.5 : 0)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(amount.unit)
                .font(RoomType.figure(max(11, size * 0.4)))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

/// A measured amount and its meaning travel together. Optional values stay
/// explicitly unmeasured; lower bounds remain visible and spoken.
struct RoomMetric: View {
    let label: String
    let bytes: Int64?
    var memory = false
    var maximumSize: CGFloat = 38
    var lowerBound = false
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.small) {
            Text(label).font(RoomTypography.caption).foregroundStyle(.secondary)
            if let bytes {
                HStack(alignment: .firstTextBaseline, spacing: RoomSpace.micro) {
                    if lowerBound {
                        Text("≥")
                            .font(RoomType.figure(maximumSize * 0.65))
                            .foregroundStyle(.secondary)
                    }
                    RoomByteMetric(bytes: bytes, maximumSize: maximumSize, memory: memory, valueColor: valueColor)
                }
            } else {
                Text("Not measured")
                    .font(RoomTypography.bodyEmphasis)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let bytes else { return "\(label): not measured" }
        let value = memory ? RoomFormat.memoryBytes(bytes) : RoomFormat.bytes(bytes)
        return "\(label): \(lowerBound ? "at least " : "")\(value)"
    }
}
