// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitPilotCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "GitPilotCore", targets: ["GitPilotCore"])],
    targets: [
        .target(name: "GitPilotCore"),
        .testTarget(name: "GitPilotCoreTests", dependencies: ["GitPilotCore"])
    ]
)
