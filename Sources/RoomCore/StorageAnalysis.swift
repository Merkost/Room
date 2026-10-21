import Foundation

public enum StorageCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case cachesBuilds, agents, applications, archives, media, documents, systemOther

    public var title: String {
        switch self {
        case .cachesBuilds: "Builds & caches"
        case .agents: "Agent data"
        case .applications: "Applications"
        case .archives: "Archives"
        case .media: "Media"
        case .documents: "Documents"
        case .systemOther: "System & other"
        }
    }

    public var symbol: String {
        switch self {
        case .cachesBuilds: "hammer"
        case .agents: "sparkle"
        case .applications: "app"
        case .archives: "archivebox"
        case .media: "photo.on.rectangle"
        case .documents: "doc.text"
        case .systemOther: "folder"
        }
    }
}

public struct StorageCategorySummary: Identifiable, Equatable, Sendable {
    public var id: String { category.rawValue }
    public let category: StorageCategory
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int

    public init(category: StorageCategory, allocatedBytes: Int64, logicalBytes: Int64, fileCount: Int) {
        self.category = category
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
    }
}

public enum StorageDisposition: String, Codable, Sendable {
    case protected, review, cache
    public var title: String {
        switch self {
        case .protected: "Keep protected"
        case .review: "Review manually"
        case .cache: "Known cache location"
        }
    }
}

public enum StorageAnalysisSource: String, Codable, Sendable {
    case ruleBased, onDevice
    public var title: String { self == .onDevice ? "On-device" : "Rule-based" }
}

public struct StorageAIAvailability: Equatable, Sendable {
    public let isAvailable: Bool
    public let reason: String
    public let provider: String
    public let modelName: String?
    public init(isAvailable: Bool, reason: String, provider: String = "Apple Intelligence", modelName: String? = nil) {
        self.isAvailable = isAvailable; self.reason = reason
        self.provider = provider; self.modelName = modelName
    }
}

public struct StorageFinding: Identifiable, Equatable, Sendable {
    public let id: String
    public let item: DiskMapItem
    public let category: StorageCategory
    public let disposition: StorageDisposition
    public let reason: String
    public let source: StorageAnalysisSource
}

public struct StorageAnalysisReport: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let scanID: UUID
    public let generatedAt: Date
    public let findings: [StorageFinding]
    public let source: StorageAnalysisSource
    public let availability: StorageAIAvailability
    public let summary: String
}

/// Organization labels do not establish disposability or authorize any cleanup.
public enum StorageClassification {
    public static func category(for url: URL) -> StorageCategory {
        let path = url.path.lowercased()
        let components = path.split(separator: "/").map(String.init)
        let names = Set(components)
        if components.contains(where: { $0.hasSuffix(".app") || $0.hasSuffix(".framework") }) ||
            !names.isDisjoint(with: [".rustup", "toolchains", "sdks", "ms-playwright"]) { return .applications }
        if path.hasSuffix("/library/caches") || path.contains("/library/caches/") || !names.isDisjoint(with: ["build", ".build", "deriveddata", "_cacache", "_npx"]) ||
            path.hasSuffix("/.gradle/caches") || path.contains("/.gradle/caches/") ||
            path.hasSuffix("/.codex/cache") || path.contains("/.codex/cache/") ||
            path.hasSuffix("/.claude/cache") || path.contains("/.claude/cache/") { return .cachesBuilds }
        if !names.isDisjoint(with: [".codex", ".claude", ".agents", ".cursor", ".gemini"]) ||
            path.hasSuffix("/application support/codex") || path.contains("/application support/codex/") ||
            path.hasSuffix("/application support/claude") || path.contains("/application support/claude/") { return .agents }
        let ext = url.pathExtension.lowercased()
        if archiveExtensions.contains(ext) { return .archives }
        if mediaExtensions.contains(ext) { return .media }
        if documentExtensions.contains(ext) { return .documents }
        return .systemOther
    }

    public static func isHiddenPath(_ url: URL) -> Bool {
        url.path.split(separator: "/").contains { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
    }

    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "xip", "pkg"]
    static let mediaExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "svg", "raw", "mov", "mp4", "mkv", "avi", "mp3", "wav", "m4a", "flac", "aiff"]
    static let documentExtensions: Set<String> = ["pdf", "txt", "md", "rtf", "doc", "docx", "pages", "numbers", "xls", "xlsx", "csv", "ppt", "pptx", "key", "odt", "tex", "swift", "kt", "kts", "java", "js", "ts", "tsx", "jsx", "py", "rb", "rs", "go", "c", "cpp", "h", "hpp", "cs", "json", "jsonl", "yaml", "yml", "toml", "xml", "html", "css", "sql"]
}

