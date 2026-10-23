import SwiftUI

/// Roles, rather than free-form sizes, establish hierarchy across Room's windows.
/// San Francisco remains the platform voice; numeric styles use tabular digits
/// at the point of rendering, so ordinary text keeps its natural spacing.
enum RoomTypography {
    static let pageTitle = Font.system(size: 24, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12)
    static let captionEmphasis = Font.system(size: 12, weight: .medium)
    static let meta = Font.system(size: 11, weight: .medium)
    static let metric = Font.system(size: 38, weight: .regular)
    static let secondaryMetric = Font.system(size: 22, weight: .regular)
}

enum RoomSpace {
    static let micro: CGFloat = 4
    static let small: CGFloat = 8
    static let compact: CGFloat = 12
    static let standard: CGFloat = 16
    static let section: CGFloat = 24
    static let page: CGFloat = 28
}

enum RoomRadius {
    static let control: CGFloat = 8
    static let row: CGFloat = 12
    static let group: CGFloat = 16
}

/// Working surfaces stay opaque and semantic. Liquid Glass belongs to native
/// navigation and controls, rather than behind every group of data.
enum RoomSurface {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let group = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let selection = Color.accentColor.opacity(0.085)
    static let hover = Color.primary.opacity(0.045)
}

enum RoomMotion {
    static let selection = Animation.smooth(duration: 0.22)
    static let disclosure = Animation.smooth(duration: 0.24)
    static let measurement = Animation.smooth(duration: 0.25)
}

/// Shared preference resolution makes in-app and accessibility motion settings
/// authoritative in every consumer. Callers animate the smallest changed view,
/// never the whole scrolling workspace on each measurement update.
struct RoomMotionPolicy: DynamicProperty {
    @AppStorage("RoomMotionEnabled") private var motionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var enabled: Bool { motionEnabled && !reduceMotion }
    var selection: Animation? { enabled ? RoomMotion.selection : nil }
    var disclosure: Animation? { enabled ? RoomMotion.disclosure : nil }
    var measurement: Animation? { enabled ? RoomMotion.measurement : nil }
    var pageTransition: AnyTransition {
        enabled ? .opacity.combined(with: .offset(y: 6)) : .identity
    }
}

/// Compatibility while existing screens migrate to the semantic role styles.
enum RoomType {
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func figure(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
}
