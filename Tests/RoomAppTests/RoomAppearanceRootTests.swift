import AppKit
import Foundation
import Testing
@testable import RoomApp

/// ONBOARDING-V3-SPEC §7 AP-1: Room's Appearance setting reaches every window, including sheets, alerts and pickers.
@MainActor
struct RoomAppearanceRootTests {
    private final class Applied {
        var names: [NSAppearance.Name?] = []
    }

    private func fixture() -> (UserDefaults, String, Applied, RoomAppearanceRoot) {
        let suite = "RoomAppearanceRoot-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let applied = Applied()
        let root = RoomAppearanceRoot(defaults: defaults) { applied.names.append($0?.name) }
        return (defaults, suite, applied, root)
    }

    @Test func darkPreferenceSetsDarkAqua() {
        let (defaults, suite, applied, root) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: RoomAppearanceRoot.key)
        root.install()
        #expect(applied.names == [.darkAqua])
    }

    @Test func unsetPreferenceUsesRoomsDarkDefault() {
        let (defaults, suite, applied, root) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        root.install()
        #expect(applied.names == [.darkAqua])
    }

    @Test func systemPreferenceClearsAppAppearance() {
        let (defaults, suite, applied, root) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("system", forKey: RoomAppearanceRoot.key)
        root.install()
        #expect(applied.names == [nil])
        #expect(RoomAppearanceRoot.appearanceName(for: "light") == .aqua)
    }

    @Test func changeAppliesWithoutRelaunch() {
        let (defaults, suite, applied, root) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("light", forKey: RoomAppearanceRoot.key)
        root.install()
        defaults.set("dark", forKey: RoomAppearanceRoot.key)
        defaults.set("dark", forKey: RoomAppearanceRoot.key)
        defaults.set("system", forKey: RoomAppearanceRoot.key)
        #expect(applied.names == [.aqua, .darkAqua, nil])
    }
}
