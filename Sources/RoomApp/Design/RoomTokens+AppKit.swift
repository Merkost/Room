import AppKit
import SwiftUI

extension RoomTokens.Status {
    // Keep the NSColor-backed tokens dynamic when AppKit draws the status item.
    static let normalAppKit = NSColor(normal)
    static let elevatedAppKit = NSColor(elevated)
    static let criticalAppKit = NSColor(critical)
}
