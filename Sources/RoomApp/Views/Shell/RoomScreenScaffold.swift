import SwiftUI

struct RoomScreenScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    var scrolls = true
    var requestedDensity: RoomTokens.Density? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let alignsTitleWithColumn = requestedDensity != nil
            let density: RoomTokens.Density = geometry.size.width >= 700 ? requestedDensity ?? .calm : .compact
            let gutter = alignsTitleWithColumn ? density.gutter : RoomTokens.Space.breath1
            let columnLimit = alignsTitleWithColumn ? RoomTokens.Overview.contentWidth + 2 * gutter : 1120
            let centeredInset = alignsTitleWithColumn ? max(0, (geometry.size.width - columnLimit) / 2) : 0
            let titleInset = (scrolls ? gutter + centeredInset : RoomTokens.Space.group) - 4
            Group {
                if scrolls {
                    ScrollView {
                        content()
                            .padding(.horizontal, gutter)
                            .padding(.top, alignsTitleWithColumn ? density.topInset : 4)
                            .padding(.bottom, RoomTokens.Space.breath1)
                            .frame(maxWidth: columnLimit, alignment: .topLeading)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    content()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoomTokens.Surface.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.inner) {
                        Text(title).font(RoomTokens.Typography.title).fixedSize()
                        if let subtitle {
                            Text(subtitle).font(RoomTokens.Typography.caption)
                                .foregroundStyle(RoomTokens.Ink.secondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(alignsTitleWithColumn ? [] : .isHeader)
                    // The native toolbar already insets navigation items by 4 points.
                    .padding(.leading, titleInset)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle ?? "")
    }
}
