import Accessibility
import SwiftUI

struct RoomActivityPill: View {
    var stop: (RoomActivityPillState.Tool) -> Void = { _ in }
    var restore: (UUID) -> Void = { _ in }
    var showHistory: () -> Void = {}

    @Environment(\.roomActivityCenter) private var center
    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @Environment(\.roomHide) private var hide
    private var hidden: Bool { hide.masksNow }
    @State private var expanded = false
    @State private var hovered = false

    var body: some View {
        if let center {
            let state = center.visible
            let text = label(state)
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: RoomTokens.Space.row) {
                    mark(state)
                    RoomChangingLabel(value: text, animates: !hidden) {
                        Text(text).font(RoomTokens.Typography.caption.monospacedDigit())
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 360, minHeight: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Capsule())
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
    private func mark(_ state: RoomActivityPillState) -> some View {
        if case .scanning = state, motion.isFull {
            TimelineView(.animation) { context in
                let lap = RoomTokens.Motion.traceLap
                let elapsed = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: lap)
                markPath(phase: elapsed / lap)
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
        } else if case .made = state {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(accent.text)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        } else {
            markPath(phase: nil).frame(width: 16, height: 16).accessibilityHidden(true)
        }
    }

    private func markPath(phase: Double?) -> some View {
        Canvas { context, size in
            let outline = Path(RoomPocketMark.outerPath(in: CGRect(origin: .zero, size: size)))
            context.stroke(outline, with: .color(phase == nil ? accent.text.opacity(0.9) : RoomTokens.Ink.secondary.opacity(0.35)), lineWidth: 1.2)
            if let phase {
                let end = phase + RoomTokens.Motion.traceDashFraction
                context.stroke(outline.trimmedPath(from: phase, to: min(1, end)), with: .color(accent.text), lineWidth: 1.4)
                if end > 1 {
                    context.stroke(outline.trimmedPath(from: 0, to: end - 1), with: .color(accent.text), lineWidth: 1.4)
                }
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
            bytes.map { "\(RoomFormat.overviewBytes($0)) free" } ?? "Free space unavailable"
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
