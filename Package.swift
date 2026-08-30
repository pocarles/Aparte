// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aparte",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Aparte", targets: ["Aparte"]),
        .library(name: "AparteCore", targets: ["AparteCore"]),
    ],
    targets: [
        .target(
            name: "AparteCore",
            path: "Sources/AparteCore"
        ),
        .executableTarget(
            name: "Aparte",
            dependencies: ["AparteCore"],
            path: "Sources/Aparte"
        ),
        .testTarget(
            name: "AparteCoreTests",
            dependencies: ["AparteCore"],
            path: "Tests/AparteCoreTests"
        ),
    ]
)

