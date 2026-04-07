// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "QuietWrite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuietWrite", targets: ["QuietWrite"])
    ],
    targets: [
        .executableTarget(
            name: "QuietWrite",
            path: "Sources/QuietWrite"
        )
    ]
)
