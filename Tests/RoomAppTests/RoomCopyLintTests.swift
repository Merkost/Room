import Foundation
import Testing
@testable import RoomApp

struct RoomCopyLintTests {
    @Test func catalogueResolvesInTests() {
        #expect(RoomCopy.bundle.localizedString(forKey: "nav.overview", value: "Fallback", table: nil) == "Overview")
    }

    @Test func pluralVariationsResolve() {
        let format = RoomCopy.bundle.localizedString(forKey: "history.cleanupCount", value: nil, table: nil)
        #expect(String.localizedStringWithFormat(format, Int64(1)) == "1 cleanup")
        #expect(String.localizedStringWithFormat(format, Int64(3)) == "3 cleanups")
    }

    @Test func defaultValueMatchesCatalogue() {
        let fallback = String(localized: "onboarding.p1.title", defaultValue: "Room to breathe.", bundle: .main)
        let localized = RoomCopy.bundle.localizedString(forKey: "onboarding.p1.title", value: nil, table: nil)
        #expect(fallback == localized)
    }

    @Test func copyLintPasses() throws {
        let appResources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RoomApp/Resources", isDirectory: true)
        let catalogues = try FileManager.default.contentsOfDirectory(at: appResources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xcstrings" }
        #expect(catalogues.count == 7)
        for catalogue in catalogues {
            let data = try Data(contentsOf: catalogue)
            let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rows = try #require(document["strings"] as? [String: [String: Any]])
            for (key, row) in rows {
                let localizations = row["localizations"] as? [String: [String: Any]]
                let english = localizations?["en"] ?? [:]
                for value in catalogueValues(english) {
                    #expect(RoomCopyLint.lint([key: value]).isEmpty, "\(catalogue.lastPathComponent) \(key)")
                }
            }
        }
    }

    private func catalogueValues(_ entry: [String: Any]) -> [String] {
        if let unit = entry["stringUnit"] as? [String: Any], let value = unit["value"] as? String { return [value] }
        return entry.values.compactMap { $0 as? [String: Any] }.flatMap { catalogueValues($0) }
    }
}
