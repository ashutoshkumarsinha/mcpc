// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mcpc",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MCPC", targets: ["MCPC"]),
        .executable(name: "mcpc", targets: ["MCPClientCLI"]),
        .executable(name: "mcpc-gui", targets: ["MCPClientGUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpurnell/SwiftMCPClient.git", from: "0.9.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "MCPC",
            dependencies: [
                .product(name: "MCPClient", package: "SwiftMCPClient"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "MCPClientCLI",
            dependencies: ["MCPC"]
        ),
        .executableTarget(
            name: "MCPClientGUI",
            dependencies: [
                "MCPC",
                .product(name: "MCPClient", package: "SwiftMCPClient"),
            ]
        ),
    ]
)
