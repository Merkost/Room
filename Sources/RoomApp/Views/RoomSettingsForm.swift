import SwiftUI

/// The board's shared label column keeps every control on the same leading edge.
@MainActor
struct RoomSettingsFormRow<Content: View>: View {
    private let title: String
    private let hint: String?
    private let content: Content

    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 180, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                content
                if let hint {
                    Text(hint)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
