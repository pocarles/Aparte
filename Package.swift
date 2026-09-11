// swift-tools-version: 6.0
import PackageDescription
import Foundation

let directUpdates = ProcessInfo.processInfo.environment["APARTE_ENABLE_UPDATES"] == "1"

let package = Package(
    name: "Aparte",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aparte", targets: ["Aparte"]),
        .library(name: "AparteCore", targets: ["AparteCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(
            name: "AparteCore",
            path: "Sources/AparteCore"
        ),
        .executableTarget(
            name: "Aparte",
            dependencies: [.target(name: "AparteCore")] + (directUpdates ? [.product(name: "Sparkle", package: "Sparkle")] : []),
            path: "Sources/Aparte",
            swiftSettings: directUpdates ? [.define("APARTE_DIRECT_UPDATES")] : [],
            linkerSettings: directUpdates ? [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])] : []
        ),
        .testTarget(
            name: "AparteCoreTests",
            dependencies: ["AparteCore"],
            path: "Tests/AparteCoreTests"
        ),
    ]
)
