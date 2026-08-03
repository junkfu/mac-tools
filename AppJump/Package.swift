// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppJump",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AppJump",
            path: "Sources/AppJump",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
