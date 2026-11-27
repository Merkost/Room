import Foundation
import Testing

/// Spec rule: one filled button per context. In the window it is the dock's.
/// A lint over the view sources: every filled style counts against its surface (a screen, or a sheet on its own).
/// Mutually exclusive branches (a start panel that never shows beside the screen's main action) are allowed only
/// when the line says so with `// one-filled: exclusive <why>`.
struct RoomButtonHierarchyTests {
    private static let filled = try! NSRegularExpression(
        pattern: #"\.(roomPrimary|roomScreenPrimary)\(|\.glassProminent\b|\.borderedProminent\b"#)

    private struct Site: CustomStringConvertible {
        let file: String
        let line: Int
        let surface: String
        var description: String { "\(file):\(line)" }
    }

    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/RoomApp", isDirectory: true)
    }

    /// Which screen a view file draws. Sheets, editors and popovers are their own surface (keyed by type name).
    static func surface(path: String, type: String?) -> String {
        if let type, ["Sheet", "Editor", "Popover"].contains(where: type.contains) { return type }
        let name = (path as NSString).lastPathComponent
        if path.contains("/Views/Overview/") { return "Overview" }
        if name == "RoomDiskMapView.swift" || path.contains("/Views/DiskMap/") { return "Disk Map" }
        if path.contains("/Views/Caches/") { return "Caches" }
        if name == "RoomDeveloperView.swift" || name == "RoomAgentWorkView.swift" || path.contains("/Views/Developer/") {
            return "Developer"
        }
        if name == "RoomMemoryView.swift" || path.contains("/Views/Memory/") { return "Memory" }
        if name.contains("Settings") { return "Settings" }
        if name == "RoomMenuBarView.swift" { return "Popover" }
        if path.contains("/Views/Shell/") || path.contains("/Views/Toolbar/") || path.contains("/Views/Receipts/") {
            return "Window chrome"
        }
        return name
    }

    private func sites() throws -> [Site] {
        let files = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && !$0.path.contains("/Design/") } ?? []
        var found: [Site] = []
        for file in files {
            var type: String?
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                if let range = line.range(of: #"^(private |fileprivate )?struct (\w+)"#, options: .regularExpression) {
                    type = line[range].split(separator: " ").last.map(String.init)
                }
                let code = line.components(separatedBy: "//").first ?? line
                let matches = Self.filled.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
                guard matches > 0, !line.contains("one-filled: exclusive") else { continue }
                found += Array(repeating: Site(file: file.lastPathComponent, line: index + 1,
                                               surface: Self.surface(path: file.path, type: type)), count: matches)
            }
        }
        return found
    }

    @Test func oneFilledButtonPerScreen() throws {
        let bySurface = Dictionary(grouping: try sites(), by: \.surface)
        #expect(!bySurface.isEmpty, "the lint found no filled buttons at all; the source path is wrong")
        for (surface, sites) in bySurface {
            #expect(sites.count == 1, "\(surface) has \(sites.count) filled buttons: \(sites)")
        }
        // The dock owns the window's filled button; the screens have none of their own.
        #expect(bySurface["Window chrome"]?.map(\.file) == ["RoomDock.swift"])
        for screen in ["Overview", "Disk Map", "Caches", "Developer", "Memory", "Settings"] {
            #expect(bySurface[screen] == nil, "\(screen) has no filled button of its own")
        }
    }

    @Test func lintCatchesASecondFilledButton() {
        let code = #"Button("A") {}.roomScreenPrimary(accent); Button("B") {}.buttonStyle(.borderedProminent)"#
        let count = Self.filled.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
        #expect(count == 2)
        #expect(Self.surface(path: "/x/Views/Caches/RoomCleanupReviewSheet.swift", type: "RoomCleanupReviewSheet")
                == "RoomCleanupReviewSheet")
        #expect(Self.surface(path: "/x/Views/DiskMap/RoomMapReadout.swift", type: "RoomMapReadout") == "Disk Map")
    }
}
