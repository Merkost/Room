import SwiftUI

/// Icons for the things rows name (FEATURES "Icons and colour"). Installed apps give their real icon through
/// NSWorkspace; tools without an app (npm, Gradle, Homebrew) get a small coloured tile with a glyph, like the mockup's
/// stand-ins. Teal stays the only accent for actions: these colours only identify things.
nonisolated enum RoomThingTiles {
    struct Match: Sendable {
        let keys: [String]
        let bundleID: String?
        let color: UInt32
        let glyph: RoomGlyph
    }

    static let matches: [Match] = [
        .init(keys: ["deriveddata", "xcode"], bundleID: "com.apple.dt.Xcode", color: 0x1B7CF2, glyph: .hammer),
        .init(keys: ["safari"], bundleID: "com.apple.Safari", color: 0x1AA0F0, glyph: .compass),
        .init(keys: ["simulator", "iphone", "ipad", "watch"], bundleID: "com.apple.iphonesimulator", color: 0x6E7781, glyph: .phone),
        .init(keys: ["android", "pixel", "system images"], bundleID: "com.google.android.studio", color: 0x34B36B, glyph: .phone),
        .init(keys: ["npm"], bundleID: nil, color: 0xCB3837, glyph: .box),
        .init(keys: ["gradle", "jdk"], bundleID: nil, color: 0x1E6A7A, glyph: .layers),
        .init(keys: ["homebrew"], bundleID: nil, color: 0xE0932A, glyph: .mug),
        .init(keys: ["browser", "chrome"], bundleID: "com.google.Chrome", color: 0x1AA0F0, glyph: .globe),
        .init(keys: ["node"], bundleID: nil, color: 0x5FA04E, glyph: .hex),
        .init(keys: ["kotlin", "konan"], bundleID: nil, color: 0x7F52FF, glyph: .hex),
        .init(keys: ["ndk"], bundleID: nil, color: 0x34B36B, glyph: .layers),
        .init(keys: ["docker"], bundleID: "com.docker.docker", color: 0x1D91E6, glyph: .stack),
        .init(keys: ["archive"], bundleID: nil, color: 0x8A6E4B, glyph: .box),
        .init(keys: ["ollama", "local model", "model"], bundleID: nil, color: 0xC2553F, glyph: .spark),
        .init(keys: ["claude"], bundleID: "com.anthropic.claudefordesktop", color: 0xD97757, glyph: .spark),
        .init(keys: ["codex", "chatgpt"], bundleID: "com.openai.chat", color: 0x30363A, glyph: .term),
        .init(keys: ["cursor"], bundleID: "com.todesktop.230313mzl4w4u92", color: 0x30363A, glyph: .term),
        .init(keys: ["worktree", "release/", "merged"], bundleID: nil, color: 0x6E7781, glyph: .branch),
        .init(keys: ["finder"], bundleID: "com.apple.finder", color: 0x3A57BA, glyph: .folder),
        .init(keys: ["preview"], bundleID: "com.apple.Preview", color: 0x3A57BA, glyph: .photo),
        .init(keys: ["notes"], bundleID: "com.apple.Notes", color: 0xE0A21A, glyph: .doc),
        .init(keys: ["mail"], bundleID: "com.apple.mail", color: 0x1AA0F0, glyph: .doc),
        .init(keys: ["photos"], bundleID: "com.apple.Photos", color: 0x3E8A33, glyph: .photo),
        .init(keys: ["music", "logic"], bundleID: "com.apple.Music", color: 0xE0503C, glyph: .wave),
        .init(keys: ["final cut", "movies", "film"], bundleID: "com.apple.FinalCut", color: 0x3E8A33, glyph: .film),
        .init(keys: ["slack"], bundleID: "com.tinyspeck.slackmacgap", color: 0x4A154B, glyph: .grid),
        .init(keys: ["figma"], bundleID: "com.figma.Desktop", color: 0x30363A, glyph: .grid),
        .init(keys: ["mail downloads"], bundleID: "com.apple.mail", color: 0x1AA0F0, glyph: .down),
    ]

    static func match(_ name: String) -> Match? {
        let lower = name.lowercased()
        return matches.first { match in match.keys.contains { lower.contains($0) } }
    }

    /// A project has no icon of its own: a stable colour from the kind palette, so rows tell apart at a glance.
    static let projectColors: [UInt32] = [0xF2683C, 0x2F7383, 0xE0A21A, 0x30363A, 0x2E9E6B, 0x3A57BA, 0xB73F2B]

    static func projectColor(_ name: String) -> UInt32 {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return projectColors[sum % projectColors.count]
    }

    @MainActor static func color(_ hex: UInt32) -> Color { .room(light: hex, dark: hex, name: "room.thing.\(hex)") }
}
