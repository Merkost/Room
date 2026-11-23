import CoreGraphics
import RoomCore
import Testing
@testable import RoomApp

struct RoomMapMotionTests {
    @MainActor @Test func stepInAndOutUseTheSameTile() throws {
        let size = CGSize(width: 600, height: 400)
        let bounds = CGRect(origin: .zero, size: size)
        let folder = node("Projects", children: [node("Projects/Sources"), node("Projects/Tests")])
        let root = node("", children: [folder, node("Downloads")])
        let rootLayer = RoomMapLayer.make(level: root, size: size)
        let folderLayer = RoomMapLayer.make(level: folder, size: size)
        let tile = try #require(rootLayer.items.first { $0.id == folder.relativePath }?.drawRect)
        let enter = RoomMapStep(generation: 1, previous: root, selection: nil, destination: folder.relativePath, into: true)
        let exit = RoomMapStep(generation: 2, previous: folder, selection: nil, destination: root.relativePath, into: false)
        let entering = try #require(enter.transforms(previousLayer: rootLayer, currentLayer: folderLayer, size: size))
        let exiting = try #require(exit.transforms(previousLayer: folderLayer, currentLayer: rootLayer, size: size))
        #expect(entering.incoming == exiting.outgoing)
        #expect(entering.outgoing == exiting.incoming)
        #expect(bounds.applying(entering.incoming) == tile)
        let expanded = tile.applying(entering.outgoing)
        #expect(abs(expanded.width - bounds.width) < 0.001)
        #expect(abs(expanded.height - bounds.height) < 0.001)
    }

    @Test func deepAnchorUsesTheNearestVisibleAncestor() throws {
        let folder = node("Projects", children: [node("Projects/Sources")])
        let root = node("", children: [folder, node("Projects-old")])
        let layer = RoomMapLayer.make(level: root, size: CGSize(width: 600, height: 400))
        let source = try #require(layer.items.first { $0.id == "Projects/Sources" })
        #expect(RoomMapStepGeometry.anchor(for: "Projects/Sources/Child", in: layer) == source.drawRect)
        #expect(RoomMapStepGeometry.anchor(for: "Projects-archive/Child", in: layer) == nil)
        #expect(RoomMapStepGeometry.fit(tile: .zero, in: CGSize(width: 600, height: 400)) == nil)
    }

    @Test(arguments: [false, true]) func compareKeepsDirectManipulationAndKeyboardInstant(reduced: Bool) {
        var divider = RoomCompareDivider()
        divider.reduceMotion = reduced
        #expect(divider.press(atPercent: 35) == (reduced ? .instant : .jump120))
        #expect(divider.drag(toPercent: 55) == .instant && divider.position == 55)
        #expect(divider.release(velocityPtPerMS: 0.5) == .instant && divider.position == 55)
        #expect(divider.release(velocityPtPerMS: 0.51) == (reduced ? .instant : .glide360))
        #expect(divider.position == 100)
        #expect(divider.key(.left) == .instant && divider.position == 95)
        #expect(divider.release(velocityPtPerMS: -0.51) == (reduced ? .instant : .glide360))
        #expect(divider.position == 0)
    }

    @Test func mapReadoutPrefersHoverAndReturnsToSelection() throws {
        let level = node("Projects", children: [node("Projects/Builds"), node("Projects/Sources")])
        let layer = RoomMapLayer.make(level: level, size: CGSize(width: 600, height: 400))
        let hovered = try #require(layer.items.first { $0.id == "Projects/Builds" })
        func readout(_ item: RoomMapItem?, hidden: Bool = false) -> RoomMapReadoutContent {
            .make(level: level, hovered: item, selectedPath: "Projects/Sources", hidden: hidden,
                  showsHint: true, format: { "\($0) bytes" })
        }
        #expect(readout(hovered).title == "Builds")
        #expect(readout(hovered).detail?.contains("of Projects") == true)
        #expect(readout(nil).title == "Sources")
        #expect(readout(hovered, hidden: true) == .init(title: "Name hidden", detail: "Size hidden"))
        #expect(RoomMapReadoutContent.make(level: level, hovered: hovered, selectedPath: "Projects/Sources",
                                          hidden: false, showsHint: true, showsCleanupTarget: true,
                                          format: { String($0) }).title == "Sources")
        #expect(RoomMapReadoutContent.make(level: level, hovered: hovered, selectedPath: nil,
                                          hidden: false, showsHint: true, showsCleanupTarget: true,
                                          format: { String($0) }).title == "Projects")
        let home = node("", children: [level, node("Pictures")])
        let rootReadout = RoomMapReadoutContent.make(level: home, hovered: hovered, selectedPath: nil,
                                                     hidden: false, showsHint: true, format: { String($0) })
        #expect(rootReadout.detail?.hasSuffix("of \(home.name)") == true)
        #expect(RoomMapReadoutContent.make(level: level, hovered: nil, selectedPath: "Projects-old/Builds",
                                          hidden: false, showsHint: true, format: { String($0) }).isHint)
    }

    private func node(_ path: String, children: [RoomTreeNode] = []) -> RoomTreeNode {
        RoomTreeNode(name: path.split(separator: "/").last.map(String.init) ?? path,
                     relativePath: path, allocatedBytes: Int64(max(1, children.count)) * 4_096,
                     fileCount: 1, kindBytes: [:], isPartial: false, isDirectory: true, children: children, other: nil)
    }
}
