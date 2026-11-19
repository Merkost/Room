import AppKit
import SwiftUI

struct RoomGoalRulerView: View {
    @Binding var value: Int
    let capacityBytes: Int64
    var haptic: () -> Void = { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }

    @Environment(\.roomMotion) private var motion
    @Environment(\.roomAccent) private var accent
    @State private var dragStart: Double?
    @State private var display: Double?
    @State private var samples: [DragGesture.Value] = []
    @State private var scrollOrigin: Double?
    @State private var scrollPoints = 0.0
    @State private var scrollSettle: Task<Void, Never>?
    @State private var coastHaptics: Task<Void, Never>?

    private let width: CGFloat = 236
    private let height: CGFloat = 44
    private var capacity: Double { RoomGoalRulerBridge.gb(capacityBytes) }
    private var upper: Double { RoomGoalRulerBridge.upperDetentGB(capacityGB: capacity) }
    private var storedGB: Double {
        RoomGoalRulerBridge.gb(RoomGoalRulerBridge.storedBytes(restingGB: RoomGoalRulerBridge.gb(Int64(value)), capacityGB: capacity))
    }
    private var position: Double { display ?? storedGB }
    private var visibleValue: Int {
        Int(RoomGoalRulerBridge.gb(RoomGoalRulerBridge.storedBytes(restingGB: position, capacityGB: capacity)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoomTokens.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(visibleValue.formatted()).font(RoomTokens.Typography.figure)
                    .contentTransition(motion.isFull ? .numericText(value: Double(visibleValue)) : .identity)
                    .animation(motion.isFull ? RoomTokens.Motion.odometerColumn : nil, value: visibleValue)
                Text("GB").font(RoomTokens.Typography.caption).foregroundStyle(.secondary)
            }.accessibilityHidden(true)

            RoomGoalRulerTickScale(position: position, upper: upper)
                .frame(width: width, height: height)
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                    .init(color: .black, location: 0.78), .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(alignment: .top) {
                    Rectangle().fill(accent.fill).frame(width: 2, height: 17)
                }
                .background(RoomTokens.Surface.group, in: .rect(cornerRadius: RoomTokens.Radius.card))
                .overlay {
                    RoomGoalScrollInput(move: scroll).allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1).onChanged(drag).onEnded(release))
                .focusable()
                .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .pageUp, .pageDown, .home, .end],
                            phases: [.down, .repeat], action: keyPressed)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Free-space goal")
                .accessibilityValue("\(visibleValue) gigabytes")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(.right)
                    case .decrement: step(.left)
                    @unknown default: break
                    }
                }
        }.onDisappear {
            scrollSettle?.cancel()
            coastHaptics?.cancel()
        }
    }

    private func drag(_ event: DragGesture.Value) {
        if dragStart == nil {
            scrollSettle?.cancel()
            coastHaptics?.cancel()
            scrollOrigin = nil
            dragStart = position
            samples = []
        }
        guard let dragStart else { return }
        samples.append(event)
        if samples.count > 6 { samples.removeFirst() }
        let next = RoomGoalRuler.dragValue(startGB: dragStart, dragPoints: event.translation.width, capacityGB: capacity)
        fireHaptics(from: position, to: next)
        display = next
    }

    private func release(_ event: DragGesture.Value) {
        let current = position
        let velocity: Double
        if let first = samples.first, let last = samples.last, last.time > first.time {
            velocity = (last.translation.width - first.translation.width) / (last.time.timeIntervalSince(first.time) * 1_000)
        } else { velocity = 0 }
        let resting = RoomGoalRuler.restingGB(currentGB: current, releaseVelocityPtPerMS: velocity, capacityGB: capacity)
        dragStart = nil
        samples = []
        settle(restingGB: resting, from: current)
    }

    private func scroll(by points: Double) {
        guard dragStart == nil else { return }
        scrollSettle?.cancel()
        coastHaptics?.cancel()
        if scrollOrigin == nil {
            scrollOrigin = position
            scrollPoints = 0
        }
        guard let scrollOrigin else { return }
        scrollPoints += points
        let next = RoomGoalRuler.dragValue(startGB: scrollOrigin, dragPoints: scrollPoints, capacityGB: capacity)
        fireHaptics(from: position, to: next)
        display = next
        scrollSettle = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            let current = position
            self.scrollOrigin = nil
            settle(restingGB: current, from: current)
        }
    }

    private func settle(restingGB: Double, from current: Double) {
        let bytes = RoomGoalRulerBridge.storedBytes(restingGB: restingGB, capacityGB: capacity)
        let target = RoomGoalRulerBridge.gb(bytes)
        let distance = target - current
        coastHaptics?.cancel()
        if motion.isFull {
            let crossings = detentsCrossed(from: current, to: target)
            if crossings > 0 {
                let interval = RoomPure.coastMS(distanceGB: distance) / Double(crossings + 1)
                coastHaptics = Task { @MainActor in
                    for _ in 0..<crossings {
                        do { try await Task.sleep(for: .milliseconds(interval)) } catch { return }
                        haptic()
                    }
                }
            }
        } else {
            fireHaptics(from: current, to: target)
        }
        withAnimation(motion.isFull ? RoomTokens.Motion.coast(distanceGB: distance) : nil) {
            value = Int(bytes)
            display = nil
        }
    }

    private func fireHaptics(from old: Double, to new: Double) {
        for _ in 0..<detentsCrossed(from: old, to: new) { haptic() }
    }

    private func detentsCrossed(from old: Double, to new: Double) -> Int {
        let before = min(upper, max(RoomGoalRuler.minimumGB, old))
        let after = min(upper, max(RoomGoalRuler.minimumGB, new))
        return RoomGoalRulerBridge.detentsCrossed(from: before, to: after)
    }

    private func keyPressed(_ press: KeyPress) -> KeyPress.Result {
        let jump = press.modifiers.contains(.option)
        switch press.key {
        case .leftArrow, .downArrow: step(jump ? .pageDown : .left)
        case .rightArrow, .upArrow: step(jump ? .pageUp : .right)
        case .pageDown: step(.pageDown)
        case .pageUp: step(.pageUp)
        case .home: step(.home)
        case .end: step(.end)
        default: return .ignored
        }
        return .handled
    }

    private func step(_ key: RoomGoalRulerBridge.Key) {
        scrollSettle?.cancel()
        coastHaptics?.cancel()
        scrollOrigin = nil
        display = nil
        let next = RoomGoalRulerBridge.step(Int64(value), key: key, capacityGB: capacity)
        fireHaptics(from: position, to: RoomGoalRulerBridge.gb(next))
        value = Int(next)
    }
}

