import AppKit
import RoomCore
import SwiftUI

extension RoomDeveloperHeadline.Kind {
    var title: String {
        switch self {
        case .inUse: "In use by your projects"
        case .unreferenced: "Not in any room"
        case .devices: "Virtual devices"
        case .toolStorage: "Tool storage"
        case .aiTools: "AI tools"
        }
    }
}

/// Rows appear in order as results arrive. Reduce Motion keeps the fade and drops the stagger.
private struct RoomDeveloperArrival: ViewModifier {
    let index: Int
    @Environment(\.roomMotion) private var motion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .task {
                let delay = motion.isFull ? RoomDeveloperList.staggerDelay(index: index) : 0
                withAnimation(motion.animation(RoomTokens.Motion.fade)?.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func roomDeveloperArrival(index: Int) -> some View { modifier(RoomDeveloperArrival(index: index)) }
}

/// A titled surface: one heading, an optional quiet caption, then its rows.
struct RoomDeveloperGroup<Content: View, Trailing: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.row) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
                    Text(title)
                        .font(RoomTokens.Typography.title)
                        .accessibilityHeading(.h2)
                    if let caption {
                        Text(caption)
                            .font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                }
                Spacer(minLength: 0)
                trailing
            }
            content
        }
        .padding(RoomTokens.Space.group)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.group))
    }
}

extension RoomDeveloperGroup where Trailing == EmptyView {
    init(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, caption: caption, trailing: { EmptyView() }, content: content)
    }
}

/// One row, everywhere: name, quiet location, size right-aligned in whole units, one action.
struct RoomDeveloperRow: View {
    let title: String
    var masksTitle = true
    var titleKind: RoomMaskKind = .name
    var subtitle: String?
    var subtitleKind: RoomMaskKind = .name
    var note: String?
    var bytes: Int64?
    var partial = false
    var finderURL: URL?
    var help: String?
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion
    @State private var hovering = false

    private var sizeText: String { bytes.map { RoomDeveloperFormat.whole($0, partial: partial) } ?? "—" }

