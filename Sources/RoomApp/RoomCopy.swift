import Foundation

nonisolated enum RoomCopy {
    static let bundle: Bundle = {
        let main = Bundle.main
        if main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil {
            return main
        }
        let markerBundle = Bundle(for: BundleMarker.self)
        for container in [main, markerBundle] {
            let candidates = [container.resourceURL, container.bundleURL.deletingLastPathComponent()]
            for directory in candidates.compactMap({ $0 }) {
                let url = directory.appendingPathComponent("Room_RoomApp.bundle", isDirectory: true)
                if let bundle = Bundle(url: url) { return bundle }
            }
        }
        return main
    }()

    private final class BundleMarker: NSObject {}
}
