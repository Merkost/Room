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

/// The pane (mockup `.pane`): a 34 pt bar with the place's name, its crumb and the status chip, then the screen.
/// The bar lives in the pane rather than the window toolbar so it lines up with the content column.
struct RoomScreenScaffold<Content: View>: View {
    /// Coordinate space of the detail column, for motion that aims at the toolbar.
    static var space: String { "RoomScreen" }
    let title: String
    let subtitle: String?
    var scrolls = true
    var chip: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let density: RoomTokens.Density = width < RoomTokens.Screen.compactBreakpoint ? .compact : .calm
            let extra = max(0, (width - RoomTokens.Screen.maximumColumnWidth) / 2)
            let leading = (density == .calm ? RoomTokens.Screen2.paneLeading : density.gutter) + extra
            let trailing = (density == .calm ? RoomTokens.Screen2.paneTrailing : density.gutter) + extra
            let insets = EdgeInsets(top: 0, leading: leading, bottom: RoomTokens.Screen2.paneBottom, trailing: trailing)
            // The bar is drawn over the screen (not above it in a stack) so a screen that hosts an inspector column
            // can never paint over it.
            ZStack(alignment: .top) {
                Group {
                    if scrolls {
                        ScrollView {
                            content().frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(EdgeInsets(top: RoomTokens.Space.group, leading: leading,
                                                    bottom: RoomTokens.Space.breath1, trailing: trailing))
                        }
                        .scrollIndicators(.hidden)
                    } else {
                        content().environment(\.roomScreenInsets, insets)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, RoomTokens.Screen2.paneTop + RoomTokens.Screen2.barHeight)
                bar
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
                    .padding(.top, RoomTokens.Screen2.paneTop)
            }
            .environment(\.roomScreenSize, geometry.size)
            .coordinateSpace(.named(RoomScreenScaffold<EmptyView>.space))
            .background(RoomTokens.Surface.canvas)
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle ?? "")
    }

    private var bar: some View {
        HStack(alignment: .center, spacing: RoomTokens.Space.row) {
            HStack(alignment: .firstTextBaseline, spacing: RoomTokens.Space.row) {
                Text(title).font(RoomTokens.Screen2.barTitle).foregroundStyle(RoomTokens.Ink.graphite).fixedSize()
                if let subtitle {
                    Text(subtitle).font(RoomTokens.Typography.body)
                        .foregroundStyle(RoomTokens.Ink.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: RoomTokens.Space.group)
            if let chip { chip }
        }
        .frame(height: RoomTokens.Screen2.barHeight)
    }
}
