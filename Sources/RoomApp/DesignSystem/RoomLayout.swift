import SwiftUI

/// A complete identity/action row switches to two rows before either is clipped.
/// Actions remain native buttons and menus supplied by the working screen.
struct RoomPageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    private let actions: Actions

    init(title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: RoomSpace.section) {
                identity.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: RoomSpace.compact)
                actions.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: RoomSpace.standard) {
                identity
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(RoomTypography.pageTitle)
                .tracking(-0.35)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(RoomTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension RoomPageHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct RoomSectionHeader<Actions: View>: View {
    let title: String
    let detail: String?
    private let actions: Actions

    init(title: String, detail: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: RoomSpace.compact) {
                identity.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: RoomSpace.compact)
                actions.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: RoomSpace.compact) {
                identity
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identity: some View {
        HStack(alignment: .firstTextBaseline, spacing: RoomSpace.small) {
            Text(title)
                .font(RoomTypography.sectionTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(RoomTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension RoomSectionHeader where Actions == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

/// Use for one related working group, not as an enclosure around each statistic.
/// Opaque system colors also satisfy Reduce Transparency without another layer.
struct RoomContentGroup<Content: View>: View {
    let inset: CGFloat
    let spacing: CGFloat
    private let content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    init(inset: CGFloat = RoomSpace.standard, spacing: CGFloat = RoomSpace.standard,
         @ViewBuilder content: () -> Content) {
        self.inset = inset
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .background(RoomSurface.group, in: RoundedRectangle(cornerRadius: RoomRadius.group, style: .continuous))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: RoomRadius.group, style: .continuous)
                        .strokeBorder(RoomSurface.separator, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Paths stay selectable and expose the complete value to assistive technology,
/// even when the visible row needs middle truncation.
struct RoomPathLabel: View {
    let path: String
    let label: String?
    let lineLimit: Int

    init(path: String, label: String? = nil, lineLimit: Int = 2) {
        self.path = path
        self.label = label
        self.lineLimit = lineLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.micro) {
            if let label, !label.isEmpty {
                Text(label).font(RoomTypography.captionEmphasis).foregroundStyle(.secondary)
            }
            Text(path)
                .font(RoomTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { "\($0): \(path)" } ?? path)
    }
}

/// Persistent heading and action footer frame the scrollable task. Mutation
/// ownership, cancel/default shortcuts, and dismissal rules stay with callers.
struct RoomSheetLayout<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    let width: CGFloat
    let maxContentHeight: CGFloat
    let feedback: String?
    private let content: Content
    private let actions: Actions

    init(title: String, subtitle: String, width: CGFloat = 580,
         maxContentHeight: CGFloat = 360,
         feedback: String? = nil,
         @ViewBuilder content: () -> Content,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.maxContentHeight = maxContentHeight
        self.feedback = feedback
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.section) {
            RoomSheetHeading(title: title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: RoomSpace.standard) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, RoomSpace.micro)
            }
            // Reserve footer space so an error cannot push the recovery
            // actions outside a window at the minimum supported height.
            .frame(maxHeight: max(0, maxContentHeight - (hasFeedback ? 96 : 0)))
            .scrollIndicators(.visible)
            VStack(alignment: .leading, spacing: RoomSpace.compact) {
                if let feedback, !feedback.isEmpty {
                    RoomStatusNotice(message: feedback, tone: .error)
                        .lineLimit(4)
                        .help(feedback)
                        .accessibilityLabel(feedback)
                        .accessibilityIdentifier("RoomSheetFeedback")
                }
                HStack(spacing: RoomSpace.compact) { actions }
                    .controlSize(.large)
            }
        }
        .padding(RoomSpace.page)
        .frame(width: width)
    }

    private var hasFeedback: Bool { feedback?.isEmpty == false }
}

struct RoomSheetHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: RoomSpace.small) {
            Text(title)
                .font(RoomTypography.pageTitle)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .help(title)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(RoomTypography.body)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .help(subtitle)
                .accessibilityLabel(subtitle)
        }
    }
}
