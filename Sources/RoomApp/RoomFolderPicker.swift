import AppKit
import Foundation

/// Native folder approval uses one presenter across storage and developer reviews.
@MainActor
final class RoomNativeFolderPicker {
    static let shared = RoomNativeFolderPicker()
    private var panel: NSOpenPanel?

    func choose(title: String, message: String, prompt: String, initialURL: URL?, allowsFiles: Bool = false) async -> URL? {
        guard panel == nil else { panel?.makeKeyAndOrderFront(nil); return nil }
        return await withCheckedContinuation { continuation in
            let chooser = NSOpenPanel()
            panel = chooser
            chooser.title = title
            chooser.message = message
            chooser.prompt = prompt
            chooser.canChooseDirectories = true
            chooser.canChooseFiles = allowsFiles
            chooser.allowsMultipleSelection = false
            chooser.canCreateDirectories = false
            chooser.showsHiddenFiles = true
            chooser.directoryURL = initialURL
            let completion: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self, weak chooser] response in
                self?.panel = nil
                continuation.resume(returning: response == .OK ? chooser?.url : nil)
            }
            if var presenter = NSApp.windows.first(where: { $0.identifier?.rawValue == "RoomPrimaryWindow" && $0.isVisible }) {
                while let attached = presenter.attachedSheet { presenter = attached }
                chooser.beginSheetModal(for: presenter, completionHandler: completion)
            } else { chooser.begin(completionHandler: completion) }
        }
    }
}
