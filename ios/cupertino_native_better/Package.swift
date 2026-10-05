// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "cupertino_native_better",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "cupertino-native-better", targets: ["cupertino_native_better"])
    ],
    dependencies: [
        .package(url: "https://github.com/SVGKit/SVGKit.git", from: "3.0.0"),
        // SVGKit allows any CocoaLumberjack 3.x; pin it so resolution stays on
        // 3.9.0 instead of jumping to the newest release.
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", exact: "3.9.0")
    ],
    targets: [
        .target(
            name: "cupertino_native_better",
            dependencies: [
                .product(name: "SVGKit", package: "SVGKit"),
                .product(name: "CocoaLumberjack", package: "CocoaLumberjack")
            ],
            path: "Sources/cupertino_native_better",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
