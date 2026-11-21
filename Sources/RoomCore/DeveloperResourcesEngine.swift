import Darwin
import Foundation

/// Read-only review. No emulator/Gradle execution, deletion, or implicit home
/// discovery occurs. Paths and timestamps are evidence, not an unused verdict.
public actor DeveloperResourcesEngine {
    private let beforeResourceValidation: (@Sendable (URL) -> Void)?

    public init() { beforeResourceValidation = nil }

    init(beforeResourceValidation: @escaping @Sendable (URL) -> Void) {
        self.beforeResourceValidation = beforeResourceValidation
    }

    public func scan(request: DeveloperResourcesRequest,
                     progress: (@Sendable (DeveloperResourcesProgress) -> Void)? = nil) async -> DeveloperResourcesReport {
        let id = UUID(), date = Date()
        let budget = DRBudget(request.limits)
        var avds: [AndroidVirtualDeviceResource] = [], gradle: [GradleDeveloperResource] = []
        var simulators: [SimulatorDeviceResource] = []
        var wrappers: [GradleProjectWrapper] = []
        var projects: [String: DeveloperProject] = [:]
        var toolchains: [DeveloperToolchainResource] = []
        var storage: [DeveloperStorageResource] = []
        var aiStorage: [DeveloperAIStorageResource] = []
        var approvals: [URL] = []
        let runtimeRoots = request.scope == .toolStorage ? Array(request.simulatorRuntimeRoots.prefix(32)) : []
        let runtimePaths = Set(runtimeRoots.filter(\.isFileURL).map { $0.roomLexicallyNormalized.path })
        var runtimeApprovals: Set<String> = []
        for supplied in request.approvedFolders.prefix(64) {
            let url = supplied.roomLexicallyNormalized
            let scansRuntime = runtimePaths.contains(url.path)
            do {
                guard supplied.isFileURL, url.path != "/" else { throw DRReadError.invalidRoot }
                let info = try DRFiles.directory(url, ownership: scansRuntime ? .readable : .currentUser)
                if info.st_uid == getuid(), !approvals.contains(where: { $0.path == url.path }) { approvals.append(url) }
                if scansRuntime { runtimeApprovals.insert(url.path) }
            } catch {
                budget.note(url, scansRuntime ? "The approved Simulator Runtimes folder is unavailable or linked."
                    : "The approved folder is unavailable, linked or not owned by this user.")
            }
        }
        if request.approvedFolders.count > 64 { budget.note(URL(fileURLWithPath: "/"), "Only the first 64 approved folders were considered.") }
        func permitted(_ supplied: URL, reportMissingApproval: Bool = true) -> URL? {
            let url = supplied.roomLexicallyNormalized
            guard supplied.isFileURL, approvals.contains(where: { DRFiles.contains(url, in: $0) }) else {
                if reportMissingApproval {
                    budget.note(url, "This requested location needs explicit folder approval. It was not inspected.")
                }
                return nil
            }
            return url
        }
        func update(_ phase: String, _ url: URL) {
            progress?(DeveloperResourcesProgress(phase: phase, inspectedCount: budget.nodes, currentPath: url.path))
        }
        do {
            let review = request.scope == .review
            var searched: [URL] = []
            let projectRoots = (review ? request.projectRoots : []).prefix(32).sorted { $0.pathComponents.count < $1.pathComponents.count }
            for supplied in projectRoots {
                try budget.check()
                guard let root = permitted(supplied),
                      !searched.contains(where: { DRFiles.contains(root, in: $0) }) else { continue }
                searched.append(root)
                update("Project versions", root)
                do { try DRProjects.find(root, budget: budget, wrappers: &wrappers, projects: &projects) }
                catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { budget.note(root, "Project version inspection was incomplete. No builds were run.") }
                await Task.yield()
            }
            var seenAVDs: Set<String> = []
            let scansDevices = review || request.scope == .devices
            for supplied in (scansDevices ? request.avdRoots : []).prefix(32) {
                try budget.check()
                guard let root = permitted(supplied) else { continue }
                update("Android devices", root)
                let candidates: [URL]
                do {
                    candidates = root.lastPathComponent.lowercased().hasSuffix(".avd") ? [root]
                        : try DRFiles.children(root, budget: budget).filter { $0.lastPathComponent.lowercased().hasSuffix(".avd") }
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { budget.note(root, "The selected AVD location could not be enumerated safely."); continue }
                for url in candidates where seenAVDs.insert(url.path).inserted {
                    try budget.resource()
                    update("Android devices", url)
                    do { avds.append(try androidDevice(url, request: request, budget: budget)) }
                    catch is CancellationError { throw CancellationError() }
                    catch is DRStop { throw DRStop.limit }
                    catch { budget.note(url, "This AVD could not be inspected safely. Linked or inaccessible directories are skipped.") }
                }
                await Task.yield()
            }
            if request.scope == .devices {
                var seenRoots: Set<String> = []
                for supplied in request.simulatorDeviceRoots.prefix(32) {
                    try budget.check()
                    let root = supplied.roomLexicallyNormalized
                    guard seenRoots.insert(root.path).inserted else { continue }
                    guard supplied.isFileURL, approvals.contains(where: { $0.path == root.path }) else {
                        budget.note(root, "Choose this Simulator Devices folder explicitly before measuring it.")
                        continue
                    }
                    update("Apple simulators", root)
                    let children: [URL]
                    let volume: dev_t
                    do {
                        volume = try DRFiles.directory(root).st_dev
                        children = try DRFiles.children(root, budget: budget)
                        guard try DRFiles.isSimulatorDeviceSet(root, budget: budget, children: children) else {
                            budget.note(root, "Choose the Simulator Devices folder containing the simulator device set.")
                            continue
                        }
                    } catch is CancellationError { throw CancellationError() }
                    catch is DRStop { throw DRStop.limit }
                    catch { budget.note(root, "The Simulator Devices folder could not be inspected safely."); continue }
                    for url in children {
                        guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
                        try budget.resource()
                        update("Apple simulators", url)
                        do { simulators.append(try simulatorDevice(url, id: id, volume: volume, budget: budget)) }
                        catch is CancellationError { throw CancellationError() }
                        catch is DRStop { throw DRStop.limit }
                        catch { budget.note(url, "Simulator device metadata could not be read safely.") }
                    }
                    await Task.yield()
                }
            }
            var seenGradle: Set<String> = []
            for supplied in (review ? request.gradleHomes : []).prefix(32) {
                guard supplied.isFileURL else { budget.note(supplied, "Choose a local Gradle home folder."); continue }
                let home = supplied.roomLexicallyNormalized
                for (relative, kind) in [("wrapper/dists", GradleDeveloperResourceKind.distribution), ("caches", .sharedCache)] {
                    try budget.check()
                    // An approved caches/dists child can be inspected without
                    // opening an unapproved Gradle home or its properties file.
                    let target = home.appendingPathComponent(relative, isDirectory: true)
                    guard let root = permitted(target) else { continue }
                    update("Gradle resources", root)
                    let children: [URL]
                    do { children = try DRFiles.children(root, budget: budget) }
                    catch is CancellationError { throw CancellationError() }
                    catch is DRStop { throw DRStop.limit }
                    catch { budget.note(root, "This Gradle cache/distribution directory is unavailable or inaccessible."); continue }
                    for url in children where seenGradle.insert(url.path).inserted {
                        try budget.resource()
                        update("Gradle resources", url)
                        do {
                            let info = try DRFiles.metadata(url)
                            guard DRFiles.isDirectory(info) else { continue }
                            let distribution = DRVersions.distribution(url.lastPathComponent)
                            if kind == .distribution, distribution == nil { continue }
                            let version = kind == .distribution ? distribution?.version : DRVersions.version(url.lastPathComponent)
                            let type = kind == .distribution ? distribution?.type : nil
                            let measured = try DRFiles.measure(url, budget: budget, beforeFinalValidation: beforeResourceValidation)
                            let matches = version.map { value in wrappers.filter {
                                $0.version == value && (kind != .distribution || $0.distributionType == type)
                            } } ?? []
                            let note: String
                            if version == nil { note = "Shared across Gradle versions. Selected project wrappers cannot establish that this cache is unused." }
                            else if matches.isEmpty { note = "No discovered wrapper in the selected projects references this \(kind == .distribution ? "distribution" : "version"). Other projects and offline builds may still need it." }
                            else { note = "Referenced by \(matches.count) selected project \(matches.count == 1 ? "wrapper" : "wrappers"). This is configuration evidence, not proof of recent execution." }
                            gradle.append(GradleDeveloperResource(url: url, name: url.lastPathComponent,
                                kind: kind == .distribution ? .distribution : version == nil ? .sharedCache : .versionCache,
                                version: version, distributionType: type, allocatedBytes: measured.allocated,
                                logicalBytes: measured.logical, isPartial: measured.partial,
                                projectUses: matches, usageNote: note, evidence: measured.evidence,
                                activity: try activity(for: url, avdName: nil, measured: measured, snapshot: request.activity, budget: budget)))
                        } catch is CancellationError { throw CancellationError() }
                        catch is DRStop { throw DRStop.limit }
                        catch { budget.note(url, "This Gradle resource could not be inspected safely.") }
                    }
                }
                await Task.yield()
            }
            let rootsByKind: [(RoomDevPinKind, [URL])] = review ? [
                (.derivedData, request.derivedDataRoots), (.ndk, request.sdkRoots), (.kotlinNative, request.konanRoots),
            ] : []
            var seenToolchains: Set<String> = []
            for (kind, roots) in rootsByKind {
                for supplied in roots.prefix(32) {
                    try budget.check()
                    guard let root = permitted(supplied) else { continue }
                    update(kind.title, root)
                    let location = kind == .ndk ? root.appendingPathComponent("ndk", isDirectory: true) : root
                    try readToolchains(in: location, kind: kind, approvals: approvals, budget: budget,
                                       seen: &seenToolchains, results: &toolchains)
                    await Task.yield()
                }
            }
            let storageRoots: [(DeveloperStorageKind, [URL], String?)] = request.scope == .toolStorage ? [
                (.gradleDaemon, request.gradleHomes, "daemon"),
                (.gradleJDKs, request.gradleHomes, "jdks"),
                (.androidSystemImages, request.sdkRoots, "system-images"),
                (.simulatorDevices, request.simulatorDeviceRoots, nil),
            ] : []
            for (kind, roots, child) in storageRoots {
                var seen: Set<String> = []
                for supplied in roots.prefix(32) where supplied.isFileURL {
                    try budget.check()
                    let candidate = child.map { supplied.appendingPathComponent($0, isDirectory: true) } ?? supplied
                    // The other Gradle and SDK resources may have approval for only one child.
                    guard let root = permitted(candidate, reportMissingApproval: child == nil),
                          seen.insert(root.path).inserted else { continue }
                    update("Tool storage", root)
                    if let resource = try readStorage(in: root, kind: kind, budget: budget) {
                        storage.append(resource)
                    }
                    await Task.yield()
                }
            }
            let runtimeFiles = DRMeasuredFiles()
            var seenRuntimeRoots: Set<String> = []
            for supplied in runtimeRoots {
                try budget.check()
                let root = supplied.roomLexicallyNormalized
                guard supplied.isFileURL, runtimeApprovals.contains(root.path) else {
                    budget.note(root, "Choose this Simulator Runtimes folder explicitly before measuring it.")
                    continue
                }
                guard seenRuntimeRoots.insert(root.path).inserted else { continue }
                update("Simulator runtimes", root)
                try DRSimulatorRuntimes.read(in: root, budget: budget, files: runtimeFiles,
                                             beforeFinalValidation: beforeResourceValidation, results: &storage)
                await Task.yield()
            }
            if request.scope == .aiTools {
                let files = DRMeasuredFiles()
                for supplied in request.aiToolRoots.prefix(32) {
                    try budget.check()
                    let root = supplied.url.roomLexicallyNormalized
                    guard supplied.url.isFileURL, approvals.contains(where: { $0.path == root.path }) else {
                        budget.note(root, "Choose this tool's folder explicitly before measuring it.")
                        continue
                    }
                    let cacheNames = try aiCacheNames(for: supplied.tool, in: root, budget: budget)
                    for location in DRAIStorageLocation.catalogue(for: supplied.tool) {
                        try budget.node()
                        let first = String(location.path.prefix { $0 != "/" })
                        if (first == "cache" || first == "Cache"), !cacheNames.contains(first) { continue }
                        let url = root.appendingPathComponent(location.path)
                        guard !aiStorage.contains(where: { DRFiles.contains(url, in: $0.url) || DRFiles.contains($0.url, in: url) })
                        else { continue }
                        update("AI tool storage", url)
                        if let resource = try readAIStorage(in: url, tool: supplied.tool, location: location, budget: budget, files: files) {
                            aiStorage.append(resource)
                        }
                    }
                    await Task.yield()
                }
            }
        } catch is CancellationError { }
        catch { budget.limited = true }
        let roleRoots: [[URL]] = switch request.scope {
        case .devices: [request.avdRoots, request.simulatorDeviceRoots]
        case .toolStorage: [request.gradleHomes, request.sdkRoots, request.simulatorDeviceRoots, request.simulatorRuntimeRoots]
        case .review: [request.projectRoots, request.avdRoots, request.gradleHomes, request.sdkRoots, request.derivedDataRoots, request.konanRoots]
        case .aiTools: []
        }
        let exceededRoots = request.scope == .aiTools ? request.aiToolRoots.count > 32 : roleRoots.contains(where: { $0.count > 32 })
        if exceededRoots {
            budget.note(approvals.first ?? URL(fileURLWithPath: "/"), "Each resource role is limited to its first 32 selected roots.")
        }
        if budget.limited { budget.note(approvals.first ?? URL(fileURLWithPath: "/"), "The bounded scan reached a time, depth, node or resource limit. Results and size measurements may be incomplete.") }
        toolchains.append(contentsOf: gradle.compactMap { resource in
            guard resource.kind == .distribution, let version = resource.version,
                  let type = resource.distributionType else { return nil }
            return DeveloperToolchainResource(path: resource.url.path, kind: .gradle, version: version + "-" + type,
                                              gradleType: type, bytes: resource.allocatedBytes, partial: resource.isPartial)
        })
        return DeveloperResourcesReport(id: id, scannedAt: date,
            androidDevices: avds.sorted { $0.allocatedBytes > $1.allocatedBytes },
            gradleResources: gradle.sorted { $0.allocatedBytes > $1.allocatedBytes },
            projectWrappers: wrappers.sorted { $0.propertiesURL.path < $1.propertiesURL.path },
            projects: projects.values.sorted { $0.root < $1.root }, toolchains: toolchains,
            storageResources: storage.sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.id < $1.id }
                return $0.allocatedBytes > $1.allocatedBytes
            },
            aiStorageResources: aiStorage.sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.id < $1.id }
                return $0.allocatedBytes > $1.allocatedBytes
            },
            simulatorDevices: simulators.sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.id < $1.id }
                return $0.allocatedBytes > $1.allocatedBytes
            },
            issues: budget.issues, cancelled: Task.isCancelled,
            isPartial: Task.isCancelled || budget.limited || !budget.issues.isEmpty || avds.contains(where: \.isPartial)
                || gradle.contains(where: \.isPartial) || wrappers.contains(where: \.isPartial)
                || toolchains.contains(where: \.partial) || storage.contains(where: \.isPartial)
                || aiStorage.contains(where: \.isPartial) || simulators.contains(where: \.isPartial))
    }

    private func aiCacheNames(for tool: DeveloperAITool, in root: URL, budget: DRBudget) throws -> Set<String> {
        // On case-insensitive volumes, a desktop Cache can alias a CLI's lowercase cache.
        // Check the spelling before treating a CLI cache as a desktop rendering cache.
        guard tool == .codex || tool == .claudeCode else { return ["cache", "Cache"] }
        do {
            return Set(try DRFiles.children(root, budget: budget).map(\.lastPathComponent))
        } catch is CancellationError {
            throw CancellationError()
        } catch is DRStop {
            throw DRStop.limit
        } catch {
            budget.note(root, "The cache folder names could not be confirmed safely.")
            return []
        }
    }

    private func readAIStorage(in url: URL, tool: DeveloperAITool, location: DRAIStorageLocation,
                               budget: DRBudget, files: DRMeasuredFiles) throws -> DeveloperAIStorageResource? {
        do {
            let metadata = try DRFiles.metadata(url)
            let allocatedBytes: Int64
            let partial: Bool
            if location.isFile {
                guard DRFiles.isRegular(metadata) else { throw DRReadError.invalidRoot }
                try budget.resource()
                allocatedBytes = files.allocatedBytes(adding: metadata)
                beforeResourceValidation?(url)
                partial = (try? DRFiles.metadata(url)).map { DRFiles.same(metadata, $0) } != true
                if partial { budget.note(url, "This file changed or became unavailable while it was measured.") }
            } else {
                guard DRFiles.isDirectory(metadata) else { throw DRReadError.invalidRoot }
                try budget.resource()
                let measured = try DRFiles.measure(url, budget: budget, beforeFinalValidation: beforeResourceValidation,
                                                   files: files, recordsEvidence: false)
                allocatedBytes = measured.allocated
                partial = measured.partial
            }
            return DeveloperAIStorageResource(tool: tool, title: location.title, url: url,
                allocatedBytes: allocatedBytes, isPartial: partial, category: location.category)
        } catch DRReadError.missing {
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch is DRStop {
            throw DRStop.limit
        } catch {
            budget.note(url, "This AI tool location could not be measured safely.")
            return nil
        }
    }

    private func readStorage(in root: URL, kind: DeveloperStorageKind, budget: DRBudget) throws -> DeveloperStorageResource? {
        do {
            try DRFiles.directory(root)
            if kind == .simulatorDevices, try !DRFiles.isSimulatorDeviceSet(root, budget: budget) {
                budget.note(root, "Choose the Simulator Devices folder containing the simulator device set.")
                return nil
            }
            try budget.resource()
            let bytes = try DRFiles.measure(root, budget: budget, beforeFinalValidation: beforeResourceValidation,
                                            staysOnVolume: kind == .simulatorDevices)
            return DeveloperStorageResource(kind: kind, url: root, allocatedBytes: bytes.allocated, isPartial: bytes.partial)
        } catch DRReadError.missing where kind != .simulatorDevices {
            return nil
        } catch is CancellationError {
            throw CancellationError()
        } catch is DRStop {
            throw DRStop.limit
        } catch {
            budget.note(root, "This tool storage folder could not be measured safely.")
            return nil
        }
    }

    private func readToolchains(in root: URL, kind: RoomDevPinKind, approvals: [URL], budget: DRBudget,
                                seen: inout Set<String>, results: inout [DeveloperToolchainResource]) throws {
        do {
            for child in try DRFiles.children(root, budget: budget) {
                try budget.check()
                let version: String?
                switch kind {
                case .ndk: version = RoomDevParse.version(child.lastPathComponent)
                case .kotlinNative: version = RoomDevParse.konan(child.lastPathComponent)
                case .derivedData: version = child.lastPathComponent
                case .gradle: return
                }
                guard let version, seen.insert(child.path).inserted else { continue }
                do {
                    guard DRFiles.isDirectory(try DRFiles.metadata(child)) else { continue }
                    try budget.resource()
                    let measured = try DRFiles.measure(child, budget: budget, beforeFinalValidation: beforeResourceValidation)
                    var artifact = DeveloperToolchainResource(path: child.path, kind: kind, version: version,
                                                              bytes: measured.allocated, partial: measured.partial)
                    if kind == .derivedData {
                        let info = child.appendingPathComponent("info.plist")
                        do {
                            if let raw = RoomDevParse.derivedDataWorkspace(try DRFiles.data(info, budget: budget,
                                                                         limit: budget.limits.maximumProjectFileBytes)) {
                                let workspace = URL(fileURLWithPath: raw).roomLexicallyNormalized
                                artifact.workspacePath = workspace.path
                                if approvals.contains(where: { DRFiles.contains(workspace, in: $0) }) {
                                    artifact.workspacePresent = DRFiles.presence(workspace)
                                }
                            }
                        } catch is CancellationError { throw CancellationError() }
                        catch is DRStop { throw DRStop.limit }
                        catch { /* This artifact has an unknown workspace. */ }
                    }
                    results.append(artifact)
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { budget.note(child, "This toolchain could not be measured safely.") }
            }
        } catch is CancellationError { throw CancellationError() }
        catch is DRStop { throw DRStop.limit }
        catch { budget.note(root, "This toolchain location is unavailable or cannot be read safely.") }
    }

    private func androidDevice(_ url: URL, request: DeveloperResourcesRequest, budget: DRBudget) throws -> AndroidVirtualDeviceResource {
        _ = try DRFiles.directory(url)
        var config: [String: String] = [:], configPartial = false
        let configURL = url.appendingPathComponent("config.ini")
        do {
            config = try DRProperties.selected(try DRFiles.text(configURL, budget: budget), keys: [
                "avd.ini.displayname", "AvdId", "target", "abi.type", "hw.cpu.arch", "hw.device.name", "hw.device.manufacturer", "image.sysdir.1"
            ])
        } catch is CancellationError { throw CancellationError() }
        catch is DRStop { throw DRStop.limit }
        catch { configPartial = true; budget.note(configURL, "AVD configuration is missing, malformed, changed or exceeds the bounded read size. Some device details are unknown.") }
        let measured = try DRFiles.measure(url, budget: budget, beforeFinalValidation: beforeResourceValidation)
        let name = String(url.lastPathComponent.dropLast(4))
        let api = DRProperties.androidAPI(config["target"]) ?? DRProperties.androidAPI(config["image.sysdir.1"])
        let hardware = [config["hw.device.manufacturer"], config["hw.device.name"]].compactMap { $0 }.joined(separator: " ")
        return AndroidVirtualDeviceResource(url: url, name: name,
            displayName: config["avd.ini.displayname"] ?? config["AvdId"] ?? name,
            apiLevel: api, abi: config["abi.type"] ?? config["hw.cpu.arch"], device: hardware.isEmpty ? nil : hardware,
            allocatedBytes: measured.allocated, logicalBytes: measured.logical,
            isPartial: measured.partial || configPartial, lastUsedAt: nil,
            lastUseNote: "Last launch is not recorded reliably in the inspected standard files. Log, launch-record, snapshot and file dates below are evidence only; they do not establish last use or that this device is unnecessary.",
            evidence: measured.evidence,
            activity: try activity(for: url, avdName: name, measured: measured, snapshot: request.activity, budget: budget))
    }

    private func simulatorDevice(_ url: URL, id: UUID, volume: dev_t, budget: DRBudget) throws -> SimulatorDeviceResource {
        let original = try DRFiles.directory(url)
        guard original.st_dev == volume else { throw DRReadError.invalidRoot }
        let metadataURL = url.appendingPathComponent("device.plist")
        let data = try DRFiles.data(metadataURL, budget: budget, limit: budget.limits.maximumFileBytes)
        guard let fields = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = (fields["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name.rangeOfCharacter(from: .controlCharacters) == nil else { throw DRReadError.malformed }
        if let rawID = fields["UDID"] ?? fields["udid"], (rawID as? String).flatMap(UUID.init(uuidString:)) != id {
            throw DRReadError.malformed
        }
        // These are descriptive identifiers from the device's local plist. They do not resolve to paths.
        func identifier(_ value: Any?, prefix: String) -> String? {
            guard let value = value as? String, value.hasPrefix(prefix), value.count <= 200,
                  value.count > prefix.count,
                  value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) })
            else { return nil }
            return value
        }
        let runtime = identifier(fields["runtime"] ?? fields["runtimeIdentifier"], prefix: "com.apple.CoreSimulator.SimRuntime.")
        let type = identifier(fields["deviceType"] ?? fields["deviceTypeIdentifier"], prefix: "com.apple.CoreSimulator.SimDeviceType.")
        guard runtime != nil || type != nil else { throw DRReadError.malformed }
        let measured = try DRFiles.measure(url, budget: budget, beforeFinalValidation: beforeResourceValidation,
                                           recordsEvidence: false, staysOnVolume: true)
        guard DRFiles.same(original, try DRFiles.directory(url)) else { throw DRReadError.changed }
        return SimulatorDeviceResource(url: url, displayName: String(name.prefix(160)), runtimeIdentifier: runtime,
            deviceTypeIdentifier: type, allocatedBytes: measured.allocated, isPartial: measured.partial)
    }

    private func activity(for url: URL, avdName: String?, measured: DRMeasurement,
                          snapshot: DeveloperActivitySnapshot, budget: DRBudget) throws -> DeveloperResourceActivity {
        if budget.limited {
            return DeveloperResourceActivity(state: .unknown, processIDs: [],
                indicators: ["The scan limit prevented complete activity review. Running or idle status remains unknown."], sampledAt: snapshot.sampledAt)
        }
        var exact: [DeveloperResourceProcess] = [], named: [DeveloperResourceProcess] = [], related: [DeveloperResourceProcess] = []
        for process in snapshot.processes {
            try budget.check()
            if process.paths.contains(where: { $0.isFileURL && DRFiles.contains($0.roomLexicallyNormalized, in: url) }) { exact.append(process) }
            if avdName.map({ process.avdNames.contains($0) }) ?? false { named.append(process) }
            let name = process.name.lowercased()
            if avdName == nil ? name.contains("gradle") || name == "java" : name.contains("emulator") || name.contains("qemu") { related.append(process) }
        }
        var indicators = exact.map { "Observed file or working-directory use by \($0.name) (PID \($0.processID))." }
        if !named.isEmpty { indicators.append("A process sample names this AVD; this is not a verified live process-to-device identity.") }
        if measured.evidence.contains(where: { $0.kind == .lockPresent }) { indicators.append("Lock indicators are present. Locks may remain after an emulator or build exits.") }
        if exact.isEmpty && !related.isEmpty { indicators.append("A related emulator/build process was sampled; its resource ownership is not established.") }
        let state: DeveloperResourceActivityState
        if !exact.isEmpty { state = .observedUse }
        else if !indicators.isEmpty { state = .possibleUse }
        else if snapshot.isComplete { state = .notObserved; indicators.append("No use was observed in the supplied sample. This does not prove the resource is unused.") }
        else { state = .unknown; indicators.append("Complete process activity was not available. Running or idle status is unknown.") }
        return DeveloperResourceActivity(state: state, processIDs: Array(Set(exact.map(\.processID) + named.map(\.processID))).sorted(),
            indicators: indicators, sampledAt: snapshot.sampledAt)
    }
}

