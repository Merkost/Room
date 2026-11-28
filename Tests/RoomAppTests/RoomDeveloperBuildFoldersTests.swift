import Foundation
import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor struct RoomDeveloperBuildFoldersTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func project(_ name: String, age: Double?, folders: [(String, Int64)], kinds: [DeveloperProjectKind] = [.node]) -> DeveloperFoundProject {
        let url = URL(fileURLWithPath: "/Users/sample/code/\(name)", isDirectory: true)
        return DeveloperFoundProject(url: url, kinds: kinds, buildFolders: folders.map {
            DeveloperBuildFolder(url: url.appendingPathComponent($0.0), name: $0.0, kind: kinds[0], bytes: $0.1,
                                 partial: false, sharesFiles: false)
        }, lastChanged: age.map { now.addingTimeInterval(-$0 * day) })
    }

    @Test func onlyProjectsUntouchedForAMonthAreTickedForYou() {
        let scan = DeveloperProjectScan(projects: [
            project("old", age: 45, folders: [("node_modules", 2_000_000_000)]),
            project("fresh", age: 3, folders: [("node_modules", 1_000_000_000)]),
            project("unknown", age: nil, folders: [("node_modules", 500_000_000)]),
            project("empty", age: 400, folders: []),
        ], partial: false)
        let ticked = RoomDeveloperBuildFolders.suggested(scan, now: now)
        #expect(ticked == ["/Users/sample/code/old"])
        #expect(RoomDeveloperBuildFolders.bytes(scan, selection: ticked) == 2_000_000_000)
        #expect(RoomDeveloperBuildFolders.staleBytes(scan, now: now) == 2_000_000_000)
    }

    @Test func aProjectTheSearchDidNotFinishIsNeverTickedForYou() {
        let url = URL(fileURLWithPath: "/Users/sample/code/half", isDirectory: true)
        let half = DeveloperFoundProject(url: url, kinds: [.node], buildFolders: [
            DeveloperBuildFolder(url: url.appendingPathComponent("node_modules"), name: "node_modules", kind: .node,
                                 bytes: 5_000_000_000, partial: false, sharesFiles: false)
        ], lastChanged: now.addingTimeInterval(-200 * day), fullyRead: false)
        #expect(RoomDeveloperBuildFolders.suggested(DeveloperProjectScan(projects: [half], partial: true), now: now).isEmpty)
    }

    @Test func agesReadAsPeopleSayThem() {
        let words = [0.2, 1.5, 4, 20, 100, 800].map { RoomDeveloperBuildFolders.age(now.addingTimeInterval(-$0 * day), now: now) }
        #expect(words == ["today", "yesterday", "4 days ago", "2 weeks ago", "3 months ago", "2 years ago"])
        #expect(RoomDeveloperBuildFolders.age(nil, now: now) == nil)
    }

    @Test func aRowSaysWhatATickClearsAndHowFresh() {
        let web = project("web", age: 120, folders: [("node_modules", 2_000_000_000), (".next", 1_000_000_000), ("packages/ui/node_modules", 100)])
        #expect(RoomDeveloperBuildFolders.meta(web, now: now) == "3 GB to clear · 4 months ago")
        #expect(RoomDeveloperBuildFolders.meta(web, now: now, alsoElsewhere: false) == "4 months ago")
        #expect(RoomDeveloperBuildFolders.summary(web) == "Node · node_modules, .next")
        let mixed = project("kit", age: 0, folders: [(".build", 10), ("build", 5), ("node_modules", 1)], kinds: [.swiftPackage, .node, .xcode])
        #expect(RoomDeveloperBuildFolders.summary(mixed) == "Swift and Node · .build, build and more")
        #expect(RoomDeveloperBuildFolders.meta(mixed, now: now).hasSuffix(" to clear · today"))
    }

    @Test func rowsMergeBuildFoldersWithWhatGradleAndXcodeKeepElsewhere() {
        let scan = DeveloperProjectScan(projects: [project("app", age: 50, folders: [("build", 3_000_000_000)], kinds: [.gradle]),
                                                   project("site", age: 1, folders: [("node_modules", 1_000_000_000)])], partial: false)
        let reviewed = DeveloperProject(root: "/Users/sample/code/app", name: "app", gradle: ("8.10", "bin"))
        let derived = DeveloperToolchainResource(path: "/Users/sample/Library/Developer/Xcode/DerivedData/app-x", kind: .derivedData,
            version: "app", workspacePath: "/Users/sample/code/app", workspacePresent: true, bytes: 2_000_000_000, partial: false)
        let summary = RoomDeveloperRooms.summarize(projects: [reviewed], artifacts: [derived], scanPartial: false)
        let rows = RoomDeveloperLargest.projects(summary, scan: scan, now: now)
        #expect(rows.map(\.name) == ["app", "site"])
        // A suggested project leads even when another is larger.
        let big = DeveloperProjectScan(projects: [project("old", age: 90, folders: [("node_modules", 1)]),
                                                  project("huge", age: 1, folders: [("node_modules", 9_000_000_000)])], partial: false)
        #expect(RoomDeveloperLargest.projects(nil, scan: big, now: now).map(\.name) == ["old", "huge"])
        #expect(rows[0].buildBytes == 3_000_000_000 && rows[0].bytes == 5_000_000_000)
        #expect(rows[1].buildBytes == 1_000_000_000)
    }

    @Test func movedFoldersLeaveThePage() {
        let scan = DeveloperProjectScan(projects: [project("web", age: 50, folders: [("node_modules", 2), (".next", 1)])], partial: false)
        let after = RoomDeveloperBuildFolders.removing(["/Users/sample/code/web/node_modules"], from: scan)
        #expect(after.projects.first?.buildFolders.map(\.name) == [".next"])
    }

    @Test func tickedBuildFoldersPutReviewInTheDockWithRescanBeside() {
        #expect(RoomDeveloperDock.make(scanning: false, needsHome: false, hasResults: true, reviewBytes: 4)
                == .init(main: .review(4), rescan: true))
        #expect(RoomDeveloperDock.make(scanning: true, needsHome: false, hasResults: true, reviewBytes: 4) == .init(main: .stop))
        #expect(RoomDeveloperDock.make(scanning: false, needsHome: false, hasResults: true) == .init(main: .scan(again: true)))
    }

    @Test func theHeadlineNamesWhatCanBeCleared() {
        let headline = RoomDeveloperHeadline(inUse: 1_000_000_000, buildFolders: 9_000_000_000)
        let page = RoomDeveloperPage.make(headline: headline, worktreesBytes: 0, projects: 3, clearable: 6_000_000_000)
        #expect(page.headline == RoomHeadline(figure: "10 GB", words: "of developer files"))
        #expect(page.supporting == "6 GB of build folders in projects untouched for a month")
        #expect(page.parts.map(\.kind) == [.projects])
    }
}
