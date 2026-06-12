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
    ],
    dependencies: [
        .package(url: "https://github.com/jpurnell/SwiftMCPClient.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MCPC",
            dependencies: [
                .product(name: "MCPClient", package: "SwiftMCPClient"),
            ]
        ),
        .executableTarget(
            name: "MCPClientCLI",
            dependencies: ["MCPC"]
        ),
    ]
)
