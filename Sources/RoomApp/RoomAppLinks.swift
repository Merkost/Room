import Foundation

struct RoomAppLinks {
    let support: URL?
    let privacy: URL?

    init(info: [String: Any]? = Bundle.main.infoDictionary) {
        support = Self.validated(info?["RoomSupportURL"] as? String)
        privacy = Self.validated(info?["RoomPrivacyURL"] as? String)
    }

    private static func validated(_ value: String?) -> URL? {
        guard let value, let components = URLComponents(string: value), components.scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              host != "localhost", !host.hasSuffix(".invalid"), !host.hasSuffix(".test"),
              !["example.com", "example.org", "example.net"].contains(host),
              !value.contains("{"), !value.contains("}"), let url = components.url else { return nil }
        return url
    }
}