private struct RoomGoalRulerTickScale: View, Animatable {
    var position: Double
    let upper: Double

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { context, size in
            for tick in stride(from: RoomGoalRuler.minimumGB, through: upper, by: RoomGoalRuler.stepGB) {
                let x = size.width / 2 + (tick - position) * RoomGoalRuler.pointsPerGB
                guard (0...size.width).contains(x) else { continue }
                let major = tick.truncatingRemainder(dividingBy: RoomGoalRuler.labelEveryGB) == 0
                var mark = Path()
                mark.move(to: CGPoint(x: x, y: 17))
                mark.addLine(to: CGPoint(x: x, y: major ? 27 : 23))
                context.stroke(mark, with: .color(RoomTokens.Ink.secondary), lineWidth: 1)
                if major {
                    context.draw(Text(Int(tick).formatted()).font(RoomTokens.Typography.micro)
                        .foregroundStyle(RoomTokens.Ink.secondary), at: CGPoint(x: x, y: 35))
                }
            }
        }.accessibilityHidden(true)
    }
}

/// Scope scroll input to the ruler's own rectangle and window so other views still scroll normally.
private struct RoomGoalScrollInput: NSViewRepresentable {
    let move: (Double) -> Void

    func makeNSView(context: Context) -> ScrollRegion {
        let view = ScrollRegion()
        view.move = move
        return view
    }

    func updateNSView(_ view: ScrollRegion, context: Context) { view.move = move }

    static func dismantleNSView(_ view: ScrollRegion, coordinator: ()) { view.detach() }

    final class ScrollRegion: NSView {
        var move: ((Double) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                    ? event.scrollingDeltaX : event.scrollingDeltaY
                if delta != 0 { self.move?(event.hasPreciseScrollingDeltas ? delta : delta * 10) }
                return nil
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
