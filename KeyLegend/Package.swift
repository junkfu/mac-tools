// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyLegend",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyLegend",
            path: "Sources/KeyLegend",
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
