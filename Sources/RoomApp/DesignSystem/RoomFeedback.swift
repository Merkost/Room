import SwiftUI

enum RoomNoticeTone {
    case neutral, information, success, warning, error

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .information: .accentColor
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    var symbol: String {
        switch self {
        case .neutral, .information: "info.circle"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.circle"
        }
    }
}

/// Status keeps its meaning in its symbol and words, independent of hue.
/// It intentionally has no card or glass, so it can live beside the affected task.
struct RoomStatusNotice: View {
    let title: String?
    let message: String
    let systemImage: String?
    let tone: RoomNoticeTone

    init(title: String? = nil, message: String, systemImage: String? = nil,
         tone: RoomNoticeTone = .neutral) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: RoomSpace.small) {
            Image(systemName: systemImage ?? tone.symbol)
                .font(.system(size: 14))
                .foregroundStyle(tone.color)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoomSpace.micro) {
                if let title, !title.isEmpty {
                    Text(title).font(RoomTypography.bodyEmphasis)
                }
                if !message.isEmpty {
                    Text(message)
                        .font(RoomTypography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RoomEmptyState<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    private let actions: Actions

    init(title: String, message: String, systemImage: String,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: RoomSpace.standard) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: RoomSpace.small) {
                Text(title)
                    .font(RoomTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(RoomTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            actions.controlSize(.regular)
        }
        .padding(RoomSpace.section)
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

extension RoomEmptyState where Actions == EmptyView {
    init(title: String, message: String, systemImage: String) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}
