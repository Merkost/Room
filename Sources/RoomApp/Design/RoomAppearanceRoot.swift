import AppKit

/// One source for Room's Appearance setting across every window (ONBOARDING-V3-SPEC §7, AP-1, D-ONV-10).
/// `.preferredColorScheme` on a window root does not reach sheets, `NSAlert` or `NSOpenPanel`: those are separate
/// windows. Setting `NSApp.appearance` from `RoomAppearance` makes them follow Room instead of the system.
@MainActor
final class RoomAppearanceRoot {
    nonisolated static let key = "RoomAppearance"
    /// Same default as `@AppStorage("RoomAppearance")` in RoomRootView and Settings.
    nonisolated static let defaultValue = "dark"

    private let defaults: UserDefaults
    private let apply: @MainActor (NSAppearance?) -> Void
    private var observer: NSObjectProtocol?
    private(set) var applied: String?

    init(defaults: UserDefaults = .standard, apply: @escaping @MainActor (NSAppearance?) -> Void = { NSApp.appearance = $0 }) {
        self.defaults = defaults
        self.apply = apply
    }

    /// `nil` follows the system; "light" and "dark" pin Aqua and Dark Aqua.
    nonisolated static func appearanceName(for preference: String?) -> NSAppearance.Name? {
        switch preference ?? defaultValue {
        case "light": .aqua
        case "dark": .darkAqua
        default: nil
        }
    }

    /// Applies the stored preference now and again whenever it changes, without a relaunch.
    func install() {
        update()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults,
                                                          queue: nil) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.update() }
            } else {
                Task { @MainActor in self?.update() }
            }
        }
    }

    func update() {
        let preference = defaults.string(forKey: Self.key) ?? Self.defaultValue
        guard preference != applied else { return }
        applied = preference
        apply(Self.appearanceName(for: preference).flatMap(NSAppearance.init(named:)))
    }
}
