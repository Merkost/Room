import Foundation
import Testing
@testable import RoomCore

@Suite("Developer project reference")
struct DeveloperRoomsTests {
    @Test("Project parsers, DMR-C61–75")
    func parsers() throws {
        let wrapperText = "distributionBase=GRADLE_USER_HOME\ndistributionUrl=https\\://services.gradle.org/distributions/gradle-8.9-bin.zip\n"
        // DMR-C61_WrapperParses
        #expect(RoomDevParse.wrapper(wrapperText).map { $0.version + "-" + $0.type } == "8.9-bin")
        // DMR-C62_WrapperDropsHostAndToken
        #expect(RoomDevParse.wrapper("distributionUrl=https\\://user:tok@corp.example/g/gradle-8.10.2-all.zip?x=1").map { $0.version } == "8.10.2")
        // DMR-C63_WrapperNonstandardIsNil
        #expect(RoomDevParse.wrapper("distributionUrl=https\\://x/dist/custom.zip") == nil)
        let toml = """
        [versions]
        agp = "8.7.2"
        kotlin = "2.1.0" # comment
        ndk = "27.1.12297006"
        [libraries]
        foo = { module = "a:b", version = "9.9.9" }
        [plugins]
        android-application = { id = "com.android.application", version.ref = "agp" }
        kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
        """
        let catalog = RoomDevParse.versionCatalog(toml)!
        // DMR-C64_CatalogResolvesVersionRef
        #expect(catalog.agp == "8.7.2" && catalog.kotlin == "2.1.0" && catalog.declaresMultiplatform)
        // DMR-C65_CatalogLibrariesIgnored
        #expect(!catalog.versions.values.contains("9.9.9"))
        let indirect = RoomDevParse.versionCatalog("[versions]\nandroidGradle = \"8.5.0\"\n[plugins]\nandroid-library = { id = \"com.android.library\", version.ref = \"androidGradle\" }\n")!
        // DMR-C66_PluginIdDecidesNotKeyName
        #expect(indirect.agp == "8.5.0")
        let kmpScript = """
        plugins { alias(libs.plugins.kotlin.multiplatform) }
        kotlin {
            androidTarget()
            iosArm64()
            iosSimulatorArm64()
            sourceSets { iosMain.dependencies { } }
        }
        android { ndkVersion = libs.versions.ndk.get() }
        """
        let kmp = RoomDevParse.buildScript(kmpScript, catalog: catalog)!
        // DMR-C67_KMPWithAppleTargets
        #expect(kmp.appliesMultiplatform && kmp.appleNativeTargets && kmp.ndk == "27.1.12297006")
        let jvm = RoomDevParse.buildScript(#"plugins { kotlin("jvm") version "2.0.21" }"# + "\nsourceSets { iosMain { } }\n// iosArm64()\n", catalog: nil)!
        // DMR-C68_JVMOnlyNoNativeTarget
        #expect(jvm.kotlin == "2.0.21" && !jvm.appliesMultiplatform && !jvm.appleNativeTargets)
        // DMR-C69_CommentedTargetIgnored
        #expect(!RoomDevParse.buildScript("/* iosArm64() */ kotlin { }", catalog: nil)!.appleNativeTargets)
        let agpScript = RoomDevParse.buildScript(#"plugins { id("com.android.application") version "8.7.2" apply false }"# + "\nandroid { ndkVersion = \"26.3.11579264\" }", catalog: nil)!
        // DMR-C70_BuildScriptFallback
        #expect(agpScript.agp == "8.7.2" && agpScript.ndk == "26.3.11579264")
        // DMR-C71_OversizeNotParsed
        #expect(RoomDevParse.buildScript(String(repeating: "a", count: 262_145), catalog: nil) == nil)
        // DMR-C72_MalformedNoCrash
        #expect(RoomDevParse.versionCatalog("[versions\nagp = 8.7.2\n= =\n[plugins]\nx = { id = }") != nil)
        // DMR-C73_KonanFolderVersion
        #expect(RoomDevParse.konan("kotlin-native-prebuilt-macos-aarch64-2.1.0") == "2.1.0"
              && RoomDevParse.konan("kotlin-native-prebuilt-macos-aarch64-2.1.20-RC") == "2.1.20-RC" && RoomDevParse.konan("dependencies") == nil)
        let plist = try! PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/Users/k/Projects/suby-kmp/iosApp/iosApp.xcodeproj"], format: .xml, options: 0)
        // DMR-C74_DerivedDataWorkspace
        #expect(RoomDevParse.derivedDataWorkspace(plist) == "/Users/k/Projects/suby-kmp/iosApp/iosApp.xcodeproj")
        // DMR-C75_DerivedDataGarbageNil
        #expect(RoomDevParse.derivedDataWorkspace(Data("nope".utf8)) == nil)
    }

    @Test("Project sizes and the matrix, DMR-C76–92 and C97")
    func summaryAndMatrix() throws {
        let suby = RoomDevProject(root: "/P/suby-kmp", name: "suby-kmp", gradle: ("8.9", "bin"), agp: "8.7.2", kotlin: "2.1.0", multiplatform: true, appleNativeTargets: true, ndk: "27.1.12297006")
        let maytes = RoomDevProject(root: "/P/maytes-mobile", name: "maytes-mobile", gradle: ("8.9", "bin"), agp: "8.7.2", kotlin: "2.1.0", multiplatform: true, appleNativeTargets: true, ndk: nil)
        let standup = RoomDevProject(root: "/P/standupbot", name: "standupbot", gradle: ("8.10", "bin"), agp: nil, kotlin: "2.0.21", multiplatform: false, appleNativeTargets: false, ndk: nil)
        let artifacts = [
            RoomDevArtifact(path: "/G/wrapper/dists/gradle-8.9-bin", kind: .gradle, version: "8.9-bin", gradleType: "bin", bytes: 200_000_000, partial: false),
            RoomDevArtifact(path: "/G/wrapper/dists/gradle-7.6.4-bin", kind: .gradle, version: "7.6.4-bin", gradleType: "bin", bytes: 150_000_000, partial: false),
            RoomDevArtifact(path: "/K/kotlin-native-prebuilt-macos-aarch64-2.1.0", kind: .kotlinNative, version: "2.1.0", bytes: 1_100_000_000, partial: false),
            RoomDevArtifact(path: "/K/kotlin-native-prebuilt-macos-aarch64-2.0.21", kind: .kotlinNative, version: "2.0.21", bytes: 900_000_000, partial: false),
            RoomDevArtifact(path: "/S/ndk/27.1.12297006", kind: .ndk, version: "27.1.12297006", bytes: 3_400_000_000, partial: false),
            RoomDevArtifact(path: "/D/suby-abc", kind: .derivedData, version: "suby-abc", workspacePath: "/P/suby-kmp/iosApp/iosApp.xcodeproj", bytes: 5_000_000_000, partial: false),
            RoomDevArtifact(path: "/D/OldSpike-fhq", kind: .derivedData, version: "OldSpike-fhq", workspacePath: "/P/OldSpike/OldSpike.xcodeproj", bytes: 2_000_000_000, partial: false),
            RoomDevArtifact(path: "/D/Other-zzz", kind: .derivedData, version: "Other-zzz", workspacePath: "/Elsewhere/Other.xcodeproj", bytes: 300_000_000, partial: false),
        ]
        let summary = RoomDeveloperRooms.summarize(projects: [standup, maytes, suby], artifacts: artifacts, scanPartial: false,
                                                   exists: { $0.hasPrefix("/Elsewhere") })
        // DMR-C76_SharedCountedOnce
        #expect(summary.pinnedBytes == 200_000_000 + 1_100_000_000 + 3_400_000_000 + 5_000_000_000)
        // DMR-C77_SharedAmountStated
        #expect(summary.sharedBytes == 1_300_000_000)
        // DMR-C78_RowsSumAtLeastTotal
        #expect(summary.rows.reduce(Int64(0)) { $0 + $1.totalBytes } >= summary.pinnedBytes)
        // DMR-C79_LaterRowHatchesShared
        #expect(summary.rows.first?.project.name == "suby-kmp"
              && summary.rows[1].segments.allSatisfy { $0.countedEarlier } && summary.rows[0].segments.allSatisfy { !$0.countedEarlier })
        // DMR-C80_JVMOnlyPinsNoKonan
        #expect(summary.rows.first { $0.project.name == "standupbot" }?.segments.isEmpty == true)
        // DMR-C81_PinnedByCountsProjectsWithBytes
        #expect(summary.pinnedProjectCount == 2)
        let reasons = Dictionary(uniqueKeysWithValues: summary.orphans.map { ($0.artifact.version, $0.reason) })
        // DMR-C82_UnpinnedGradleListed
        #expect(reasons["7.6.4-bin"] == .pinnedByNone && reasons["8.9-bin"] == nil)
        // DMR-C83_GoneProjectFolderReason
        #expect(reasons["OldSpike-fhq"] == .projectFolderGone && reasons["Other-zzz"] == .pinnedByNone)
        // DMR-C84_OrphanTotal
        #expect(summary.orphanBytes == 150_000_000 + 900_000_000 + 2_000_000_000 + 300_000_000)
        // DMR-C85_OrphansLargestFirst
        #expect(summary.orphans.map(\.artifact.bytes) == summary.orphans.map(\.artifact.bytes).sorted(by: >))
        // DMR-C86_PartialArtifactMakesLowerBound
        #expect(RoomDeveloperRooms.summarize(projects: [suby], artifacts: [RoomDevArtifact(path: "/x", kind: .ndk, version: "27.1.12297006", bytes: 1, partial: true)], scanPartial: false, exists: { _ in true }).partial)
        // DMR-C87_KindLine
        #expect(summary.rows.first?.kindLine == "Android, iOS, shared Kotlin" && summary.rows.last?.kindLine == "Kotlin JVM")
        // DMR-C88_SiblingPathNotInside
        #expect(!RoomDeveloperRooms.contains("/P/suby-kmp-old/x", in: "/P/suby-kmp"))

        let matrix = RoomDevMatrix.rows(summary)
        let standupRow = matrix.first { $0.title == "standupbot" }!
        // DMR-C89_MatrixJVMCell
        #expect(standupRow.cells[2].text == "2.0.21 JVM" && standupRow.cells[2].tooltip == "JVM only: no native toolchain on disk")
        // DMR-C90_MatrixSharedShaded
        #expect(matrix.first { $0.title == "suby-kmp" }!.cells[0].shaded && !standupRow.cells[0].shaded)
        // DMR-C91_MatrixWrapperNotOnDisk
        #expect(standupRow.cells[0].text == "8.10" && standupRow.cells[0].tooltip == "Not on this Mac")
        // DMR-C92_MatrixOrphanRowLast
        #expect(matrix.last?.title == "Not in any room" && matrix.last?.cells[0].text == "7.6.4-bin")
        // DMR-C97_ArtifactKeyHasNoPath
        #expect(!artifacts[0].key.contains("/"))
    }
}
