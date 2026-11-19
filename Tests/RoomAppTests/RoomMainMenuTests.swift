#if DEBUG
import AppKit
import Testing
@testable import RoomApp

@Suite("Native Room menu") @MainActor
struct RoomMainMenuTests {
    @Test func realMenuContainsBuiltCommands() async throws {
        let files = FileManager.default
        let fixture = files.temporaryDirectory.appendingPathComponent("RoomMainMenuTests-\(UUID())")
        defer { try? files.removeItem(at: fixture) }
        let bundle = try await Self.prepareApp(at: fixture)

        let output = fixture.appendingPathComponent("menu.json")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-RoomOnboardingVersion", "1", "-RoomOpenOn", "overview",
                                   "-RoomMenuBarEnabled", "NO", "-AppleLanguages", "(en-US)"]
        configuration.environment = ["ROOM_MAIN_MENU_TEST_OUTPUT": output.path]
        let application = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
        defer { if !application.isTerminated { application.terminate() } }

        let deadline = ContinuousClock.now + .seconds(15)
        while !files.fileExists(atPath: output.path), !application.isTerminated, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let menus = try JSONDecoder().decode([RoomDebugMainMenuProbe.Menu].self, from: Data(contentsOf: output))
        let allRows = menus.flatMap(\.rows)
        func menu(_ title: String) throws -> [RoomDebugMainMenuProbe.Row] {
            try #require(menus.first { $0.title == title }?.rows)
        }

        let appMenu = try #require(menus.first { $0.rows.contains { $0.title == "Show Monitor" } }?.rows)
        #expect(appMenu.contains { $0.title == "About Room" })
        #expect(appMenu.contains { $0.title == "Settings…" && $0.key == "," })
        #expect(appMenu.contains { $0.title == "Show Monitor" && !$0.enabled })
        #expect(appMenu.contains { $0.title == "Quit Room" && $0.key == "q" && !$0.alternate })

        let file = try menu("File")
        #expect(file.filter { ["Pin Folder as a Room…", "Open Trash", "Close"].contains($0.title) }.map(\.title)
            == ["Pin Folder as a Room…", "Open Trash", "Close"])
        #expect(file.contains { $0.title == "Close" && $0.key == "w" && !$0.alternate })
        let edit = try menu("Edit")
        #expect(edit.contains { $0.title == "Copy" && $0.key == "c" })
        let view = try menu("View")
        #expect(view.contains { $0.title == "Refresh Free Space" && $0.key == "r" && $0.enabled })
        #expect(view.contains { $0.title.contains("Full Screen") })

        let go = try menu("Go")
        #expect(go.map(\.title) == ["Back", "Forward", "Overview", "Disk Map", "Caches", "Developer", "Memory", "Show History", "Enclosing Folder"])
        #expect(go.dropFirst(2).prefix(5).map(\.key) == ["1", "2", "3", "4", "5"])
        #expect(go.contains { $0.title == "Show History" && $0.key == "y" && $0.enabled })
        #expect(go.first { $0.title == "Enclosing Folder" }?.enabled == false)
        #expect(go.first { $0.title == "Back" }?.key == "[")
        #expect(go.first { $0.title == "Forward" }?.key == "]")
        #expect(go.first { $0.title == "Forward" }?.enabled == false)
        #expect(view.first { $0.title == "Hide Sidebar Labels" }?.key == "s")
        let window = try menu("Window")
        #expect(window.contains { $0.title == "Minimize" && $0.key == "m" })
        #expect(!window.contains { $0.title == "Close" && !$0.alternate })
        let help = try menu("Help")
        #expect(help.filter { ["Show Welcome", "Room Support", "Privacy"].contains($0.title) }.map(\.title)
            == ["Show Welcome", "Room Support", "Privacy"])
        let debug = try menu("Debug")
        #expect(debug.contains { $0.title == "Menu bar state" && !$0.enabled })
        #expect(debug.contains { $0.title == "Simulate Trash Emptied" && $0.enabled })
        #expect(debug.contains { $0.title == "Reset Simulated Trash" && $0.enabled })

        let command = NSEvent.ModifierFlags.command.rawValue
        let shiftCommand = NSEvent.ModifierFlags([.shift, .command]).rawValue
        #expect(allRows.filter { $0.key == "w" && $0.modifiers == command }.count == 1)
        #expect(allRows.filter { $0.key == "r" && $0.modifiers == command }.count == 1)
        #expect(!allRows.contains { $0.key.lowercased() == "r" && $0.modifiers == shiftCommand })
        let deferred = ["Scan Caches", "Stop Cache Scan", "Show Inspector",
                        "Customise Overview…", "Toggle Sidebar"]
        #expect(allRows.allSatisfy { !deferred.contains($0.title) })
    }

    @concurrent
    private static func prepareApp(at fixture: URL) async throws -> URL {
        let files = FileManager.default
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = try #require(executableProduct(), "Room executable beside the SwiftPM test bundle")
        let bundle = fixture.appendingPathComponent("Room.app")
        let contents = bundle.appendingPathComponent("Contents")
        let binaries = contents.appendingPathComponent("MacOS")
        try files.createDirectory(at: binaries, withIntermediateDirectories: true)
        try files.copyItem(at: executable, to: binaries.appendingPathComponent("Room"))
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        var info = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        info["CFBundleIdentifier"] = "app.room.tests.menu.\(UUID().uuidString.lowercased())"
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: contents.appendingPathComponent("Info.plist"))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let signer = Process()
            signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            signer.arguments = ["--force", "--sign", "-", bundle.path]
            signer.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteNoPermission))
                }
            }
            do { try signer.run() } catch { continuation.resume(throwing: error) }
        }
        return bundle
    }

    nonisolated private static func executableProduct() -> URL? {
        var directory = Bundle(for: RoomMainMenuTestBundleMarker.self).bundleURL
        while directory.path != "/" {
            let product = directory.appendingPathComponent("Room")
            if FileManager.default.isExecutableFile(atPath: product.path),
               (try? product.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return product
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}

private final class RoomMainMenuTestBundleMarker: NSObject {}
#endif
