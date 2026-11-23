import Foundation
import Testing
@testable import RoomCore

@Suite("Disk Map streaming reference")
struct RoomTreeBuilderTests {
    let GB: Int64 = 1_000_000_000
    func gb(_ x: Double) -> Int64 { Int64((x * 1e9).rounded()) }
    func fmt(_ b: Int64) -> String { String(format: "%.1f GB", Double(b) / 1e9) }
    func spoken(_ b: Int64) -> String { String(format: "%.1f gigabytes", Double(b) / 1e9) }
    let day: TimeInterval = 86_400
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: deterministic RNG and raw trees
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
    indirect enum Raw {
        case file(String, Int64, String, Bool)          // name, bytes, kind, partial
        case dir(String, [Raw], Bool)                   // name, children, own partial
        var name: String { switch self { case .file(let n, _, _, _), .dir(let n, _, _): n } }
    }
    let kindsRaw = StorageKind.allCases.map(\.rawValue)
    func randomTree(_ rng: inout SplitMix, depth: Int = 0, name: String = "root") -> Raw {
        let count = depth == 0 ? Int.random(in: 30...70, using: &rng) : Int.random(in: 0...(depth < 3 ? 30 : 8), using: &rng)
        var kids: [Raw] = []
        for i in 0..<count {
            let n = "n\(depth)_\(i)_\(Int.random(in: 0...9, using: &rng))"
            if depth < 6 && Int.random(in: 0...(4 + 6 * depth), using: &rng) == 0 { kids.append(randomTree(&rng, depth: depth + 1, name: n)) }
            else {
                let big = Int.random(in: 0...20, using: &rng) == 0
                let bytes = big ? Int64.random(in: 1...40_000_000_000, using: &rng) : Int64.random(in: 0...200_000_000, using: &rng)
                kids.append(.file(n, bytes, kindsRaw.randomElement(using: &rng)!, Int.random(in: 0...60, using: &rng) == 0))
            }
        }
        return .dir(name, kids, Int.random(in: 0...80, using: &rng) == 0)
    }
    /// Full unpruned node, the input RoomTreeRetention.prune expects.
    func fullNode(_ raw: Raw, path: String) -> RoomTreeNode {
        switch raw {
        case .file(let n, let b, let k, let p):
            return RoomTreeNode(name: n, relativePath: path, allocatedBytes: b, fileCount: 1, kindBytes: b > 0 ? [k: b] : [:],
                                isPartial: p, isDirectory: false, children: [], other: nil)
        case .dir(let n, let kids, let p):
            let children = kids.map { fullNode($0, path: RoomTreeBuilder.join(path, $0.name)) }
            var kinds: [String: Int64] = [:]
            for c in children { for (k, v) in c.kindBytes { kinds[k, default: 0] += v } }
            return RoomTreeNode(name: n, relativePath: path, allocatedBytes: children.reduce(0) { $0 + $1.allocatedBytes },
                                fileCount: children.reduce(0) { $0 + $1.fileCount }, kindBytes: kinds,
                                isPartial: p || children.contains { $0.isPartial }, isDirectory: true, children: children, other: nil)
        }
    }
    func feed(_ b: inout RoomTreeBuilder, _ raw: Raw) {
        switch raw {
        case .file(let n, let bytes, let k, let p): b.file(n, bytes: bytes, kind: k, partial: p)
        case .dir(let n, let kids, let p):
            b.enterDirectory(n); for k in kids { feed(&b, k) }; b.leaveDirectory(partial: p)
        }
    }
    func build(_ raw: Raw) -> RoomTreeNode {
        guard case .dir(let n, let kids, let p) = raw else { fatalError() }
        var b = RoomTreeBuilder(rootName: n)
        for k in kids { feed(&b, k) }
        return b.finish(partial: p)
    }
    func zeroCounts(_ n: RoomTreeNode) -> RoomTreeNode {
        var c = n; c.other?.itemCount = 0; c.children = n.children.map(zeroCounts); return c
    }
    func allNodes(_ n: RoomTreeNode, depth: Int = 0, _ f: (RoomTreeNode, Int) -> Void) {
        f(n, depth); for c in n.children { allNodes(c, depth: depth + 1, f) }
    }


