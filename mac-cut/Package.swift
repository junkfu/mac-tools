// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacCut",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacCut",
            path: "Sources/MacCut",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        )
    ]
)