private final class DRBudget {
    let limits: DeveloperResourcesLimits
    let deadline: ContinuousClock.Instant
    var nodes = 0, resources = 0
    var limited = false
    var issues: [ScanIssue] = []
    init(_ limits: DeveloperResourcesLimits) {
        self.limits = limits; deadline = ContinuousClock.now.advanced(by: .seconds(limits.timeLimit))
    }
    func check() throws {
        try Task.checkCancellation()
        guard !limited, ContinuousClock.now < deadline else { limited = true; throw DRStop.limit }
    }
    func node() throws {
        try check(); nodes += 1
        guard nodes <= limits.maximumNodes else { limited = true; throw DRStop.limit }
    }
    func resource() throws {
        try check(); resources += 1
        guard resources <= limits.maximumResources else { limited = true; throw DRStop.limit }
    }
    func note(_ url: URL, _ message: String) {
        if issues.count < 128 { issues.append(ScanIssue(url: url, message: message)) }
    }
}
private enum DRStop: Error { case limit }
private enum DRReadError: Error { case invalidRoot, missing, unreadable, malformed, oversize, changed }

private struct DRAIStorageLocation {
    let path: String
    let title: String
    let category: DeveloperAIStorageCategory
    let isFile: Bool

    init(_ path: String, _ title: String, _ category: DeveloperAIStorageCategory, isFile: Bool = false) {
        self.path = path
        self.title = title
        self.category = category
        self.isFile = isFile
    }

