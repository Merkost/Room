import SwiftUI

private struct RoomScreenInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    var roomScreenInsets: EdgeInsets {
        get { self[RoomScreenInsetsKey.self] }
        set { self[RoomScreenInsetsKey.self] = newValue }
    }
}

struct RoomScreenScaffold<Content: View>: View {
    /// Coordinate space of the detail column, for motion that aims at the toolbar.
    static var space: String { "RoomScreen" }
    let title: String
    let subtitle: String?
    var scrolls = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let density: RoomTokens.Density = width < RoomTokens.Screen.compactBreakpoint ? .compact : .calm
            let gutter = density.gutter + max(0, (width - RoomTokens.Screen.maximumColumnWidth) / 2)
            let insets = EdgeInsets(top: density.topInset, leading: gutter,
                                    bottom: RoomTokens.Space.breath1, trailing: gutter)
            Group {
                if scrolls {
                    ScrollView {
                        content().frame(maxWidth: .infinity, alignment: .topLeading).padding(insets)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    content().environment(\.roomScreenInsets, insets)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.roomScreenSize, geometry.size)
            .coordinateSpace(.named(RoomScreenScaffold<EmptyView>.space))
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
                    .accessibilityAddTraits(.isHeader)
                    // The native toolbar already insets navigation items by 4 points.
                    .padding(.leading, gutter - 4)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle ?? "")
    }
}
