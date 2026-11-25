import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

private struct CaptureError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) { errorDescription = message }
}

private actor RecordingState {
    private var started = false
    private var finished = false
    private var failure: String?

    func markStarted() { started = true }
    func markFinished() { finished = true }
    func markFailed(_ message: String) { failure = message }

    func wait(until target: Target) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let failure { throw CaptureError(failure) }
            if target == .start ? started : finished { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CaptureError("ScreenCaptureKit timed out waiting for the recording to \(target.rawValue).")
    }

    func hold(for seconds: Double) async throws {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if let failure { throw CaptureError(failure) }
            if finished { throw CaptureError("The fixture recording ended early.") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    enum Target: String { case start, finish }
}

private final class RecordingDelegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    let state = RecordingState()

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { [state] in await state.markStarted() }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { [state] in await state.markFinished() }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        fail(error)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        fail(error)
    }

    private func fail(_ error: any Error) {
        let message = error.localizedDescription
        Task { [state] in await state.markFailed(message) }
    }
}

@main
@MainActor
struct RoomFixtureCapture {
    private static let fixtureBundle = "dev.merkost.room.screenshot-fixture"
    private static let fixtureTitles: Set<String> = ["Room Screenshot Fixture", "Overview", "Disk Map", "Caches", "Developer", "Memory", "History", "Settings"]

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        if arguments.isEmpty || arguments == ["--help"] {
            print("""
            Usage
              capture-window preflight
              capture-window list <fixture-pid>
              capture-window png <fixture-pid> <window-id> <new-output.png> [--include-child-windows]
              capture-window record <fixture-pid> <window-id> <seconds> <new-output.mov> [--include-child-windows]
            """)
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError("Screen Recording access is unavailable. No capture or permission request was started.")
        }
        if arguments == ["preflight"] {
            print("Screen Recording access is available to this process.")
            return
        }
        // A desktop-independent window filter queries the WindowServer for its display geometry.
        _ = NSApplication.shared
        let includesChildWindows = arguments.last == "--include-child-windows"
        let arguments = includesChildWindows ? Array(arguments.dropLast()) : arguments
        guard arguments.count >= 2, let pid = Int32(arguments[1]), pid > 0 else {
            throw CaptureError("Supply the process ID of the owned Room screenshot fixture.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let matches = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.owningApplication?.bundleIdentifier == fixtureBundle
                && $0.title.map(fixtureTitles.contains) == true && $0.isOnScreen
        }
        if arguments[0] == "list", arguments.count == 2 {
            guard !matches.isEmpty else { throw CaptureError("No matching Room screenshot fixture window for process \(pid).") }
            for window in matches {
                print("\(window.windowID)  \(Int(window.frame.width))×\(Int(window.frame.height))  \(window.title ?? "")")
            }
            return
        }
        guard arguments.count >= 3, let id = UInt32(arguments[2]) else {
            throw CaptureError("Supply the exact window ID from the fixture list.")
        }
        guard let window = matches.first(where: { $0.windowID == id }) else {
            throw CaptureError("Window \(id) is not the specified visible Room screenshot fixture.")
        }
        if arguments[0] == "png", arguments.count == 4 {
            try await capturePNG(window, output: URL(filePath: arguments[3]).standardizedFileURL, includesChildWindows: includesChildWindows)
            return
        }
        guard arguments[0] == "record", arguments.count == 5,
              let seconds = Double(arguments[3]), seconds.isFinite, (16...29).contains(seconds) else {
            throw CaptureError("Record expects the fixture PID, window ID, 16–29 seconds and a new .mov path.")
        }
        try await record(window, seconds: seconds, output: URL(filePath: arguments[4]).standardizedFileURL, includesChildWindows: includesChildWindows)
    }

    private static func capturePNG(_ window: SCWindow, output: URL, includesChildWindows: Bool) async throws {
        let files = FileManager.default
        guard output.pathExtension.lowercased() == "png", !files.fileExists(atPath: output.path) else {
            throw CaptureError("Choose a new .png output file.")
        }
        let directory = output.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(component: ".capture-\(UUID()).png")
        defer { try? files.removeItem(at: temporary) }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = includesChildWindows
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CaptureError("Could not prepare the fixture PNG.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError("Could not finish the fixture PNG.") }
        try files.moveItem(at: temporary, to: output)
        print(output.path)
    }

    private static func record(_ window: SCWindow, seconds: Double, output: URL, includesChildWindows: Bool) async throws {
        let files = FileManager.default
        guard output.pathExtension.lowercased() == "mov", !files.fileExists(atPath: output.path) else {
            throw CaptureError("Choose a new .mov output file.")
        }
        let directory = output.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(component: ".capture-\(UUID()).mov")
        defer { try? files.removeItem(at: temporary) }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let content = filter.contentRect.size
        guard content.width.isFinite, content.height.isFinite, content.width > 0, content.height > 0 else {
            throw CaptureError("ScreenCaptureKit reported an invalid fixture window size.")
        }
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = 1920
        streamConfiguration.height = 1080
        let frameWidth = CGFloat(streamConfiguration.width)
        let frameHeight = CGFloat(streamConfiguration.height)
        let scale = min(frameWidth / content.width, frameHeight / content.height)
        let width = (content.width * scale / 2).rounded(.down) * 2
        let height = (content.height * scale / 2).rounded(.down) * 2
        streamConfiguration.destinationRect = CGRect(
            x: (frameWidth - width) / 2,
            y: (frameHeight - height) / 2,
            width: width,
            height: height
        )
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfiguration.scalesToFit = true
        streamConfiguration.preservesAspectRatio = true
        let backdrop = CGColor(red: 0.08, green: 0.10, blue: 0.11, alpha: 1)
        defer { withExtendedLifetime(backdrop) {} }
        streamConfiguration.backgroundColor = backdrop
        streamConfiguration.ignoreGlobalClipSingleWindow = true
        streamConfiguration.ignoreShadowsSingleWindow = true
        streamConfiguration.includeChildWindows = includesChildWindows
        streamConfiguration.capturesAudio = false
        streamConfiguration.captureMicrophone = false
        streamConfiguration.showsCursor = true
        streamConfiguration.colorSpaceName = CGColorSpace.itur_709

        let delegate = RecordingDelegate()
        let configuration = SCRecordingOutputConfiguration()
        configuration.outputURL = temporary
        guard configuration.availableVideoCodecTypes.contains(.h264),
              configuration.availableOutputFileTypes.contains(.mov) else {
            throw CaptureError("This Mac does not expose H.264 in a QuickTime container for window capture.")
        }
        configuration.videoCodecType = .h264
        configuration.outputFileType = .mov
        let recording = SCRecordingOutput(configuration: configuration, delegate: delegate)
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: delegate)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        do {
            try await delegate.state.wait(until: .start)
            FileHandle.standardOutput.write(Data("Recording owned Room fixture window \(window.windowID).\n".utf8))
            try await delegate.state.hold(for: seconds)
            try await stream.stopCapture()
            try await delegate.state.wait(until: .finish)
        } catch {
            try? await stream.stopCapture()
            throw error
        }
        try files.moveItem(at: temporary, to: output)
        print(output.path)
    }
}
