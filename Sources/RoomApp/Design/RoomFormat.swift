import SwiftUI

enum RoomFormat {
    static func overviewBytes(_ bytes: Int64) -> String {
        if bytes == 0 {
            return String(localized: "\(0.formatted(.number.grouping(.never))) GB")
        }
        return RoomMenuBarFormat.liveDisk(bytes)
    }

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
        guard let separator = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<separator]), String(text[text.index(after: separator)...]))
    }
}

enum RoomType {
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func figure(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
}

/// Each alternative keeps its unit and baseline together. Narrow windows choose
/// the next complete size rather than clipping a unit or compressing its glyphs.
struct RoomByteMetric: View {
    let bytes: Int64
    var maximumSize: CGFloat = 38
    var memory = false
    var animatesChanges = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metric(size: maximumSize).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.82).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.66).fixedSize(horizontal: true, vertical: false)
            metric(size: maximumSize * 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(size: CGFloat) -> some View {
        let amount = RoomFormat.splitBytes(bytes, memory: memory)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Group {
                if memory { Text(amount.value) } else { RoomMaskable(amount.value) }
            }
                .font(RoomType.figure(size))
                .tracking(size > 30 ? -0.5 : 0)
                .monospacedDigit()
                .roomNumericTransition(amount.value, enabled: animatesChanges)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(amount.unit)
                .font(RoomType.figure(max(14, size * 0.4)))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}
