// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoiceOSCore", targets: ["VoiceOSCore"]),
        .executable(name: "VoiceOSApp", targets: ["VoiceOSApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "VoiceOSCore",
            dependencies: []
        ),
        .executableTarget(
            name: "VoiceOSApp",
            dependencies: ["VoiceOSCore"]
        ),
        .testTarget(
            name: "VoiceOSCoreTests",
            dependencies: ["VoiceOSCore"]
        )
    ]
)

