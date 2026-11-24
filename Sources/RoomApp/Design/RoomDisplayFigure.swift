import SwiftUI

/// Where the display face (Fraunces) may appear in the product: the Overview hero figure and the chapter headings.
/// Nothing dense: lists, tables, controls, the menu bar and every other number stay in SF (BRAND-DS, owner exception
/// for the Overview hero, 1.2.0).
enum RoomDisplayType {
    /// Overview chapter headings ("Storage map", "Your Rooms", "Your week", "Recent").
    static let chapter = RoomDS.TypeRole.display.font
    static let chapterTracking: CGFloat = RoomDS.TypeRole.display.spec.tracking

    static func figure(_ size: CGFloat) -> Font {
        Font.custom(RoomDS.displayFamilyName, fixedSize: size).weight(.medium)
    }
}

/// The bundled Fraunces cut has proportional figures and no `tnum` feature, so `monospacedDigit()` cannot make it
/// tabular. Each digit (and each Hide bullet) sits in a fixed slot as wide as the widest figure instead: a changing
/// value never nudges its unit, and masking never moves geometry.
nonisolated enum RoomDisplayFigureSlots {
    /// The widest Fraunces figure ("0") is 1289 / 2000 em.
    static let slotEm: CGFloat = 0.645

    struct Slot: Identifiable, Equatable {
        /// Counted from the right, so units, tens and decimals keep their slot when the value gains a digit.
        let id: Int
        let character: Character
        var isFixed: Bool { character.isNumber || character == RoomDisplayFigureSlots.bullet }
    }

    static let bullet: Character = "•"

    static func slots(_ text: String) -> [Slot] {
        let characters = Array(text)
        return characters.enumerated().map { index, character in
            Slot(id: characters.count - 1 - index, character: character)
        }
    }
}

/// The Overview hero number in the display face. Each slot rolls on its own (`numericText`) when the value really
/// changes; the first appearance and Hide never count. Hide dissolves the digits to bullets in place.
struct RoomDisplayFigure: View {
    let value: String
    let size: CGFloat
    var animatesChanges = false
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion

    private enum Dissolve: CaseIterable { case rest, soft, clear }

    var body: some View {
        let shown = RoomHideMask.display(value, kind: .figure, hide: hide)
        let rolls = animatesChanges && motion.isFull && !hide.masksNow
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(RoomDisplayFigureSlots.slots(shown)) { slot in
                Text(verbatim: String(slot.character))
                    .frame(width: slot.isFixed ? size * RoomDisplayFigureSlots.slotEm : nil)
                    .contentTransition(rolls ? .numericText() : .opacity)
            }
        }
        .font(RoomDisplayType.figure(size))
        .tracking(0)
        .animation(rolls ? RoomTokens.Motion.countAnimation : nil, value: shown)
        .animation(hide.isPeeking ? nil : RoomTokens.Motion.fade, value: hide.isOn)
        .phaseAnimator(Dissolve.allCases, trigger: motion.isFull && !hide.isPeeking ? hide.isOn : nil) { content, phase in
            content.blur(radius: phase == .soft ? RoomHideMask.dissolveBlur : 0)
        } animation: { _ in
            .timingCurve(RoomTokens.Motion.fadeCurve, duration: RoomHideMask.dissolveDuration / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RoomHideSpeech.value(value, hide: hide))
    }
}