    @Test func streamingRetentionAndExclusiveKinds() {
        func check(_ name: String, _ condition: Bool) {
            #expect(condition, Comment(rawValue: name))
        }
        // MARK: Kinds (FD-10)
        check("DMC-01_GitHiddenIsHidden", StorageKind.kind(categoryRaw: "systemOther", isHidden: true) == .hidden)
        check("DMC-02_GradleCachesHiddenIsDeveloper", StorageKind.kind(categoryRaw: "cachesBuilds", isHidden: true) == .developer
              && StorageKind.kind(categoryRaw: "agents", isHidden: false) == .developer)
        check("DMC-03_UnknownCategoryIsNotSystem", StorageKind.kind(categoryRaw: "future", isHidden: false) == nil)
        check("DMC-04_DominantTiesByOrder", StorageKind.dominant(["media": 5, "developer": 5]) == .developer
              && StorageKind.dominant([:]) == nil)

        // MARK: Streaming retention
        var rng = SplitMix(state: 42)
        var equal = true, invariant = true, depthOK = true, limitsOK = true, kindsOK = true
        for _ in 0..<150 {
            let raw = randomTree(&rng)
            let streamed = build(raw)
            let pruned = RoomTreeRetention.prune(fullNode(raw, path: ""))
            if zeroCounts(streamed) != zeroCounts(pruned) { equal = false }
            allNodes(streamed) { n, d in
                if n.isDirectory && RoomTreeRetention.keptBytes(n) != n.allocatedBytes { invariant = false }
                if d > RoomTreeRetention.maxDepth { depthOK = false }
                if n.children.count > (RoomTreeRetention.keepPerDepth[d + 1] ?? 0) { limitsOK = false }
                if n.kindBytes.values.reduce(0, +) != n.allocatedBytes { kindsOK = false }
            }
        }
        check("DMC-10_StreamingEqualsPruneOn150RandomTrees", equal)
        check("DMC-11_KeptPlusOtherEqualsBytes", invariant)
        check("DMC-12_DepthCappedAt4", depthOK)
        check("DMC-13_PerDepthLimits40_24_16_12", limitsOK)
        check("DMC-18_KindBytesSumToBytes", kindsOK)

        do {   // 100 equal small files in one folder: 8 kept by the minimum, 92 folded, counted as entries
            var b = RoomTreeBuilder(rootName: "Home")
            b.enterDirectory("big"); b.file("huge", bytes: 100 * GB, kind: "media"); b.leaveDirectory()
            b.enterDirectory("many")
            for i in 0..<100 { b.file(String(format: "f%03d", i), bytes: 1_000, kind: "documents") }
            b.leaveDirectory()
            let root = b.finish()
            let many = root.descendant(at: "many")
            check("DMC-14_OtherCountsDirectEntries", many?.children.count == 24 && many?.other?.itemCount == 76
                  && many?.other?.allocatedBytes == 76_000)
            // Added after mutation run 1 (M01 survived): the first 8 are kept even below 0.2 % of the parent.
            var s = RoomTreeBuilder(rootName: "S")
            s.file("huge", bytes: 1_000_000, kind: "media")
            for i in 0..<10 { s.file("t\(i)", bytes: 10, kind: "media") }
            let small = s.finish()
            check("DMC-14b_FirstEightKeptBelowShare", small.children.count == 8 && small.other?.itemCount == 3)
            // Added after M15 survived: a depth-4 folder counts its direct entries, not the files below them.
            var d4 = RoomTreeBuilder(rootName: "R")
            for n in ["a", "b", "c", "d"] { d4.enterDirectory(n) }
            d4.enterDirectory("sub"); for i in 0..<5 { d4.file("f\(i)", bytes: 1, kind: "system") }; d4.leaveDirectory()
            d4.file("x", bytes: 1, kind: "system"); d4.file("y", bytes: 1, kind: "system")
            for _ in 0..<4 { d4.leaveDirectory() }
            let deep = d4.finish()
            check("DMC-14c_DepthFourOtherCountsDirectEntries", deep.descendant(at: "a/b/c/d")?.other?.itemCount == 3
                  && deep.descendant(at: "a/b/c/d")?.other?.allocatedBytes == 7)
        }
        do {
            var b = RoomTreeBuilder(rootName: "Home")
            b.enterDirectory("a"); b.enterDirectory("b"); b.enterDirectory("c"); b.enterDirectory("d"); b.enterDirectory("e")
            b.enterDirectory("f"); b.file("x", bytes: 5, kind: "system"); b.leaveDirectory(partial: true)
            b.leaveDirectory(); b.leaveDirectory(); b.leaveDirectory(); b.leaveDirectory(); b.leaveDirectory()
            let root = b.finish()
            check("DMC-15_UnreadableBelowDepth4MakesAncestorsPartial", root.isPartial && root.descendant(at: "a/b/c/d")!.isPartial
                  && root.descendant(at: "a/b/c/d")!.other?.isPartial == true && root.descendant(at: "a/b/c/d/e") == nil)
            var c = RoomTreeBuilder(rootName: "Home")
            c.enterDirectory("Projects"); c.enterDirectory("suby"); c.file("a", bytes: 10, kind: "developer")
            let cancelled = c.finish()
            check("DMC-16_FinishClosesOpenFoldersAsPartial", cancelled.isPartial && cancelled.allocatedBytes == 10
                  && cancelled.descendant(at: "Projects/suby")?.isPartial == true)
            var d = RoomTreeBuilder(rootName: "Home")
            d.enterDirectory("Library"); let inner = d.file("x", bytes: 3, kind: "system"); let top = d.leaveDirectory()
            let topFile = d.file(".zshrc", bytes: 1, kind: "hidden")
            check("DMC-17_OnlyTopLevelCompletionsReported", inner == nil && top?.name == "Library" && topFile?.name == ".zshrc")
            var e = RoomTreeBuilder(rootName: "Home")
            e.file("a", bytes: 4_096, kind: "media"); e.file("a-link", bytes: 0, kind: "media")
            let hl = e.finish()
            check("DMC-19_RepeatedHardlinkCountsFileNotBytes", hl.fileCount == 2 && hl.allocatedBytes == 4_096)
        }

    }
}
