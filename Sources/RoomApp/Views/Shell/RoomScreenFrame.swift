import SwiftUI

/// The headline that answers a screen's question, number first: "64 GB" in ink, " free" in the quiet ink.
nonisolated struct RoomHeadline: Equatable, Sendable {
    /// The figure (a size goes through `RoomFormat.gb`); nil for a words-only headline such as "All clear".
    var figure: String?
    var words: String
    /// Whether Hide masks the figure (sizes yes; "9 of 16 GB" memory figures too).
    var masksFigure = true
    /// Whether Hide masks the words (a folder name in "in Developer").
    var masksWords = false

    static func words(_ text: String) -> RoomHeadline { RoomHeadline(figure: nil, words: text, masksFigure: false) }

    func spoken(hidden: Bool) -> String {
        let f = figure.map { masksFigure && hidden ? "Size hidden" : $0 }
        let w = masksWords && hidden ? "name hidden" : words
        return [f, w].compactMap { $0 }.joined(separator: " ")
    }
}

/// nav-v3 screen hierarchy (FEATURES rules 1 to 4): one serif headline, one supporting line, the evidence, one quiet
/// note at the bottom left and at most one filled button at the bottom right. The filled button is the caller's, so
/// the one-filled lint still sees it in the screen's own file.
struct RoomScreenFrame<Evidence: View, Action: View>: View {
    let headline: RoomHeadline
    var supporting: String?
    var supportingMasked = false
    var note: String?
    var scrollsEvidence = false
    @ViewBuilder var evidence: () -> Evidence
    @ViewBuilder var action: () -> Action

    @Environment(\.roomScreenInsets) private var insets
    @Environment(\.roomScreenSize) private var screenSize
    @Environment(\.roomHide) private var hide
    @Environment(\.roomMotion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoomHeadlineView(headline: headline, compact: screenSize.width < RoomTokens.Screen.compactBreakpoint)
                .padding(.top, RoomTokens.Screen2.headlineTop)
            if let supporting {
                Group {
                    if supportingMasked { RoomMaskable(supporting) } else { Text(supporting) }
                }
                .font(RoomTokens.Screen2.supporting)
                .foregroundStyle(RoomTokens.Ink.secondary)
                .padding(.top, RoomTokens.Screen2.supportingGap)
                .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if scrollsEvidence {
                    ScrollView { evidence().frame(maxWidth: .infinity, alignment: .topLeading) }
                        .scrollIndicators(.automatic)
                } else {
                    evidence().frame(maxWidth: .infinity, alignment: .topLeading)
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, RoomTokens.Screen2.evidenceGap)
            HStack(alignment: .center, spacing: RoomTokens.Space.group) {
                if let note {
                    Text(note)
                        .font(RoomTokens.Typography.body)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                        .animation(motion.animation(RoomTokens.Motion.quick, fallback: RoomTokens.Motion.fade), value: note)
                }
                Spacer(minLength: 0)
                action()
            }
            .frame(minHeight: RoomTokens.Overview.actionHeight)
            .padding(.top, RoomTokens.Screen2.footerGap)
        }
        .padding(EdgeInsets(top: insets.top, leading: insets.leading, bottom: RoomTokens.Space.breath1, trailing: insets.trailing))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RoomHeadlineView: View {
    let headline: RoomHeadline
    var compact = false
    @Environment(\.roomHide) private var hide

    var body: some View {
        let figure = headline.figure.map { headline.masksFigure ? RoomHideMask.display($0, kind: .figure, hide: hide) : $0 }
        let words = headline.masksWords ? RoomHideMask.display(headline.words, kind: .name, hide: hide) : headline.words
        let text: Text = if let figure {
            Text(verbatim: figure).foregroundStyle(RoomTokens.Ink.graphite)
                + Text(verbatim: words.isEmpty ? "" : " " + words).foregroundStyle(RoomTokens.Ink.tertiary)
        } else {
            Text(verbatim: words).foregroundStyle(RoomTokens.Ink.graphite)
        }
        text
            .font(compact ? RoomTokens.Screen2.headlineCompact : RoomTokens.Screen2.headline)
            .tracking(RoomTokens.Screen2.headlineTracking)
            .monospacedDigit()
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headline.spoken(hidden: hide.masksNow))
            .accessibilityAddTraits(.isHeader)
    }
}
