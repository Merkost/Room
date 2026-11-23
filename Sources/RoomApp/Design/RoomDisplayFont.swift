import CoreText
import Foundation

/// The bundled display face (Fraunces, SIL OFL 1.1; licence beside it). Registration exists but nothing calls it yet:
/// no screen uses the face until the display moments land (DS-6).
enum RoomDisplayFont {
    static let fileName = "Fraunces-Variable"
    static let fileExtension = "ttf"
    static let licenceFileName = "OFL-Fraunces"

    /// The font file in the app bundle (Contents/Resources) or, for SwiftPM builds and tests, the resource bundle.
    static func fontURL(in bundles: [Bundle] = candidateBundles) -> URL? { url(licence: false, in: bundles) }

    /// The licence text that must ship beside the font.
    static func licenceURL(in bundles: [Bundle] = candidateBundles) -> URL? { url(licence: true, in: bundles) }

    /// Registers the font for this process only. Returns true when it is registered (or already was).
    @discardableResult
    static func register() -> Bool {
        guard let url = fontURL() else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        if let error = error?.takeRetainedValue(), CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue { return true }
        return false
    }

    /// `RoomCopy.bundle` finds the SwiftPM resource bundle without `Bundle.module`, which traps in a script-built app that never ships it.
    private static var candidateBundles: [Bundle] { [Bundle.main, RoomCopy.bundle] }

    private static func url(licence: Bool, in bundles: [Bundle]) -> URL? {
        let name = licence ? licenceFileName : fileName
        let ext = licence ? "txt" : fileExtension
        for bundle in bundles {
            for subdirectory in [nil, "Fonts"] as [String?] {
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) { return url }
            }
        }
        return nil
    }
}
