// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMeter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeMeter", targets: ["ClaudeMeter"])
    ],
    targets: [
        // Thin @main shell so the logic below stays unit-testable.
        .executableTarget(
            name: "ClaudeMeter",
            dependencies: ["ClaudeMeterKit"],
            path: "Sources/ClaudeMeter"
        ),
        .target(
            name: "ClaudeMeterKit",
            path: "Sources/ClaudeMeterKit"
        ),
        // Developer tool: renders the real SwiftUI views to the PNGs used in
        // the README and to Resources/AppIcon.icns. Not part of the product.
        .executableTarget(
            name: "AssetGen",
            dependencies: ["ClaudeMeterKit"],
            path: "Sources/AssetGen"
        ),
        // Troubleshooting CLI: runs the exact token → fetch → parse path the app
        // uses and prints what it found. Never prints the token itself.
        .executableTarget(
            name: "claudemeter-doctor",
            dependencies: ["ClaudeMeterKit"],
            path: "Sources/Doctor"
        ),
        .testTarget(
            name: "ClaudeMeterKitTests",
            dependencies: ["ClaudeMeterKit"],
            path: "Tests/ClaudeMeterKitTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
