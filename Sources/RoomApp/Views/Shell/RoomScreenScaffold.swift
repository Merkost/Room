import SwiftUI

struct RoomScreenScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    var scrolls = true
    var requestedDensity: RoomTokens.Density? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let density: RoomTokens.Density = geometry.size.width >= 700 ? requestedDensity ?? .calm : .compact
            Group {
                if scrolls {
                    ScrollView {
                        content()
                            .padding(.horizontal, requestedDensity == nil ? RoomTokens.Space.breath1 : density.gutter)
                            .padding(.top, requestedDensity == nil ? 4 : density.topInset)
                            .padding(.bottom, RoomTokens.Space.breath1)
                            .frame(maxWidth: 1120, alignment: .topLeading)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    content()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoomTokens.Surface.canvas.ignoresSafeArea())
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle ?? "")
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
                .accessibilityAddTraits(requestedDensity == nil ? .isHeader : [])
                .padding(.leading, scrolls && requestedDensity == nil ? RoomTokens.Space.breath1 - 4 : 0)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
