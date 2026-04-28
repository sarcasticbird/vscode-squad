// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeSquad",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CodeSquad",
            path: "CodeSquad",
            exclude: ["Info.plist", "CodeSquad.entitlements"],
            resources: [.process("Assets.xcassets")]
        ),
        .testTarget(
            name: "CodeSquadTests",
            dependencies: ["CodeSquad"],
            path: "CodeSquadTests"
        ),
    ]
)
