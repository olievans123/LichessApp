// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LichessApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LichessApp", targets: ["LichessApp"])
    ],
    targets: [
        .executableTarget(
            name: "LichessApp",
            path: "LichessApp"
        )
    ]
)
