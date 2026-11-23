import Foundation
import Testing
@testable import RoomApp

/// DS-7: one formatter. Whole units everywhere, one decimal only on the hero below 100 GB.
@MainActor
struct RoomFormatTests {
    private let us = Locale(identifier: "en_US")

    @Test func wholeGBEverywhere() {
        #expect(RoomFormat.gb(63_730_000_000, hero: false, locale: us) == "64 GB")
        #expect(RoomFormat.gb(430_660_000_000, hero: false, locale: us) == "431 GB")
        #expect(RoomFormat.gb(4_240_000_000, hero: false, locale: us) == "4 GB")
        #expect(RoomFormat.gb(999_700_000, hero: false, locale: us) == "1 GB")
        #expect(RoomFormat.gb(480_300_000, hero: false, locale: us) == "480 MB")
        #expect(RoomFormat.gb(1_240_000_000_000, hero: false, locale: us) == "1.2 TB")
        #expect(RoomFormat.gb(0, hero: false, locale: us) == "0 KB")
        // Memory: binary units, whole except the Memory hero ("29.08 GB" was the bug).
        #expect(RoomFormat.memory(31_224_000_000, hero: false, locale: us) == "29 GB")
        #expect(RoomFormat.memory(51_539_607_552, hero: false, locale: us) == "48 GB")
        for bytes: Int64 in [1_500_000_000, 12_345_678_901, 63_730_000_000, 99_960_000_000, 494_380_000_000] {
            let text = RoomFormat.gb(bytes, hero: false, locale: us)
            #expect(!text.contains("."), "\(text) should be whole")
        }
    }

    @Test func heroDecimalBelow100Only() {
        #expect(RoomFormat.gb(63_730_000_000, hero: true, locale: us) == "63.7 GB")
        #expect(RoomFormat.gb(64_000_000_000, hero: true, locale: us) == "64.0 GB", "the hero keeps its width")
        #expect(RoomFormat.gb(99_940_000_000, hero: true, locale: us) == "99.9 GB")
        #expect(RoomFormat.gb(99_960_000_000, hero: true, locale: us) == "100 GB", "rounding up to 100 drops the decimal")
        #expect(RoomFormat.gb(312_400_000_000, hero: true, locale: us) == "312 GB")
        #expect(RoomFormat.memory(31_224_000_000, hero: true, locale: us) == "29.1 GB")
        #expect(RoomFormat.splitBytes(63_730_000_000, hero: true).unit == "GB")
    }

    @Test func lowerBoundUsesGreaterEqual() {
        #expect(RoomFormat.lowerBound("120 GB") == "≥ 120 GB")
        #expect(RoomFormat.gb(Int64(144_980_000_000), partial: true, locale: us) == "≥ 145 GB")
        #expect(RoomFormat.approx("2 GB") == "≈ 2 GB")
        #expect(RoomDeveloperFormat.whole(1_500_000_000, partial: true).hasPrefix("≥ "))
        let bound = RoomFormat.lowerBound(120_000_000_000)
        #expect(bound == "≥ 120 GB")
    }

    @Test func missingIsWords() {
        #expect(RoomFormat.gb(Int64?.none) == "not measured")
        #expect(RoomFormat.notMeasured == "not measured")
        let missing = RoomFormat.gb(Int64?.none)
        #expect(missing.contains("—") == false)
    }

    @Test func sameValueSameStringAcrossSurfaces() {
        // The review fixture: 63.73 GB free read "64 GB" (pill), "63.73 GB" (hero, sidebar) and "63.56 GB" a minute later.
        let free: Int64 = 63_730_000_000
        let foot = RoomSidebarFoot.make(capacityBytes: 494_380_000_000, freeBytes: free, goalBytes: 50_000_000_000,
                                        volumeName: "Macintosh HD", hidden: false, format: RoomFormat.gb)
        let surfaces = [
            foot.freeText.map { String($0.dropLast(" free".count)) },
            RoomMenuBarFormat.liveDisk(free),
            RoomFormat.gb(free),
            RoomDeveloperFormat.whole(free),
            RoomFormat.split(RoomFormat.gb(free)).value + " GB",
        ]
        #expect(Set(surfaces.compactMap { $0 }).count == 1, "\(surfaces)")
        #expect(RoomFormat.gb(free) == "64 GB")
        #expect(RoomFormat.gb(free, hero: true) == "63.7 GB")
        // A minute later the next sample rounds to the same whole figure everywhere but the hero.
        #expect(RoomFormat.gb(63_560_000_000) == RoomFormat.gb(free))
        #expect(RoomMenuBarFormat.liveMemory(31_224_000_000) == RoomFormat.memory(31_224_000_000, hero: true))
    }
}
