// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "Sofa",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Sofa", targets: ["HisenseRemote"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(name: "HisenseRemote", dependencies: [.product(name: "Sparkle", package: "Sparkle")], swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])]
)
