import Foundation

// MARK: - Parsers (DV-1: text only, bounded, anchored on known keys, nothing executed)

nonisolated enum RoomDevParse {
    /// Same ceiling as DeveloperResourcesLimits.maximumFileBytes' hard maximum (262 144). Larger files are not parsed.
    static let maximumBytes = 262_144

    /// Mirrors RoomCore DRVersions.version: 1–4 numeric parts, optional "-qualifier".
    static func version(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= 96 else { return nil }
        let main = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = main[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(numbers.count),
              numbers.allSatisfy({ !$0.isEmpty && $0.count <= 12 && $0.allSatisfy { $0 >= "0" && $0 <= "9" } }) else { return nil }
        if main.count == 2 {
            guard !main[1].isEmpty, main[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-+".contains($0)) }) else { return nil }
        }
        return text
    }

    /// Strips // line comments and /* */ blocks so a commented-out target or version is never read as a pin.
    static func uncommented(_ text: String) -> String {
        var out = "", i = text.startIndex, inBlock = false, inString = false
        while i < text.endIndex {
            let c = text[i], next = text.index(after: i), n: Character? = next < text.endIndex ? text[next] : nil
            if inBlock {
                if c == "*", n == "/" { inBlock = false; i = text.index(after: next); continue }
                if c == "\n" { out.append(c) }
                i = next; continue
            }
            if c == "\"" { inString.toggle() }
            if !inString, c == "/", n == "/" {
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                continue
            }
            if !inString, c == "/", n == "*" { inBlock = true; i = text.index(after: next); continue }
            if c == "\n" { inString = false }
            out.append(c); i = next
        }
        return out
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > group, let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }
    private static func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (0..<m.numberOfRanges).map { g in Range(m.range(at: g), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    // gradle/wrapper/gradle-wrapper.properties → ("8.9", "bin"). Only the file name of distributionUrl is read.
    static func wrapper(_ properties: String) -> (version: String, type: String)? {
        guard properties.utf8.count <= maximumBytes else { return nil }
        guard let values = try? DRProperties.selected(properties, keys: ["distributionUrl"]) else { return nil }
        return values["distributionUrl"].flatMap(DRVersions.distributionURL)
    }

    /// "kotlin-native-prebuilt-macos-aarch64-2.1.0" → "2.1.0" (a ~/.konan child).
    static func konan(_ folder: String) -> String? {
        guard folder.hasPrefix("kotlin-native-prebuilt-") || folder.hasPrefix("kotlin-native-macos-") else { return nil }
        guard let last = folder.split(separator: "-").last else { return nil }
        // Versions with a qualifier ("2.1.20-RC") end in letters; read from the first numeric component on.
        let parts = folder.split(separator: "-").map(String.init)
        guard let start = parts.firstIndex(where: { $0.first?.isNumber == true }) else { return version(String(last)) }
        return version(parts[start...].joined(separator: "-"))
    }

    nonisolated struct Catalog: Equatable, Sendable {
        var versions: [String: String] = [:]          // normalized key ("agp", "kotlin", "ndk") → value
        var agp: String?
        var kotlin: String?
        var declaresMultiplatform = false
        var multiplatformAccessors: [String] = []      // "libs.plugins.kotlin.multiplatform"
    }

    /// Accessor normalization used by Gradle: '-', '_' and '.' separate segments.
    static func accessorKey(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "_", with: ".").replacingOccurrences(of: "-", with: ".")
    }

    /// gradle/libs.versions.toml: [versions] and [plugins] only. Plugin ids decide what a version is (DV-1).
    static func versionCatalog(_ toml: String) -> Catalog? {
        guard toml.utf8.count <= maximumBytes else { return nil }
        var catalog = Catalog(), section = ""
        var pluginRows: [(alias: String, id: String, version: String?, ref: String?)] = []
        for raw in toml.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#"), !line[..<hash].contains("\"") { line = String(line[..<hash]).trimmingCharacters(in: .whitespaces) }
            if line.isEmpty { continue }
            if line.hasPrefix("[") { section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")); continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if section == "versions" {
                if value.hasPrefix("\""), let v = firstMatch("^\"([^\"]+)\"", in: value), let ok = version(v) {
                    catalog.versions[accessorKey(key)] = ok
                }
            } else if section == "plugins" {
                if value.hasPrefix("{") {
                    guard let id = firstMatch("\\bid\\s*=\\s*\"([^\"]+)\"", in: value) else { continue }
                    pluginRows.append((key, id, firstMatch("\\bversion\\s*=\\s*\"([^\"]+)\"", in: value),
                                       firstMatch("\\bversion\\.ref\\s*=\\s*\"([^\"]+)\"", in: value)))
                } else if let short = firstMatch("^\"([^\":]+):([^\"]+)\"", in: value), let v = firstMatch("^\"[^\":]+:([^\"]+)\"", in: value) {
                    pluginRows.append((key, short, v, nil))
                }
            }
        }
        func resolve(_ row: (alias: String, id: String, version: String?, ref: String?)) -> String? {
            if let v = row.version { return version(v) }
            if let ref = row.ref { return catalog.versions[accessorKey(ref)] }
            return nil
        }
        for row in pluginRows {
            if row.id == "com.android.application" || row.id == "com.android.library" { catalog.agp = catalog.agp ?? resolve(row) }
            if row.id.hasPrefix("org.jetbrains.kotlin.") { catalog.kotlin = catalog.kotlin ?? resolve(row) }
            if row.id == "org.jetbrains.kotlin.multiplatform" {
                catalog.declaresMultiplatform = true
                catalog.multiplatformAccessors.append("libs.plugins." + accessorKey(row.alias))
            }
        }
        catalog.agp = catalog.agp ?? catalog.versions["agp"] ?? catalog.versions["androidgradleplugin"]
        catalog.kotlin = catalog.kotlin ?? catalog.versions["kotlin"]
        return catalog
    }

    nonisolated struct BuildScript: Equatable, Sendable {
        var agp: String?
        var kotlin: String?
        var appliesMultiplatform = false
        var appleNativeTargets = false
        var ndk: String?
    }

    /// build.gradle(.kts) of a module or the root. `catalog` resolves `libs.versions.x.get()` and plugin aliases.
    static func buildScript(_ text: String, catalog: Catalog?) -> BuildScript? {
        guard text.utf8.count <= maximumBytes else { return nil }
        let src = uncommented(text)
        var s = BuildScript()
        s.agp = firstMatch(#"id\s*\(?\s*["']com\.android\.(?:application|library)["']\s*\)?\s*version\s*\(?\s*["']([^"']+)["']"#, in: src).flatMap(version)
        s.kotlin = (firstMatch(#"kotlin\s*\(\s*"[a-z.]+"\s*\)\s*version\s*\(?\s*"([^"]+)""#, in: src)
            ?? firstMatch(#"id\s*\(?\s*["']org\.jetbrains\.kotlin\.[a-z.]+["']\s*\)?\s*version\s*\(?\s*["']([^"']+)["']"#, in: src)).flatMap(version)
        let aliases = catalog?.multiplatformAccessors ?? []
        s.appliesMultiplatform = src.contains(#"kotlin("multiplatform")"#) || src.contains("org.jetbrains.kotlin.multiplatform")
            || aliases.contains { src.contains("alias(\($0))") }
        // Apple targets are calls such as iosArm64(), iosSimulatorArm64(), macosArm64 { }, ios("x"). Source sets
        // (iosMain, iosTest) are not targets.
        let targets = allMatches(#"\b(ios|macos|watchos|tvos)([A-Z][A-Za-z0-9]*)?\s*(\(|\{)"#, in: src)
        s.appleNativeTargets = targets.contains { row in
            let suffix = row.count > 2 ? row[2] : ""
            return !(suffix.hasSuffix("Main") || suffix.hasSuffix("Test"))
        }
        if let literal = firstMatch(#"\bndkVersion\s*=?\s*\(?\s*["']([^"']+)["']"#, in: src) {
            s.ndk = version(literal)
        } else if let ref = firstMatch(#"\bndkVersion\s*=\s*libs\.versions\.([A-Za-z0-9_.-]+?)\.get\(\)"#, in: src) {
            s.ndk = catalog?.versions[accessorKey(ref)]
        }
        return s
    }

    /// ~/Library/Developer/Xcode/DerivedData/<Name>-<hash>/info.plist → WorkspacePath.
    static func derivedDataWorkspace(_ plist: Data) -> String? {
        guard plist.count <= maximumBytes,
              let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let path = object["WorkspacePath"] as? String, path.hasPrefix("/") else { return nil }
        return path
    }
}
