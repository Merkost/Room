import Testing
@testable import RoomApp

@Suite("Overview: scan everything") @MainActor
struct RoomScanEverythingTests {
    @MainActor private final class Engine {
        var reading = RoomScanEverything.Reading()
        var blocked: String?
        var starts = 0
        var stops = 0
        var source: RoomScanEverything.Source {
            .init(unavailable: { self.blocked },
                  start: { self.starts += 1; self.reading.running = true },
                  stop: { self.stops += 1; self.reading.running = false },
                  read: { _ in self.reading })
        }
    }

    @Test("One press starts every engine that can run, and says why the others cannot")
    func startsWhatCanRun() {
        let caches = Engine(), developer = Engine()
        developer.blocked = "Add a folder in Developer"
        let scan = RoomScanEverything()
        scan.sources = [.caches: caches.source, .developer: developer.source]

        scan.start()
        scan.start()

        #expect(caches.starts == 1 && developer.starts == 0)
        #expect(scan.isRunning)
        #expect(scan.tiles.map(\.state) == [.reading(fraction: nil), .skipped])
        #expect(scan.tiles.last?.detail == "Add a folder in Developer")
        #expect(RoomScanTile.progress(scan.tiles) == "0 of 1 read")
    }

    @Test("Rooms fill only as far as the engine counted, and finish with its figure")
    func fillsFromCounts() {
        let caches = Engine()
        let scan = RoomScanEverything()
        scan.sources = [.caches: caches.source]
        scan.start()

        caches.reading.fraction = 0.5
        #expect(scan.tiles.first?.fill == 0.5)
        caches.reading = .init(finished: true, figure: "12 GB could go")
        #expect(scan.tiles.first?.state == .done)
        #expect(scan.tiles.first?.value == "12 GB could go")
        #expect(scan.tiles.first?.fill == 1)
        #expect(!scan.isRunning && scan.isPresented)
        scan.dismiss()
        #expect(!scan.isPresented)
    }

    @Test("Waiting on a folder panel keeps the scan open; declining it reads as not read")
    func waitsForThePerson() {
        let disk = Engine()
        let scan = RoomScanEverything()
        scan.sources = [.disk: disk.source]
        scan.start()

        disk.reading = .init(pending: true)
        #expect(scan.isRunning)
        #expect(scan.tiles.first?.detail == "Waiting for you")
        disk.reading = .init()
        #expect(!scan.isRunning)
        #expect(scan.tiles.first?.state == .skipped)
    }

    @Test("A finished room keeps its result, and the board puts itself away")
    func finishedRoomsStayFinished() async throws {
        let memory = Engine(), caches = Engine()
        let scan = RoomScanEverything()
        scan.sources = [.memory: memory.source, .caches: caches.source]
        scan.start()
        memory.reading = .init(finished: true, figure: "9 GB in use")
        scan.settle()

        memory.reading = .init(running: true)
        #expect(scan.tiles.last?.state == .done)
        #expect(scan.tiles.last?.value == "9 GB in use")
        scan.stop()
        #expect(memory.stops == 0 && caches.stops == 1)
        scan.settle()

        #expect(await RoomTestWait.until(timeout: .seconds(10)) { !scan.isPresented })
    }

    @Test("A read that came to nothing says why instead of showing a figure")
    func problemsAreNotDone() {
        let caches = Engine()
        let scan = RoomScanEverything()
        scan.sources = [.caches: caches.source]
        scan.start()
        caches.reading = .init(finished: true, problem: "Couldn’t read", figure: "All clear")

        #expect(scan.tiles.first?.state == .skipped)
        #expect(scan.tiles.first?.detail == "Couldn’t read")
        #expect(scan.tiles.first?.value == nil)
    }

    @Test("Stop stops only what is still running")
    func stopStopsRunningEngines() {
        let caches = Engine(), memory = Engine()
        let scan = RoomScanEverything()
        scan.sources = [.caches: caches.source, .memory: memory.source]
        scan.start()
        memory.reading = .init(finished: true)

        scan.stop()

        #expect(caches.stops == 1 && memory.stops == 0)
        #expect(scan.tiles.map(\.state) == [.stopped, .done])
        #expect(!scan.isRunning)
    }
}
