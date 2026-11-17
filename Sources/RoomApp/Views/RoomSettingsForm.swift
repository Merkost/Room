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

/// The board's `tgl` + label: the switch first, then its words (a long label wraps beside the switch, never before it).
@MainActor
struct RoomSettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden()
                .fixedSize()
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { isOn.toggle() }
                .accessibilityHidden(true)
        }
    }
}
