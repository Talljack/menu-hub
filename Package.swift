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
                .copy("../../Resources/en.lproj"),
                .copy("../../Resources/zh-Hans.lproj"),
                .copy("../../Resources/zh-Hant.lproj"),
                .copy("../../Resources/ja.lproj"),
                .copy("../../Resources/ko.lproj"),
                .copy("../../Resources/es.lproj"),
                .copy("../../Resources/fr.lproj"),
                .copy("../../Resources/de.lproj"),
                .copy("../../Resources/pt-BR.lproj"),
                .copy("../../Resources/ru.lproj"),
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
