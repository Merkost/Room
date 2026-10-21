import Foundation
import Testing
@testable import RoomApp

@Suite("Public support and privacy links") @MainActor
struct RoomAppLinksTests {
    @Test func missingAndPlaceholderLinksStayAbsent() {
        #expect(RoomAppLinks(info: [:]).support == nil)
        for value in ["http://room.merkost.dev", "https://example.com/privacy", "https://publisher.invalid/privacy", "https://localhost", "https://user:secret@room.merkost.dev", "https://{host}/privacy"] {
            #expect(RoomAppLinks(info: ["RoomPrivacyURL": value]).privacy == nil)
        }
    }
    @Test func configuredPublicHTTPSLinksArePreserved() {
        let links = RoomAppLinks(info: ["RoomSupportURL": "https://room.merkost.dev/support", "RoomPrivacyURL": "https://room.merkost.dev/privacy"])
        #expect(links.support?.absoluteString == "https://room.merkost.dev/support")
        #expect(links.privacy?.absoluteString == "https://room.merkost.dev/privacy")
    }
}