    static func catalogue(for tool: DeveloperAITool) -> [Self] {
        let renderingCaches: [Self] = [
            .init("Cache", "App cache", .cache), .init("Code Cache", "Code cache", .cache),
            .init("GPUCache", "Graphics cache", .cache), .init("ShaderCache", "Shader cache", .cache),
            .init("Default/Cache", "Default profile cache", .cache),
            .init("Default/Code Cache", "Default profile code cache", .cache),
            .init("Default/GPUCache", "Default profile graphics cache", .cache),
        ]
        switch tool {
        case .codex:
            return renderingCaches + [
                .init("cache", "Tool cache", .cache),
                .init("models_cache.json", "Model catalogue cache", .cache, isFile: true),
                .init("log", "Diagnostic logs", .diagnostics),
                .init("history.jsonl", "Prompt history", .history, isFile: true),
                .init("sessions", "Sessions", .history),
                .init("archived_sessions", "Archived sessions", .history),
                .init("packages", "Runtime packages", .runtime),
                .init(".tmp", "Tool staging and active work", .runtime),
                .init("worktrees", "Worktree files and builds", .worktrees),
            ]
        case .claudeCode:
            return renderingCaches + [
                .init("cache/model-catalog", "Model catalogue cache", .cache),
                .init("cache/changelog.md", "Cached changelog", .cache, isFile: true),
                .init("debug", "Diagnostic logs", .diagnostics),
                .init("projects", "Project sessions", .history),
                .init("file-history", "File history", .history),
                .init("downloads", "Tool downloads", .runtime),
                .init("worktrees", "Worktree files and builds", .worktrees),
            ]
        case .chatGPT:
            return renderingCaches + [
                .init("NetworkCache", "Network cache", .cache),
                .init("WebKit/NetworkCache", "WebKit network cache", .cache),
            ]
        case .cursor:
            return renderingCaches + [
                .init("CachedData", "Cached app data", .cache),
                .init("CachedExtensionVSIXs", "Extension download cache", .cache),
            ]
        case .gemini:
            return [
                .init("history", "Project checkpoints", .history),
                .init("tmp", "Workspace data and sessions", .history),
            ]
        case .copilot:
            return [
                .init("logs", "Session logs", .diagnostics),
                .init("session-state", "Sessions and workspace data", .history),
                .init("command-history-state", "Command history", .history),
                .init("session-store.db", "Session index", .history, isFile: true),
            ]
        case .ollama:
            return [.init("logs", "App and server logs", .diagnostics), .init("models", "Installed models", .runtime)]
        }
    }
}