    var body: some View {
        HStack(spacing: RoomTokens.Space.inner) {
            VStack(alignment: .leading, spacing: RoomTokens.Space.tight / 2) {
                Group {
                    if masksTitle { RoomMaskable(title, kind: titleKind) } else { Text(title) }
                }
                .font(RoomTokens.Typography.section)
                .lineLimit(1)
                .truncationMode(.middle)
                if let subtitle {
                    RoomMaskable(subtitle, kind: subtitleKind)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let note {
                    Text(note)
                        .font(RoomTokens.Typography.caption)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: RoomTokens.Space.inner)
            RoomMaskable(sizeText)
                .font(RoomTokens.Typography.numeric)
                .fixedSize()
                .help(partial ? "Measured size is a lower bound" : "Space on disk")
            actionSlot
        }
        .padding(.horizontal, RoomTokens.Space.inner)
        .padding(.vertical, RoomTokens.Space.row)
        .frame(minHeight: RoomTokens.Developer.rowMinHeight)
        .background(RoomTokens.Surface.hover.opacity(hovering ? 1 : 0), in: .rect(cornerRadius: RoomTokens.Radius.row))
        .animation(motion.animation(RoomTokens.Motion.quick, fallback: nil), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .help(help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .modifier(RoomDeveloperFinderAction(url: hide.masksNow ? nil : finderURL))
    }

    @ViewBuilder private var actionSlot: some View {
        if let finderURL, !hide.masksNow {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([finderURL])
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .frame(width: RoomTokens.Developer.actionSize, height: RoomTokens.Developer.actionSize)
            }
            .buttonStyle(RoomHoverButtonStyle())
            .help("Show in Finder. Room only reveals it; nothing is moved.")
            .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: RoomTokens.Developer.actionSize, height: RoomTokens.Developer.actionSize)
        }
    }

    private var spoken: String {
        let name = hide.masksNow && masksTitle && titleKind == .name ? "Hidden" : title
        let size = hide.masksNow ? "size hidden" : (partial ? "at least " : "") + sizeText
        return [name, subtitle.flatMap { hide.masksNow ? nil : $0 }, size].compactMap { $0 }.joined(separator: ", ")
    }
}

private struct RoomDeveloperFinderAction: ViewModifier {
    let url: URL?
    func body(content: Content) -> some View {
        if let url {
            content.accessibilityAction(named: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } else {
            content
        }
    }
}

/// A list that shows the first rows and says how many more there are.
struct RoomDeveloperRowList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var limit = RoomDeveloperList.collapsedLimit
    @ViewBuilder var row: (Item) -> Row
    @State private var expanded = false
    @Environment(\.roomAccent) private var accent

    var body: some View {
        let split = RoomDeveloperList.visible(items, expanded: expanded, limit: limit)
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight / 2) {
            ForEach(Array(split.shown.enumerated()), id: \.element.id) { index, item in
                row(item).roomDeveloperArrival(index: index)
            }
            if split.hidden > 0 {
                Button("Show \(split.hidden.formatted()) more") { expanded = true }
                    .roomLink(accent)
                    .padding(.horizontal, RoomTokens.Space.inner)
            } else if expanded && items.count > limit + 1 {
                Button("Show fewer") { expanded = false }
                    .roomLink(accent)
                    .padding(.horizontal, RoomTokens.Space.inner)
            }
        }
    }
}

/// The summary header: one hero figure, a thin breakdown bar in the Developer colour, and its legend.
struct RoomDeveloperHeader<Actions: View>: View {
    let headline: RoomDeveloperHeadline
    @ViewBuilder var actions: Actions
    @Environment(\.roomHide) private var hide

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: RoomTokens.Space.group) {
                    hero
                    Spacer(minLength: 0)
                    actions.fixedSize()
                }
                VStack(alignment: .leading, spacing: RoomTokens.Space.inner) {
                    hero
                    actions
                }
            }
            if !headline.isEmpty {
                RoomDeveloperBreakdown(headline: headline)
            }
        }
    }

    private var hero: some View {
        let amount = RoomFormat.splitBytes(headline.total)
        return VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            Text("Developer storage found")
                .font(RoomTokens.Typography.caption)
                .foregroundStyle(RoomTokens.Ink.secondary)
            HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.tight) {
                if headline.partial {
                    Text("≥").font(RoomTokens.Typography.figure).foregroundStyle(RoomTokens.Ink.secondary)
                }
                RoomMaskable(amount.value)
                    .font(RoomTokens.Typography.hero)
                    .tracking(RoomTokens.Typography.heroTracking)
                    .roomNumericTransition(headline.total)
                RoomMaskable(amount.unit)
                    .font(RoomTokens.Typography.unit(for: 40))
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hide.masksNow ? "Developer storage, hidden"
                : "Developer storage found, \(headline.partial ? "at least " : "")\(RoomFormat.bytes(headline.total))")
            .accessibilityAddTraits(.isHeader)
            if headline.unreferenced > 0 {
                RoomMaskable("\(RoomDeveloperFormat.whole(headline.unreferenced, partial: headline.partial)) is not referenced by the projects you chose.",
                             kind: .figure)
                    .font(RoomTokens.Typography.body)
                    .foregroundStyle(RoomTokens.Ink.secondary)
            }
        }
    }
}

struct RoomDeveloperBreakdown: View {
    let headline: RoomDeveloperHeadline
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion

    private func tone(_ index: Int) -> Color {
        let steps = RoomTokens.Developer.breakdownSteps
        return RoomTokens.Kind.developer.mark.opacity(steps[min(index, steps.count - 1)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.row) {
            let fractions = headline.fractions()
            let sum = max(0.0001, fractions.reduce(0, +))
            GeometryReader { geometry in
                HStack(spacing: RoomTokens.Developer.breakdownGap) {
                    ForEach(Array(headline.parts.enumerated()), id: \.element.id) { index, _ in
                        Capsule().fill(tone(index))
                            .frame(width: max(2, geometry.size.width * fractions[index] / sum))
                    }
                }
                .animation(motion.animation(RoomTokens.Motion.standard), value: headline.parts)
            }
            .frame(height: RoomTokens.Developer.breakdownHeight)
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)],
                      alignment: .leading, spacing: RoomTokens.Space.tight) {
                ForEach(Array(headline.parts.enumerated()), id: \.element.id) { index, part in
                    HStack(spacing: RoomTokens.Space.tight) {
                        Circle().fill(tone(index))
                            .frame(width: RoomTokens.OverviewPlan.swatchSize, height: RoomTokens.OverviewPlan.swatchSize)
                            .accessibilityHidden(true)
                        Text(part.kind.title)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                        RoomMaskable(RoomDeveloperFormat.whole(part.bytes, partial: headline.partial))
                            .font(RoomTokens.Typography.captionNumeric)
                    }
                    .font(RoomTokens.Typography.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(hide.masksNow ? "\(part.kind.title), hidden"
                        : "\(part.kind.title), \(headline.partial ? "at least " : "")\(RoomFormat.bytes(part.bytes))")
                }
            }
        }
    }
}
