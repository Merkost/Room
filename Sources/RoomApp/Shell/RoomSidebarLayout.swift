import CoreGraphics

nonisolated enum RoomSidebarMode: Equatable, Sendable { case labelled, iconsOnly }

/// SH-12 / board v4 `sbToggle`: labelled 212 pt, icons-only 56 pt. Below 900 pt of window width the sidebar is
/// icons-only automatically and comes back when wider; the person's own choice (⌃⌘S) is remembered. The divider is
/// not draggable (D-FND-1): the column has one fixed width per mode.
nonisolated enum RoomSidebarLayout {
    static let labelledWidth: CGFloat = 212
    static let iconsWidth: CGFloat = 56
    static let autoCollapseBelow: CGFloat = 900
    static let rowHeight: CGFloat = 30
    static let iconLeading: CGFloat = 16

    static func mode(windowWidth: CGFloat, userPrefersIcons: Bool) -> RoomSidebarMode {
        (userPrefersIcons || windowWidth < autoCollapseBelow) ? .iconsOnly : .labelled
    }
    static func width(_ mode: RoomSidebarMode) -> CGFloat { mode == .labelled ? labelledWidth : iconsWidth }
    /// Shortcut hints (11 pt) show only at the labelled width.
    static func showsShortcutHints(_ mode: RoomSidebarMode) -> Bool { mode == .labelled }
}
