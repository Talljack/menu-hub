// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MenuHub",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MenuHubCore", targets: ["MenuHubCore"]),
        .executable(name: "MenuHub", targets: ["MenuHub"]),
        .executable(name: "FeasibilityProbe", targets: ["FeasibilityProbe"]),
    ],
    targets: [
        .target(name: "MenuHubCore"),
        .executableTarget(
            name: "MenuHub",
            dependencies: ["MenuHubCore"],
            resources: [
                .process("../../Resources/en.lproj"),
                .process("../../Resources/zh-Hans.lproj"),
                .process("../../Resources/zh-Hant.lproj"),
                .process("../../Resources/ja.lproj"),
                .process("../../Resources/ko.lproj"),
                .process("../../Resources/es.lproj"),
                .process("../../Resources/fr.lproj"),
                .process("../../Resources/de.lproj"),
                .process("../../Resources/pt-BR.lproj"),
                .process("../../Resources/ru.lproj"),
            ]
        ),
        .executableTarget(name: "FeasibilityProbe", dependencies: ["MenuHubCore"]),
        .testTarget(name: "MenuHubCoreTests", dependencies: ["MenuHubCore"]),
        .testTarget(
            name: "MenuHubTests",
            dependencies: ["MenuHub", "MenuHubCore"],
            path: "Tests/MenuHubTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
