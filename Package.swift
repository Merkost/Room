// swift-tools-version: 6.2
import PackageDescription
import Foundation

let storeEdition = ProcessInfo.processInfo.environment["ROOM_EDITION"] == "store"
let editionSettings: [SwiftSetting] = storeEdition ? [.define("ROOM_APP_STORE")] : []

let package = Package(
    name: "Room",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Room", targets: ["RoomApp"])],
    targets: [
        .target(name: "RoomCore", swiftSettings: editionSettings),
        .executableTarget(
            name: "RoomApp",
            dependencies: ["RoomCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)] + editionSettings
        ),
        .testTarget(name: "RoomCoreTests", dependencies: ["RoomCore"], swiftSettings: editionSettings),
        .testTarget(name: "RoomAppTests", dependencies: ["RoomApp", "RoomCore"], swiftSettings: editionSettings)
    ],
    swiftLanguageModes: [.v6]
)
