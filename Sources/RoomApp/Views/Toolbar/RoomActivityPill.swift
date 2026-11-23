import Accessibility
import SwiftUI

struct RoomActivityPill: View {
    private static let markSize: CGFloat = 14
    private static let height: CGFloat = 28
    var stop: (RoomActivityPillState.Tool) -> Void = { _ in }
    var restore: (UUID) -> Void = { _ in }
    var showHistory: () -> Void = {}
    var prefersQuietIdleLabel = false

    @Environment(\.roomActivityCenter) private var center
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    @State private var expanded = false
    @State private var hovered = false

    private enum Mark: Hashable {
        case idle, scanning, needsAccess, made

        init(_ state: RoomActivityPillState) {
            switch state {
            case .scanning: self = .scanning
            case .needsAccess: self = .needsAccess
            case .made: self = .made
            default: self = .idle
            }
        }
    }

    var body: some View {
        if let center {
            let state = center.visible
            let appearance = Mark(state)
            let text = toolbarLabel(state)
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: RoomTokens.Space.row) {
                    mark(appearance)
                        .roomPanelArrival()
                        .id(appearance)
                        .frame(width: Self.markSize, height: Self.markSize)
                    RoomChangingLabel(value: text, animates: !hidden) {
                        Text(text).font(RoomTokens.Typography.caption.monospacedDigit())
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 200)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: Self.height)
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Capsule())
            }
            .buttonStyle(RoomHoverButtonStyle(cornerRadius: Self.height / 2, isActive: expanded))
            .background(RoomTokens.Surface.group, in: Capsule())
            .overlay { Capsule().strokeBorder(RoomTokens.Surface.line2).allowsHitTesting(false) }
            .accessibilityLabel(spoken(state))
            .accessibilityHint("Shows activity details")
            .onHover { inside in
                hovered = inside
                center.pause(inside || expanded)
            }
            .onChange(of: expanded) { _, open in center.pause(open || hovered) }
            .onChange(of: state) { previous, next in
                if case .scanning = previous, case .scanning = next { return }
                guard next.priority > 0 else { return }
                AccessibilityNotification.Announcement(spoken(next)).post()
            }
            .onDisappear { center.pause(false) }
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: RoomTokens.Space.group) {
                    Text("Activity").font(RoomTokens.Typography.section).accessibilityHeading(.h2)
                    if center.expansion.isEmpty {
                        Text(label(state)).accessibilityLabel(spoken(state))
                    } else {
                        ForEach(Array(center.expansion.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(label(item)).accessibilityLabel(spoken(item))
                                Spacer()
                                action(item)
                            }
                        }
                    }
                    Button("Show History") { expanded = false; showHistory() }
                        .buttonStyle(.plain)
                    Button("Close") { expanded = false }
                        .keyboardShortcut(.cancelAction)
                }
                .font(RoomTokens.Typography.caption)
                .frame(minWidth: 240)
                .padding(RoomTokens.Space.group)
            }
        }
    }

    @ViewBuilder
    private func mark(_ appearance: Mark) -> some View {
        if appearance == .scanning, motion.isFull {
            TimelineView(.animation) { context in
                let lap = RoomTokens.Motion.traceLap
                let elapsed = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: lap)
                markPath(phase: elapsed / lap, ink: RoomTokens.Ink.secondary)
            }
            .accessibilityHidden(true)
        } else if appearance == .made {
            RoomMadeMark(color: accent.text)
                .accessibilityHidden(true)
        } else {
            let ink = appearance == .needsAccess ? RoomTokens.Status.elevated : RoomTokens.Ink.secondary
            markPath(phase: nil, ink: ink).accessibilityHidden(true)
        }
    }

    private func markPath(phase: Double?, ink: Color) -> some View {
        let bounds = CGRect(x: 0, y: 0, width: Self.markSize, height: Self.markSize)
        let outline = Path(RoomPocketMark.outerPath(in: bounds))
        return ZStack {
            outline.stroke(ink.opacity(phase == nil ? 0.75 : 0.35), lineWidth: 1)
            if let phase {
                let end = phase + RoomTokens.Motion.traceDashFraction
                outline.trim(from: phase, to: min(1, end)).stroke(accent.text, lineWidth: 1.4)
                if end > 1 {
                    outline.trim(from: 0, to: end - 1).stroke(accent.text, lineWidth: 1.4)
                }
            } else {
                Circle().fill(ink).frame(width: 2, height: 2)
            }
        }
    }

    @ViewBuilder
    private func action(_ state: RoomActivityPillState) -> some View {
        switch state {
        case .scanning(let tool, _, _, _):
            Button("Stop") { stop(tool); expanded = false }
        case .moved(let receipt), .made(let receipt):
            if receipt.canRestore { Button("Restore") { expanded = false; restore(receipt.id) } }
        default:
            EmptyView()
        }
    }

    private func rawLabel(_ state: RoomActivityPillState) -> String {
        switch state {
        case .idle(let bytes):
            bytes.map { "\(RoomFormat.gb($0)) free" } ?? "Free space unavailable"
        case .scanning(_, let location, _, _):
            location.isEmpty ? "Checking…" : location
        case .needsAccess(let folders):
            "Needs access · \(folders) \(folders == 1 ? "folder" : "folders")"
        case .moved(let receipt), .made(let receipt):
            receipt.sentence
        case .ok(let sentence), .failed(let sentence):
            sentence
        case .stopped(let measured, let count):
            "Check stopped · \(measured) of \(count) places"
        }
    }

    private func label(_ state: RoomActivityPillState) -> String {
        guard hidden else { return rawLabel(state) }
        if case .scanning = state { return "Checking · details hidden" }
        return RoomCachesVisibility.figure(rawLabel(state), hidden: hidden)
    }

    private func toolbarLabel(_ state: RoomActivityPillState) -> String {
        if prefersQuietIdleLabel, case .idle(.some) = state { return String(localized: "Up to date") }
        return label(state)
    }

    private func spoken(_ state: RoomActivityPillState) -> String {
        guard hidden else { return rawLabel(state) }
        switch state {
        case .idle: return "Free space hidden"
        case .scanning: return "Checking. Details hidden."
        case .moved: return "Moved to Trash. Size hidden."
        case .made: return "Made room. Size hidden."
        default: return "Activity details hidden"
        }
    }
}

private struct RoomMadeMark: View {
    let color: Color
    @Environment(\.roomMotion) private var motion
    @State private var settled = false

    var body: some View {
        let visible = settled || !motion.isFull
        Circle().fill(color)
            .overlay {
                RoomCheckmarkPath()
                    .trim(from: 0, to: visible ? 1 : 0)
                    .stroke(RoomTokens.Surface.canvas, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 7, height: 5)
                    .animation(motion.animation(RoomTokens.Motion.receiptLead, fallback: nil), value: visible)
            }
            .scaleEffect(visible ? 1 : 0.6)
            .animation(motion.animation(RoomTokens.Motion.success, fallback: nil), value: visible)
            .task { settled = true }
    }
}
