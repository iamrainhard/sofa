// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Sofa",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Sofa", targets: ["HisenseRemote"])],
    targets: [.executableTarget(name: "HisenseRemote", swiftSettings: [.swiftLanguageMode(.v5)])]
)
