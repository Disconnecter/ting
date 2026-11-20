// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ting",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "Vendor/BobukKit"),
        // Automatic updates from the public GitHub release feed.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Pure logic: config, key names, leader state machine, binding tree. No AppKit.
        .target(
            name: "TingCore",
            dependencies: [.product(name: "BobukCore", package: "BobukKit")],
            path: "Sources/TingCore",
            swiftSettings: [.swiftLanguageMode(.v5)]),
        // Shared execution engine for the app and the console tool.
        .target(name: "TingRuntime", dependencies: ["TingCore", .product(name: "BobukCore", package: "BobukKit")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ting-micro", dependencies: ["TingRuntime"], path: "Sources/TingMicroCLI",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // The menu-bar app (AppKit + SwiftUI + Carbon).
        .executableTarget(
            name: "Ting",
            dependencies: ["TingCore", "TingRuntime", .product(name: "Sparkle", package: "Sparkle"),
                           .product(name: "BobukCore", package: "BobukKit"),
                           .product(name: "BobukSystem", package: "BobukKit"),
                           .product(name: "BobukUI", package: "BobukKit"),
                           .product(name: "BobukUpdates", package: "BobukKit")],
            path: "Sources/Ting",
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "TingServiceTests",
            dependencies: ["Ting", "TingCore", "TingRuntime",
                           .product(name: "BobukSystem", package: "BobukKit"),
                           .product(name: "BobukUI", package: "BobukKit"),
                           .product(name: "BobukUpdates", package: "BobukKit"),
                           .product(name: "BobukTestSupport", package: "BobukKit")],
            path: "Tests/TingServiceTests",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Swift Build leaves Sparkle.framework next to the test bundle, outside its default rpath.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../.."])]),
        .testTarget(
            name: "TingCoreTests",
            dependencies: ["TingCore"],
            path: "Tests/TingCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
