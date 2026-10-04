// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "LaserKit",
    platforms: [
        .visionOS(.v27),
        .iOS(.v27),
        .macOS(.v27),
    ],
    products: [
        .library(name: "ShowModel", targets: ["ShowModel"]),
        .library(name: "ShowAudio", targets: ["ShowAudio"]),
        .library(name: "LaserRendering", targets: ["LaserRendering"]),
    ],
    targets: [
        .target(name: "ShowModel"),
        .target(name: "ShowAudio", dependencies: ["ShowModel"]),
        // C header shared by Swift and Metal so GPU struct layouts can never drift apart.
        .target(name: "LaserShaderTypes"),
        .target(
            name: "LaserRendering",
            dependencies: ["ShowModel", "ShowAudio", "LaserShaderTypes"],
            resources: [.process("Shaders")]
        ),
        .testTarget(name: "ShowModelTests", dependencies: ["ShowModel"]),
        .testTarget(name: "ShowAudioTests", dependencies: ["ShowAudio"]),
        .testTarget(name: "LaserRenderingTests", dependencies: ["LaserRendering"]),
    ]
)