public enum StorageAnalyzer {
    public static func analyze(report: DiskMapReport, configuration: CacheConfiguration = .standard) -> StorageAnalysisReport {
        let ordered = (Array(report.children.prefix(24)) + report.largestFiles).sorted {
            $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes
        }
        var seen = Set<String>()
        let findings = ordered.filter { seen.insert($0.id).inserted }.prefix(100).map {
            finding(for: $0, configuration: configuration)
        }
        return StorageAnalysisReport(id: UUID(), scanID: report.id, generatedAt: Date(), findings: findings,
            source: .ruleBased,
            availability: StorageAIAvailability(isAvailable: false, reason: "On-device analysis has not been requested."),
            summary: "Metadata-based review of large items. Categories and age never establish that a file is unnecessary; cleanup eligibility is checked separately.")
    }

    static func finding(for item: DiskMapItem, configuration: CacheConfiguration) -> StorageFinding {
        let disposition: StorageDisposition
        let reason: String
        if let protection = protectionReason(for: item.url, configuration: configuration) {
            disposition = .protected
            reason = protection
        } else if configuration.roots.contains(where: { root in
            root.allowsKnownLocation(item.url)
        }) {
            disposition = .cache
            reason = "Inside an explicit cache location. This label does not establish cleanup eligibility; active tools, age, identity and the cleanup allowlist must still be checked."
        } else if item.category == .documents {
            disposition = .protected
            reason = "Document or source metadata may represent user work. Keep it protected; its name, size and age do not establish redundancy."
        } else {
            disposition = .review
            reason = "Review the owning app and contents manually. File metadata alone cannot establish whether this item is needed."
        }
        return StorageFinding(id: item.id, item: item, category: item.category, disposition: disposition,
            reason: reason, source: .ruleBased)
    }

    static func contains(_ url: URL, in root: URL) -> Bool {
        let path = url.roomLexicallyNormalized.path
        let base = root.roomLexicallyNormalized.path
        return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
    }

    private static func protectionReason(for url: URL, configuration: CacheConfiguration) -> String? {
        for location in configuration.protectedLocations where contains(url, in: location.url) {
            return location.reason
        }
        let lower = url.path.lowercased()
        let components = lower.split(separator: "/").map(String.init)
        let names = Set(components)
        let name = url.lastPathComponent.lowercased()
        if !names.isDisjoint(with: [".git", ".ssh", ".gnupg", ".aws", ".kube", "keychains", "localhistory"]) ||
            ["auth.json", "credentials", "credentials.json", ".env", "settings.json"].contains(name) ||
            name.hasPrefix(".env.") || ["sqlite", "sqlite3", "db", "key", "pem", "p12", "pfx", "keystore", "jks"].contains(url.pathExtension.lowercased()) ||
            name.hasSuffix(".sqlite-wal") || name.hasSuffix(".sqlite-shm") || name.hasSuffix(".db-wal") || name.hasSuffix(".db-shm") {
            return "Credentials, databases, configuration or recovery history. Keep this persistent data protected."
        }
        if components.contains(where: { $0.hasSuffix(".app") || $0.hasSuffix(".photoslibrary") }) ||
            !names.isDisjoint(with: [".rustup", "toolchains", "sdks", "ms-playwright"]) {
            return "Installed application, toolchain or persistent library data. Keep it in place and manage it through its owning app."
        }
        let knownCache = configuration.roots.contains { root in
            root.allowsKnownLocation(url)
        }
        if knownCache { return nil }
        for system in ["/System", "/Library", "/bin", "/sbin", "/usr", "/private"] where contains(url, in: URL(fileURLWithPath: system)) {
            // User-selected fixture/private paths are not automatically OS state;
            // protect actual system subtrees rather than all /private/tmp work.
            if system == "/private", !lower.hasPrefix("/private/var/db/") && !lower.hasPrefix("/private/etc/") { continue }
            return "System-managed data. Keep it protected and use macOS or the owning app to manage it."
        }
        let home = configuration.homeDirectory
        if contains(url, in: home.appendingPathComponent("Library", isDirectory: true)) {
            return "Persistent application data can include history, settings and user work. A cache-like name does not establish disposability."
        }
        if contains(url, in: home) {
            let relative = String(url.path.dropFirst(home.path.count)).split(separator: "/")
            if relative.first?.hasPrefix(".") == true {
                return "Hidden home-folder data may contain credentials, conversations, installed tools or user work. Keep it protected outside explicit cache locations."
            }
        }
        return nil
    }
}
