// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conductor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Conductor",
            path: "Conductor",
            exclude: ["Info.plist", "Conductor.entitlements"],
            resources: [.process("Assets.xcassets")]
        ),
        .testTarget(
            name: "ConductorTests",
            dependencies: ["Conductor"],
            path: "ConductorTests"
        ),
    ]
)