private final class DRMeasuredFiles {
    private struct Location: Hashable {
        let device: dev_t
        let inode: ino_t
    }
    private var measured: Set<Location> = []

    func add(_ metadata: stat) -> Bool {
        measured.insert(Location(device: metadata.st_dev, inode: metadata.st_ino)).inserted
    }

    func allocatedBytes(adding metadata: stat) -> Int64 {
        add(metadata) ? max(0, Int64(metadata.st_blocks)) * 512 : 0
    }
}
private struct DRMeasurement { var allocated: Int64 = 0; var logical: Int64 = 0; var partial = false; var evidence: [DeveloperResourceEvidence] = [] }

private enum DROwnership {
    case currentUser, readable

    func allows(_ info: stat) -> Bool { self == .readable || info.st_uid == getuid() }
}

private enum DRSimulatorRuntimes {
    private static let bundlePrefix = "com.apple.CoreSimulator.SimRuntime."
    private static let assetPrefix = "com.apple.MobileAsset."
    private static let assetSuffix = "SimulatorRuntime"

    static func read(in root: URL, budget: DRBudget, files: DRMeasuredFiles,
                     beforeFinalValidation: ((URL) -> Void)?, results: inout [DeveloperStorageResource]) throws {
        do {
            let volume = try DRFiles.directory(root, ownership: .readable).st_dev
            let directPackage = ["simruntime", "asset"].contains(root.pathExtension.lowercased())
            let candidates = directPackage ? [root]
                : try DRFiles.children(root, budget: budget, ownership: .readable, volume: volume)
            let catalogue = candidates.contains(where: { $0.pathExtension.lowercased() == "dmg" })
                ? try imageCatalogue(in: root, volume: volume, budget: budget) : [:]
            for url in candidates {
                try budget.check()
                do {
                    switch url.pathExtension.lowercased() {
                    case "simruntime":
                        guard !results.contains(where: { $0.url.path == url.path }) else { continue }
                        let item = try bundle(url, volume: volume, budget: budget, beforeFinalValidation: beforeFinalValidation)
                        results.append(item)
                    case "asset":
                        try assetImages(in: url, volume: volume, budget: budget, files: files,
                                        beforeFinalValidation: beforeFinalValidation, results: &results)
                    case "dmg":
                        let declared = catalogue[url.path]
                        guard let metadata = declared ?? looseImageMetadata(url) else { continue }
                        try appendImage(url, metadata: metadata, checkTrailer: declared == nil, volume: volume,
                                        budget: budget, files: files, beforeFinalValidation: beforeFinalValidation, results: &results)
                    default: continue
                    }
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch {
                    budget.note(url, "This runtime backing item could not be measured safely. Mounted runtime views and links are skipped.")
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch is DRStop { throw DRStop.limit }
        catch { budget.note(root, "The approved Simulator Runtimes folder could not be read.") }
    }

    private static func bundle(_ url: URL, volume: dev_t, budget: DRBudget,
                               beforeFinalValidation: ((URL) -> Void)?) throws -> DeveloperStorageResource {
        try budget.node()
        let original = try DRFiles.directory(url, ownership: .readable)
        guard original.st_dev == volume, try !DRFiles.readOnlyVolume(url) else { throw DRReadError.invalidRoot }
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        // A mounted runtime's metadata can look like a bundle while the actual OS lives in an image.
        let payloads = ["RuntimeRoot", "Resources/RuntimeRoot"].map { contents.appendingPathComponent($0) }
        guard payloads.contains(where: { (try? DRFiles.directory($0, ownership: .readable).st_dev) == volume })
        else { throw DRReadError.invalidRoot }
        let fields = try plist(contents.appendingPathComponent("Info.plist"), volume: volume, budget: budget)
        guard let fallbackName = bundleName(fields["CFBundleIdentifier"]) else { throw DRReadError.malformed }
        let metadata = SimulatorRuntimeMetadata(name: string(fields["CFBundleName"]) ?? fallbackName,
                                                build: string(fields["ProductBuildVersion"]))
        try budget.resource()
        let measurement = try DRFiles.measure(url, budget: budget, beforeFinalValidation: beforeFinalValidation,
                                               recordsEvidence: false, staysOnVolume: true, ownership: .readable)
        guard DRFiles.same(original, try DRFiles.directory(url, ownership: .readable)) else { throw DRReadError.changed }
        return .init(kind: .simulatorRuntimeBundle, url: url, allocatedBytes: measurement.allocated,
                     isPartial: measurement.partial, runtime: metadata)
    }

    private static func assetImages(in asset: URL, volume: dev_t, budget: DRBudget, files: DRMeasuredFiles,
                                    beforeFinalValidation: ((URL) -> Void)?, results: inout [DeveloperStorageResource]) throws {
        guard try DRFiles.directory(asset, ownership: .readable).st_dev == volume else { throw DRReadError.invalidRoot }
        let fields = try plist(asset.appendingPathComponent("Info.plist"), volume: volume, budget: budget)
        guard let identifier = string(fields["CFBundleIdentifier"]), identifier.hasPrefix(assetPrefix),
              identifier.hasSuffix(assetSuffix), let platform = platformName(String(identifier.dropFirst(assetPrefix.count).dropLast(assetSuffix.count)))
        else { return }
        let properties = fields["MobileAssetProperties"] as? [String: Any] ?? [:]
        let name = string(properties["SimulatorVersion"]).map { "\(platform) \($0)" } ?? "\(platform) Simulator Runtime"
        let metadata = SimulatorRuntimeMetadata(name: name, build: string(properties["Build"]))
        let payloads = asset.appendingPathComponent("AssetData/Restore", isDirectory: true)
        for image in try DRFiles.children(payloads, budget: budget, ownership: .readable, volume: volume)
        where image.pathExtension.lowercased() == "dmg" {
            do {
                try appendImage(image, metadata: metadata, checkTrailer: false, volume: volume,
                                budget: budget, files: files, beforeFinalValidation: beforeFinalValidation, results: &results)
            } catch is CancellationError { throw CancellationError() }
            catch is DRStop { throw DRStop.limit }
            catch { budget.note(image, "This Simulator runtime image was inaccessible, linked or changed.") }
        }
    }

    private static func appendImage(_ url: URL, metadata: SimulatorRuntimeMetadata, checkTrailer: Bool, volume: dev_t,
                                    budget: DRBudget, files: DRMeasuredFiles, beforeFinalValidation: ((URL) -> Void)?,
                                    results: inout [DeveloperStorageResource]) throws {
        try budget.node()
        guard !results.contains(where: { $0.url.path == url.path }) else { return }
        let info = try DRFiles.metadata(url, ownership: .readable)
        guard DRFiles.isRegular(info), info.st_dev == volume, info.st_size > 0 else { throw DRReadError.invalidRoot }
        if checkTrailer, try !DRFiles.hasDiskImageTrailer(url, matching: info) { return }
        beforeFinalValidation?(url)
        guard DRFiles.same(info, try DRFiles.metadata(url, ownership: .readable)) else { throw DRReadError.changed }
        guard files.add(info) else { return }
        try budget.resource()
        results.append(.init(kind: .simulatorRuntimeImage, url: url, allocatedBytes: max(0, Int64(info.st_blocks)) * 512,
                             isPartial: false, runtime: metadata))
    }

    private static func imageCatalogue(in root: URL, volume: dev_t, budget: DRBudget) throws -> [String: SimulatorRuntimeMetadata] {
        let url = root.appendingPathComponent("images.plist")
        do {
            _ = try DRFiles.metadata(url, ownership: .readable)
            let fields = try plist(url, volume: volume, budget: budget)
            var images: [String: SimulatorRuntimeMetadata] = [:]
            for image in (fields["images"] as? [[String: Any]] ?? []).prefix(budget.limits.maximumResources) {
                try budget.node()
                let path = (image["path"] as? [String: Any])?["relative"] ?? image["path"]
                guard let path = string(path, limit: 4_096), let candidate = localImage(path, in: root),
                      let info = image["runtimeInfo"] as? [String: Any], let name = bundleName(info["bundleIdentifier"])
                else { continue }
                images[candidate.path] = .init(name: name, build: string(info["build"]))
            }
            return images
        } catch DRReadError.missing { return [:] }
        catch is CancellationError { throw CancellationError() }
        catch is DRStop { throw DRStop.limit }
        catch {
            budget.note(url, "The runtime image catalogue could not be read safely.")
            return [:]
        }
    }

    private static func localImage(_ path: String, in root: URL) -> URL? {
        let url: URL
        if path.hasPrefix("file:") {
            guard let local = URL(string: path), local.isFileURL, (local.host ?? "").isEmpty || local.host == "localhost" else { return nil }
            url = local.roomLexicallyNormalized
        } else {
            url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).roomLexicallyNormalized
        }
        return url.deletingLastPathComponent().path == root.path && url.pathExtension.lowercased() == "dmg" ? url : nil
    }

    private static func plist(_ url: URL, volume: dev_t, budget: DRBudget) throws -> [String: Any] {
        let data = try DRFiles.data(url, budget: budget, limit: budget.limits.maximumFileBytes, ownership: .readable, volume: volume)
        guard let fields = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw DRReadError.malformed }
        return fields
    }

    private static func string(_ value: Any?, limit: Int = 160) -> String? {
        guard let value = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= limit, value.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return value
    }

    private static func platformName(_ name: String) -> String? {
        switch name.lowercased() {
        case "ios": "iOS"
        case "tvos": "tvOS"
        case "watchos": "watchOS"
        case "visionos", "xros": "visionOS"
        default: nil
        }
    }

    private static func bundleName(_ value: Any?) -> String? {
        guard let identifier = string(value), identifier.hasPrefix(bundlePrefix) else { return nil }
        let parts = identifier.dropFirst(bundlePrefix.count).split(separator: "-")
        guard let platform = parts.first.flatMap({ platformName(String($0)) }) else { return nil }
        let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        return version.isEmpty ? "\(platform) Simulator Runtime" : "\(platform) \(version)"
    }

    private static func looseImageMetadata(_ url: URL) -> SimulatorRuntimeMetadata? {
        let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        guard name.localizedCaseInsensitiveContains("Simulator Runtime"),
              let first = name.split(separator: " ").first, platformName(String(first)) != nil,
              let display = string(name) else { return nil }
        return .init(name: display, build: nil)
    }
}

private enum DRFiles {
    static func contains(_ child: URL, in parent: URL) -> Bool { child.path == parent.path || child.path.hasPrefix(parent.path + "/") }
    static func isDirectory(_ info: stat) -> Bool { info.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    static func isRegular(_ info: stat) -> Bool { info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    static func isSimulatorDeviceSet(_ root: URL, budget: DRBudget, children: [URL]? = nil) throws -> Bool {
        func hasMarker(_ directory: URL, named name: String) -> Bool {
            (try? metadata(directory.appendingPathComponent(name))).map(isRegular) ?? false
        }
        if hasMarker(root, named: "device_set.plist") { return true }
        return try (children ?? Self.children(root, budget: budget)).contains {
            UUID(uuidString: $0.lastPathComponent) != nil && hasMarker($0, named: "device.plist")
        }
    }
    static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_size == b.st_size
            && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
            && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    static func openDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.pathComponents.count <= 128 else { throw DRReadError.invalidRoot }
        var fd = open("/", O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DRReadError.unreadable }
        for component in url.pathComponents where component != "/" {
            let next = openat(fd, component, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let failure = errno
            close(fd)
            guard next >= 0 else { throw failure == ENOENT ? DRReadError.missing : DRReadError.unreadable }
            fd = next
        }
        return fd
    }
    @discardableResult static func directory(_ url: URL, ownership: DROwnership = .currentUser) throws -> stat {
        let fd = try openDirectory(url); defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, isDirectory(info), ownership.allows(info) else { throw DRReadError.invalidRoot }
        return info
    }
    static func readOnlyVolume(_ url: URL) throws -> Bool {
        let fd = try openDirectory(url); defer { close(fd) }
        var info = statfs()
        guard fstatfs(fd, &info) == 0 else { throw DRReadError.unreadable }
        return info.f_flags & UInt32(MNT_RDONLY) != 0
    }
    static func metadata(_ url: URL, ownership: DROwnership = .currentUser) throws -> stat {
        let fd = try openDirectory(url.deletingLastPathComponent()); defer { close(fd) }
        var info = stat()
        guard fstatat(fd, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw errno == ENOENT ? DRReadError.missing : DRReadError.unreadable
        }
        guard ownership.allows(info) else { throw DRReadError.unreadable }
        return info
    }
    static func hasDiskImageTrailer(_ url: URL, matching expected: stat) throws -> Bool {
        guard expected.st_size >= 512 else { return false }
        let parent = try openDirectory(url.deletingLastPathComponent()); defer { close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw DRReadError.unreadable }; defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, same(before, expected) else { throw DRReadError.changed }
        // An exported UDIF image advertises its format in the final 512-byte record.
        var signature = [UInt8](repeating: 0, count: 4)
        let count = pread(fd, &signature, signature.count, before.st_size - 512)
        var after = stat()
        guard count == signature.count, fstat(fd, &after) == 0, same(before, after) else { throw DRReadError.changed }
        return signature == Array("koly".utf8)
    }
    static func children(_ url: URL, budget: DRBudget, ownership: DROwnership = .currentUser, volume: dev_t? = nil) throws -> [URL] {
        try budget.node()
        let fd = try openDirectory(url); defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, ownership.allows(info), volume == nil || volume == info.st_dev else { throw DRReadError.unreadable }
        // Reopen the exact directory for readdir; O_SEARCH itself is not readable.
        let readable = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard readable >= 0 else { throw DRReadError.unreadable }
        guard let stream = fdopendir(readable) else { close(readable); throw DRReadError.unreadable }
        defer { closedir(stream) }
        var result: [URL] = []
        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            try budget.node()
            result.append(url.appendingPathComponent(name, isDirectory: false))
            errno = 0
        }
        guard errno == 0 else { throw DRReadError.unreadable }
        var end = stat()
        guard fstat(fd, &end) == 0, same(info, end) else { throw DRReadError.changed }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    static func presence(_ url: URL) -> Bool? {
        do {
            let parent = try openDirectory(url.deletingLastPathComponent())
            defer { close(parent) }
            var info = stat()
            guard fstatat(parent, url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                return errno == ENOENT ? false : nil
            }
            return info.st_uid == getuid() && (isDirectory(info) || isRegular(info)) ? true : nil
        } catch DRReadError.missing { return false }
        catch { return nil }
    }

    static func text(_ url: URL, budget: DRBudget, limit: Int? = nil) throws -> String {
        let bytes = try data(url, budget: budget, limit: limit ?? budget.limits.maximumFileBytes)
        guard let text = String(data: bytes, encoding: .utf8), !text.contains("\0") else { throw DRReadError.malformed }
        return text
    }

    static func data(_ url: URL, budget: DRBudget, limit: Int, ownership: DROwnership = .currentUser, volume: dev_t? = nil) throws -> Data {
        try budget.node()
        let parent = try openDirectory(url.deletingLastPathComponent()); defer { close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw DRReadError.unreadable }; defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, ownership.allows(before), isRegular(before), before.st_nlink == 1,
              volume == nil || volume == before.st_dev else { throw DRReadError.unreadable }
        guard before.st_size >= 0, before.st_size <= limit else { throw DRReadError.oversize }
        var bytes = Data(), chunk = [UInt8](repeating: 0, count: 8_192)
        bytes.reserveCapacity(Int(before.st_size))
        while true {
            try budget.check()
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw DRReadError.unreadable }
            bytes.append(contentsOf: chunk.prefix(count))
            guard bytes.count <= limit else { throw DRReadError.oversize }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, same(before, after) else { throw DRReadError.changed }
        return bytes
    }
    static func measure(_ url: URL, budget: DRBudget, beforeFinalValidation: ((URL) -> Void)?,
                        files: DRMeasuredFiles = DRMeasuredFiles(), recordsEvidence: Bool = true,
                        staysOnVolume: Bool = false, ownership: DROwnership = .currentUser) throws -> DRMeasurement {
        var result = DRMeasurement()
        var latest: Date?
        let root = try directory(url, ownership: ownership)
        func walk(_ current: URL, depth: Int) throws {
            try budget.check()
            guard depth <= budget.limits.maximumDepth else { result.partial = true; budget.note(current, "The resource depth limit was reached."); return }
            let entries = try children(current, budget: budget, ownership: ownership, volume: staysOnVolume ? root.st_dev : nil)
            for child in entries {
                do {
                    let info = try metadata(child, ownership: ownership)
                    if staysOnVolume, info.st_dev != root.st_dev {
                        result.partial = true
                        budget.note(child, "An item on another volume was skipped.")
                        continue
                    }
                    if recordsEvidence {
                        let date = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
                        if latest == nil || date > latest! { latest = date }
                        let relative = String(child.path.dropFirst(url.path.count + 1))
                        if result.evidence.count < 32, let evidence = evidence(child, relative: relative, info: info) {
                            result.evidence.append(evidence)
                        }
                    }
                    if isDirectory(info) { try walk(child, depth: depth + 1) }
                    else if isRegular(info) {
                        if files.add(info) {
                            result.allocated += max(0, Int64(info.st_blocks)) * 512
                            result.logical += max(0, Int64(info.st_size))
                        }
                    } else { result.partial = true; budget.note(child, "A link or special item was skipped; its target was not inspected.") }
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { result.partial = true; budget.note(child, "An item is inaccessible, changed or not owned by this user; size is a lower bound.") }
            }
        }
        do { try walk(url, depth: 0) }
        catch is CancellationError { throw CancellationError() }
        catch is DRStop { result.partial = true }
        catch { result.partial = true; budget.note(url, "Resource measurement was incomplete.") }
        beforeFinalValidation?(url)
        if (try? directory(url, ownership: ownership)).map({ same(root, $0) }) != true {
            result.partial = true
            budget.note(url, "The resource changed or became unavailable while it was measured.")
        }
        if let latest {
            result.evidence.append(DeveloperResourceEvidence(kind: .filesystemChanged, label: "Latest measured file change", url: url, date: latest,
                uncertainty: "File modification is not a last-launch or last-build timestamp."))
        }
        return result
    }
    static func evidence(_ url: URL, relative: String, info: stat) -> DeveloperResourceEvidence? {
        let name = url.lastPathComponent.lowercased(), lower = relative.lowercased()
        let date = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        let kind: DeveloperResourceEvidenceKind, label: String, note: String
        if name.hasSuffix(".lock") || name.hasSuffix(".lck") {
            kind = .lockPresent; label = "Lock indicator present"; note = "A lock may be stale. Its presence does not prove a live process."
        } else if name == "emu-launch-params.txt" {
            kind = .launchRecordChanged; label = "Launch record modified"; note = "This is the file's modification date, not a verified emulator launch time."
        } else if ["emulator.log", "emulator-launch.log", "launch.log"].contains(name) {
            kind = .logChanged; label = "Available emulator log modified"; note = "Only file metadata was inspected; a log change does not establish last launch."
        } else if lower.hasPrefix("snapshots/") && ["snapshot.pb", "ram.img", "snapshot.lock"].contains(name) {
            kind = .snapshotChanged; label = "Snapshot file modified"; note = "Snapshots preserve device/app/user state. A saved-file date does not prove last use or safe removal."
        } else if name == "config.ini" {
            kind = .configurationChanged; label = "AVD configuration modified"; note = "Configuration edits are not emulator launch evidence."
        } else { return nil }
        return DeveloperResourceEvidence(kind: kind, label: label, url: url, date: date, uncertainty: note)
    }
}

private enum DRProjects {
    static let skipped: Set<String> = [".git", ".gradle", ".build", ".claude", ".codex", "node_modules", "build", "dist", "Pods", "vendor",
        "local.properties", "gradle.properties", ".env", ".env.local"]
    static let settingsNames: Set<String> = ["settings.gradle.kts", "settings.gradle"]
    static let buildNames: Set<String> = ["build.gradle.kts", "build.gradle"]

    struct Sources {
        var wrapper: URL?
        var catalog: URL?
        var scripts: [URL] = []
        var xcode = false
    }

    static func find(_ root: URL, budget: DRBudget, wrappers: inout [GradleProjectWrapper],
                     projects: inout [String: DeveloperProject]) throws {
        var sources: [String: Sources] = [:]
        var buildFiles: [URL] = []
        func walk(_ url: URL, depth: Int) throws {
            try budget.check()
            guard depth <= budget.limits.maximumDepth else {
                budget.note(url, "Nested project search reached its depth limit.")
                return
            }
            for child in try DRFiles.children(url, budget: budget) {
                let name = child.lastPathComponent
                if skipped.contains(name) || name.hasPrefix(".env.") { continue }
                do {
                    let info = try DRFiles.metadata(child)
                    if DRFiles.isDirectory(info) {
                        if name.hasSuffix(".xcodeproj") { sources[url.path, default: Sources()].xcode = true }
                        else { try walk(child, depth: depth + 1) }
                    } else if DRFiles.isRegular(info) {
                        if settingsNames.contains(name) {
                            sources[url.path, default: Sources()].scripts.append(child)
                        } else if buildNames.contains(name) {
                            buildFiles.append(child)
                        } else if name == "libs.versions.toml", url.lastPathComponent == "gradle",
                                  url.path != root.path {
                            sources[url.deletingLastPathComponent().path, default: Sources()].catalog = child
                        } else if name == "gradle-wrapper.properties", url.lastPathComponent == "wrapper",
                                  url.deletingLastPathComponent().lastPathComponent == "gradle" {
                            let project = url.deletingLastPathComponent().deletingLastPathComponent()
                            if DRFiles.contains(project, in: root) {
                                sources[project.path, default: Sources()].wrapper = child
                            }
                        }
                    } else {
                        budget.note(child, "A linked or special project item was skipped; its target was not inspected.")
                    }
                } catch is CancellationError { throw CancellationError() }
                catch is DRStop { throw DRStop.limit }
                catch { budget.note(child, "A project item is inaccessible or changed. No symbolic-link target was followed.") }
            }
        }
        try walk(root, depth: 0)

        // Nearest Gradle root owns each module's build script. Keep standalone
        // scripts as project roots when there is no wrapper, catalog or settings.
        for script in buildFiles.sorted(by: { $0.pathComponents.count < $1.pathComponents.count }) {
            let start = script.deletingLastPathComponent()
            var candidate = start
            var owner: String?
            while DRFiles.contains(candidate, in: root) {
                if let found = sources[candidate.path], found.wrapper != nil || found.catalog != nil || !found.scripts.isEmpty {
                    owner = candidate.path
                    break
                }
                if candidate.path == root.path { break }
                candidate.deleteLastPathComponent()
            }
            sources[owner ?? start.path, default: Sources()].scripts.append(script)
        }

        for (path, files) in sources.sorted(by: { $0.key < $1.key }) {
            try budget.resource()
            let url = URL(fileURLWithPath: path, isDirectory: true)
            var project = DeveloperProject(root: path, name: url.lastPathComponent, hasXcodeProject: files.xcode)
            if let wrapper = files.wrapper {
                let parsed = try readWrapper(wrapper, project: url, budget: budget)
                wrappers.append(parsed)
                if let version = parsed.version, let type = parsed.distributionType {
                    project.gradle = DeveloperProject.GradlePin(version: version, type: type)
                }
            }
            let catalog: RoomDevParse.Catalog?
            if let url = files.catalog { catalog = try readScript(url, budget: budget).flatMap(RoomDevParse.versionCatalog) }
            else { catalog = nil }
            project.agp = catalog?.agp
            project.kotlin = catalog?.kotlin
            for script in files.scripts {
                guard let text = try readScript(script, budget: budget),
                      let parsed = RoomDevParse.buildScript(text, catalog: catalog) else { continue }
                project.agp = project.agp ?? parsed.agp
                project.kotlin = project.kotlin ?? parsed.kotlin
                project.ndk = project.ndk ?? parsed.ndk
                project.multiplatform = project.multiplatform || parsed.appliesMultiplatform
                project.appleNativeTargets = project.appleNativeTargets || parsed.appleNativeTargets
            }
            projects[path] = project
        }
    }

    private static func readWrapper(_ file: URL, project: URL, budget: DRBudget) throws -> GradleProjectWrapper {
        let parsed: (version: String, type: String)?
        do {
            parsed = RoomDevParse.wrapper(try DRFiles.text(file, budget: budget))
        } catch is CancellationError { throw CancellationError() }
        catch is DRStop { throw DRStop.limit }
        catch {
            parsed = nil
            budget.note(file, "Wrapper metadata is malformed, changed, inaccessible or exceeds the bounded read size.")
        }
        return GradleProjectWrapper(projectURL: project, propertiesURL: file, version: parsed?.version,
                                    distributionType: parsed?.type,
                                    note: parsed == nil ? "The selected wrapper's version is unknown. No URL credentials are retained."
                                        : "Version inferred from this wrapper's distribution filename. This does not establish when the project last ran.",
                                    isPartial: parsed == nil)
    }

    private static func readScript(_ file: URL, budget: DRBudget) throws -> String? {
        do { return try DRFiles.text(file, budget: budget, limit: budget.limits.maximumProjectFileBytes) }
        catch is CancellationError { throw CancellationError() }
        catch is DRStop { throw DRStop.limit }
        catch {
            budget.note(file, "Project version metadata could not be read safely or exceeds the bounded read size.")
            return nil
        }
    }
}

enum DRProperties {
    static func selected(_ text: String, keys: Set<String>) throws -> [String: String] {
        var result: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") || line.hasPrefix("!") { continue }
            guard line.utf8.count <= 4_096 else { throw DRReadError.malformed }
            guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key) else { continue }
            guard result[key] == nil else { throw DRReadError.malformed }
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            guard value.utf8.count <= (key == "distributionUrl" ? 2_048 : 256) else { throw DRReadError.oversize }
            guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw DRReadError.malformed }
            result[key] = value
        }
        return result
    }
    static func androidAPI(_ value: String?) -> String? {
        guard let value else { return nil }
        for component in value.split(separator: "/") where component.hasPrefix("android-") {
            let api = String(component.dropFirst(8))
            if !api.isEmpty, api.count <= 40, api.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._".contains($0)) }) { return api }
        }
        return nil
    }
}

enum DRVersions {
    static func version(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= 96 else { return nil }
        let main = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = main[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(numbers.count), numbers.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }) else { return nil }
        if main.count == 2 {
            guard !main[1].isEmpty, main[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-+".contains($0)) }) else { return nil }
        }
        return text
    }
    static func distribution(_ name: String) -> (version: String, type: String)? {
        let stem = name.hasSuffix(".zip") ? String(name.dropLast(4)) : name
        guard stem.hasPrefix("gradle-") else { return nil }
        for type in ["bin", "all"] where stem.hasSuffix("-" + type) {
            let value = String(stem.dropFirst(7).dropLast(type.count + 1))
            if let version = version(value) { return (version, type) }
        }
        return nil
    }
    static func distributionURL(_ raw: String) -> (version: String, type: String)? {
        // Read only the filename. Discard host, query, tokens, and userinfo.
        let value = raw.replacingOccurrences(of: "\\:", with: ":").replacingOccurrences(of: "\\/", with: "/")
        guard !value.hasSuffix("\\"), let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["https", "http", "file"].contains(scheme),
              let name = components.path.split(separator: "/").last.map(String.init), name.hasSuffix(".zip") else { return nil }
        return distribution(name.removingPercentEncoding ?? name)
    }
}
