import Testing
@testable import RoomApp
@testable import RoomCore

@MainActor struct RoomDeveloperPageTests {
    @Test func headlineAddsEveryPartAndNamesWhatNothingUses() {
        let headline = RoomDeveloperHeadline(inUse: 85_000_000_000, unreferenced: 14_000_000_000,
                                             devices: 27_000_000_000, toolStorage: 20_000_000_000, aiTools: 28_000_000_000)
        let page = RoomDeveloperPage.make(headline: headline, worktreesBytes: 6_000_000_000, projects: 5)
        #expect(page.headline == RoomHeadline(figure: "180 GB", words: "of developer files"))
        #expect(page.supporting == "14 GB that nothing uses")
        #expect(page.parts.map(\.kind) == [.projects, .devices, .storage, .aiTools, .worktrees])
    }

    @Test func emptyPartsAreLeftOutAndNothingIsNotZeroGigabytes() {
        let page = RoomDeveloperPage.make(headline: .init(), worktreesBytes: 0, projects: 1)
        #expect(page.parts.isEmpty && page.headline.figure == nil && page.supporting == "1 project")
    }

    @Test func chipsCountProjectsPerVersionAndFlagUnusedOnes() {
        let projects = [
            DeveloperProject(root: "/p/a", name: "a", gradle: ("8.7", "bin"), kotlin: "2.0"),
            DeveloperProject(root: "/p/b", name: "b", gradle: ("8.7", "all")),
            DeveloperProject(root: "/p/c", name: "c", gradle: ("8.2", "bin")),
        ]
        let old = DeveloperToolchainResource(path: "/g/8.0-bin", kind: .gradle, version: "8.0-bin",
                                             bytes: 1_200_000_000, partial: false)
        let summary = RoomDeveloperRooms.summarize(projects: projects, artifacts: [old], scanPartial: false)
        let chips = RoomDeveloperVersionChip.make(projects: projects, summary: summary)
        #expect(chips.map(\.label) == ["Gradle 8.7", "Gradle 8.2", "Kotlin 2.0", "Gradle 8.0"])
        #expect(chips.first?.detail == "2 projects" && chips.first?.projects == ["a", "b"])
        #expect(chips.last?.unused == true && chips.last?.detail == "unused, \(RoomFormat.gb(1_200_000_000))")
    }
}
