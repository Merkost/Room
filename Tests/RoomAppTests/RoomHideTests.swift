import Foundation
import Testing
@testable import RoomApp

struct RoomHideTests {
    @Test func figureAndNameKeepPunctuationAndUnits() {
        let hide = RoomHideState(isOn: true)
        #expect(RoomHideMask.display("≥ 21.6 GB", kind: .figure, hide: hide) == "≥ ••.• GB")
        #expect(RoomHideMask.display("~/Build 2", kind: .name, hide: hide) == "~/••••• •")
        #expect(RoomHideMask.display("≥ 21.6 GB", kind: .figure, hide: .off) == "≥ 21.6 GB")
    }

    @Test func reduceMotionMasksAtOnce() {
        #expect(RoomHideMask.maskedCharacters(elapsedMS: 0, total: 3, fullMotion: false) == 3)
        #expect(RoomHideMask.duration("312 GB", kind: .figure, fullMotion: false) == 0)
        #expect(RoomHideMask.maskedCharacters(elapsedMS: 21, total: 3, fullMotion: true) == 0)
        #expect(RoomHideMask.maskedCharacters(elapsedMS: 22, total: 3, fullMotion: true) == 1)
        #expect(RoomHideMask.remainingMasked(elapsedMS: 44, total: 3, fullMotion: true) == 1)
        #expect(RoomHideMask.duration("312 GB", kind: .figure, fullMotion: true) == 66)
    }

    @Test func accessibleLabelsAndPasteboardDoNotLeakMaskedValues() {
        let hide = RoomHideState(isOn: true)
        #expect(RoomHideSpeech.value("312 GB", hide: hide) == "hidden")
        #expect(RoomHideSpeech.labelled("Free", value: "312 GB", labelIsName: false, hide: hide) == "Free, hidden")
        #expect(RoomHideSpeech.labelled("Secret Project", value: "21 GB", labelIsName: true, hide: hide) == "Room, hidden")
        #expect(RoomHideSpeech.pasteboard("/Secret Project", hide: hide) == nil)
    }

    @Test func peekNeverChangesToggleState() {
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        var peek = RoomHidePeek()
        _ = peek.press(at: start)
        let early = peek.holdElapsed(at: start.addingTimeInterval(0.279), isOn: true)
        let held = peek.holdElapsed(at: start.addingTimeInterval(0.280), isOn: true)
        let released = peek.release(at: start.addingTimeInterval(1))
        #expect(early == .none && held == .beginPeek && released == .endPeek && !peek.peeking)
    }

    @Test func interruptedHoldNeverToggles() {
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        var peek = RoomHidePeek()
        _ = peek.press(at: start)
        _ = peek.holdElapsed(at: start.addingTimeInterval(1), isOn: true)
        let cancel = peek.cancel()
        let release = peek.release(at: start.addingTimeInterval(2))
        #expect(cancel == .endPeek && release == .none)
    }

    @MainActor @Test func hidePersistsAcrossLaunch() throws {
        let suite = "RoomHideTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let control = RoomHideControl(defaults: defaults)
        #expect(control.state == .off)
        control.toggle()
        #expect(defaults.bool(forKey: RoomHideControl.preferenceKey))
        control.beginPress()
        control.cancelPeek()
        let relaunched = RoomHideControl(defaults: defaults)
        #expect(relaunched.state.isOn && !relaunched.state.isPeeking)
    }
}
