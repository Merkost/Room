import AppKit
import Foundation
import Testing
@testable import RoomApp

/// Ports of design/brand-ds/check/main.swift: the generated RoomDS must match the JSON copy in the test resources.
struct RoomDesignTokensTests {
    private let json: [String: Any] = {
        guard let url = Bundle.module.url(forResource: "room.tokens", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return root
    }()

    private func node(_ dotted: String) -> Any? {
        dotted.split(separator: ".").reduce(json as Any?) { ($0 as? [String: Any])?[String($1)] }
    }

    private func colourLeaves(_ n: Any?, _ path: [String]) -> [(String, [String: String])] {
        guard let dict = n as? [String: Any] else { return [] }
        if let v = dict["$value"] as? [String: String] { return [(path.joined(separator: "."), v)] }
        return dict.keys.filter { !$0.hasPrefix("$") }.sorted().flatMap { colourLeaves(dict[$0], path + [$0]) }
    }

    private func parse(_ s: String) -> RoomDS.RGBA {
        let parts = s.split(separator: "@")
        return RoomDS.RGBA(UInt32(parts[0].dropFirst(), radix: 16) ?? 0, parts.count > 1 ? Double(parts[1]) ?? 1 : 1)
    }

    private func expected(_ v: [String: String], _ a: RoomDS.Appearance) -> RoomDS.RGBA {
        switch a {
        case .light: parse(v["light"] ?? "#000000")
        case .dark: parse(v["dark"] ?? "#000000")
        case .lightHC: parse(v["lightHC"] ?? v["light"] ?? "#000000")
        case .darkHC: parse(v["darkHC"] ?? v["dark"] ?? "#000000")
        }
    }

    private func near(_ a: RoomDS.RGBA, _ b: RoomDS.RGBA) -> Bool { a.hex == b.hex && abs(a.alpha - b.alpha) < 0.0005 }

    private var colourJSON: [(String, [String: String])] { colourLeaves(node("color"), ["color"]) }

    @Test func jsonResourceLoads() {
        #expect(!json.isEmpty)
        #expect(json["$version"] as? String == RoomDS.version)
    }

    @Test func everyColourTokenPresent() {
        let names = Set(RoomDS.allSwatches.map(\.name))
        #expect(names.count == RoomDS.allSwatches.count, "duplicate swatch names")
        #expect(!colourJSON.isEmpty)
        for (name, _) in colourJSON { #expect(names.contains(name), "missing in Swift: \(name)") }
        let jsonNames = Set(colourJSON.map(\.0))
        for name in names { #expect(jsonNames.contains(name), "extra in Swift: \(name)") }
    }

    @Test func colourValuesMatchJSON() {
        let swatches = Dictionary(RoomDS.allSwatches.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for (name, v) in colourJSON {
            guard let s = swatches[name] else { continue }
            for a in RoomDS.Appearance.allCases {
                #expect(near(s.value(a), expected(v, a)), "\(name) \(a.rawValue)")
            }
        }
    }

    @Test func increaseContrastMapping() {
        let table: [(Bool, Bool, RoomDS.Appearance)] = [(false, false, .light), (true, false, .dark), (false, true, .lightHC), (true, true, .darkHC)]
        for (dark, hc, want) in table { #expect(RoomDS.Swatch.resolve(dark: dark, highContrast: hc) == want) }
        let swatches = Dictionary(RoomDS.allSwatches.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for (name, v) in colourJSON {
            guard let s = swatches[name] else { continue }
            if v["lightHC"] != nil { #expect(!near(s.lightHC, s.light), "\(name) lightHC equals light") }
            if v["darkHC"] != nil { #expect(!near(s.darkHC, s.dark), "\(name) darkHC equals dark") }
        }
    }

    @Test func dynamicColourResolvesLightAndDark() throws {
        for (appName, a) in [(NSAppearance.Name.aqua, RoomDS.Appearance.light), (.darkAqua, .dark)] {
            let appearance = try #require(NSAppearance(named: appName))
            appearance.performAsCurrentDrawingAppearance {
                for s in RoomDS.allSwatches {
                    guard let c = s.nsColor.usingColorSpace(.sRGB) else { Issue.record("\(s.name) not sRGB"); continue }
                    let v = s.value(a)
                    let hex = (UInt32((c.redComponent * 255).rounded()) << 16) | (UInt32((c.greenComponent * 255).rounded()) << 8) | UInt32((c.blueComponent * 255).rounded())
                    #expect(hex == v.hex && abs(Double(c.alphaComponent) - v.alpha) <= 0.002, "\(s.name) under \(a.rawValue)")
                }
            }
        }
    }

    // MARK: WCAG
    private func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private func composite(_ fg: RoomDS.RGBA, over bg: (Double, Double, Double)) -> (Double, Double, Double) {
        (fg.red * fg.alpha + bg.0 * (1 - fg.alpha), fg.green * fg.alpha + bg.1 * (1 - fg.alpha), fg.blue * fg.alpha + bg.2 * (1 - fg.alpha))
    }
    private func lum(_ c: (Double, Double, Double)) -> Double { 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2) }
    private func ratio(_ pair: RoomDS.ContrastPair, _ a: RoomDS.Appearance) -> Double {
        let white = (1.0, 1.0, 1.0)
        let base = pair.over.map { composite($0.value(a), over: white) } ?? white
        let bg: (Double, Double, Double)
        if pair.tint {
            bg = composite(RoomDS.RGBA(pair.fg.value(a).hex, 0.13), over: base)
        } else {
            bg = composite(pair.bg.value(a), over: base)
        }
        let fg = composite(pair.fg.value(a), over: bg)
        let (x, y) = (lum(fg), lum(bg))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test func contrastPairsPassAllAppearances() {
        #expect(!RoomDS.contrastPairs.isEmpty)
        for pair in RoomDS.contrastPairs {
            for a in RoomDS.Appearance.allCases {
                #expect(ratio(pair, a) + 1e-9 >= pair.minimum, "\(pair.id) \(a.rawValue)")
            }
        }
    }

    @Test func typeRolesMatchJSON() {
        let roles = (node("type.role") as? [String: Any]) ?? [:]
        #expect(Set(roles.keys) == Set(RoomDS.TypeRole.allCases.map(\.rawValue)))
        for role in RoomDS.TypeRole.allCases {
            guard let app = (roles[role.rawValue] as? [String: Any])?["app"] as? [String: Any] else { Issue.record("no json for \(role)"); continue }
            let s = role.spec
            #expect(s.family.rawValue == app["family"] as? String, "\(role) family")
            #expect(Double(s.size) == app["size"] as? Double, "\(role) size")
            #expect(s.weight == app["weight"] as? Int, "\(role) weight")
            #expect(Double(s.lineHeight) == app["lineHeight"] as? Double, "\(role) lineHeight")
            #expect(Double(s.tracking) == app["tracking"] as? Double, "\(role) tracking")
            #expect(s.tabular == ((app["tabular"] as? Bool) ?? false), "\(role) tabular")
            #expect(s.size >= RoomDS.textFloor, "\(role) below the 11 pt floor")
        }
        #expect(RoomDS.TypeRole.allCases.filter { $0.spec.family == .fraunces }.map(\.rawValue).sorted() == ["display", "displayXl"])
        #expect(RoomDS.TypeRole.allCases.filter { $0.rawValue.hasPrefix("number") }.allSatisfy { $0.spec.tabular })
    }

    @Test func spaceScaleMonotonic() {
        let scale = ((node("space.scale") as? [String: Any]) ?? [:]).compactMap { ($0.key, ($0.value as? Double) ?? 0) }.sorted { $0.1 < $1.1 }
        #expect(!scale.isEmpty)
        #expect(scale.map { CGFloat($0.1) } == RoomDS.Space.scale)
        for (a, b) in zip(RoomDS.Space.scale, RoomDS.Space.scale.dropFirst()) { #expect(b > a) }
        for v in RoomDS.Space.scale where v > 4 { #expect(v.truncatingRemainder(dividingBy: 4) == 0, "\(v) off the 4 pt grid") }
        #expect(RoomDS.Space.breath1 < RoomDS.Space.breath2 && RoomDS.Space.breath2 < RoomDS.Space.breath3 && RoomDS.Space.breath3 < RoomDS.Space.breath4)
    }

    @Test func radiusScaleMonotonic() {
        let scale = ((node("radius.scale") as? [String: Any]) ?? [:]).compactMap { $0.value as? Double }.sorted()
        #expect(!scale.isEmpty)
        #expect(scale.map { CGFloat($0) } == RoomDS.Radius.scale)
        for (a, b) in zip(RoomDS.Radius.scale, RoomDS.Radius.scale.dropFirst()) { #expect(b > a) }
        #expect(RoomDS.Radius.tile < RoomDS.Radius.row && RoomDS.Radius.row < RoomDS.Radius.group && RoomDS.Radius.group < RoomDS.Radius.window)
    }

    @Test func motionDurationsInSet() {
        let allowed: Set<Int> = [120, 200, 320, 600]
        let durations = (node("motion.duration") as? [String: Any]) ?? [:]
        for d in RoomDS.Motion.Duration.allCases {
            #expect(allowed.contains(d.milliseconds), "\(d) is not in 120/200/320/600")
            #expect((durations[d.rawValue] as? [String: Any])?["$value"] as? Int == d.milliseconds, "\(d) differs from json")
        }
        #expect(Set(RoomDS.Motion.Duration.allCases.map(\.milliseconds)) == allowed)
        #expect(RoomDS.Motion.staggerItem * Double(RoomDS.Motion.staggerCap) <= 0.4)
    }

    @Test func oneOvershootSpringOnly() {
        let springs = (node("motion.spring") as? [String: [String: Any]]) ?? [:]
        for s in RoomDS.Motion.Spring.allCases {
            #expect(springs[s.rawValue]?["response"] as? Double == s.spec.response, "\(s) response")
            #expect(springs[s.rawValue]?["damping"] as? Double == s.spec.damping, "\(s) damping")
        }
        #expect(RoomDS.Motion.Spring.allCases.filter { $0.spec.damping < 1 }.map(\.rawValue) == ["success"])
        #expect(RoomDS.Motion.Vocabulary.allCases.filter { $0.move.curve == "spring.success" }.map(\.rawValue) == ["madeRoom"])
    }
}
