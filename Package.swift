// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeyAgent",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "HeyAgent", targets: ["HeyAgent"]),
    ],
    targets: [
        .executableTarget(
            name: "HeyAgent",
            path: "Sources/HeyAgent"
        ),
    ]
)
