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
                            .padding(.horizontal, density.gutter)
                            .padding(.top, requestedDensity?.topInset ?? RoomTokens.Density.calm.topInset)
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
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(RoomTokens.Typography.title)
                    if let subtitle {
                        Text(subtitle).font(RoomTokens.Typography.caption)
                            .foregroundStyle(RoomTokens.Ink.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
