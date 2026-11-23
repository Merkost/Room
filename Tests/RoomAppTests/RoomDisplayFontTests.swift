import AppKit
import Foundation
import Testing
@testable import RoomApp

@MainActor
struct RoomDisplayFontTests {
    @Test func registersFraunces() throws {
        #expect(RoomDisplayFont.register())
        let font = try #require(NSFont(name: "Fraunces", size: 26))
        #expect(font.familyName == "Fraunces")
        // Registering twice is harmless.
        #expect(RoomDisplayFont.register())
    }

    @Test func licenceShipsBesideFont() throws {
        let font = try #require(RoomDisplayFont.fontURL())
        let licence = try #require(RoomDisplayFont.licenceURL())
        #expect(font.deletingLastPathComponent() == licence.deletingLastPathComponent())
        let text = try String(contentsOf: licence, encoding: .utf8)
        #expect(text.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(text.contains("Fraunces Project Authors"))
    }
}
