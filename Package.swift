// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Triggerit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Triggerit", targets: ["Triggerit"]),
    ],
    targets: [
        .executableTarget(
            name: "Triggerit",
            path: "Sources/Triggerit"
        ),
    ]
)
