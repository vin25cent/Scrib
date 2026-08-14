// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "ScribDomain", targets: ["ScribDomain"]),
    .library(name: "ScribApplication", targets: ["ScribApplication"]),
    .executable(name: "ScribDocxPreview", targets: ["ScribDocxPreview"])
]

var targets: [Target] = [
    .target(name: "ScribDomain"),
    .target(
        name: "ScribApplication",
        dependencies: ["ScribDomain"]
    ),
    .target(
        name: "ScribInfrastructure",
        dependencies: [
            "ScribDomain",
            "ScribApplication"
        ],
        linkerSettings: [
            .linkedFramework("AVFoundation", .when(platforms: [.macOS])),
            .linkedFramework("Compression", .when(platforms: [.macOS])),
            .linkedFramework("IOKit", .when(platforms: [.macOS])),
            .linkedFramework("Network", .when(platforms: [.macOS])),
            .linkedFramework("PDFKit", .when(platforms: [.macOS])),
            .linkedFramework("Security", .when(platforms: [.macOS])),
            .linkedFramework("SwiftData", .when(platforms: [.macOS])),
            .linkedFramework("UserNotifications", .when(platforms: [.macOS]))
        ]
    ),
    .executableTarget(
        name: "ScribDocxPreview",
        dependencies: ["ScribDomain", "ScribInfrastructure"]
    ),
    .testTarget(
        name: "ScribDomainTests",
        dependencies: ["ScribDomain"]
    ),
    .testTarget(
        name: "ScribApplicationTests",
        dependencies: ["ScribApplication", "ScribDomain"]
    ),
    .testTarget(
        name: "ScribInfrastructureTests",
        dependencies: ["ScribInfrastructure", "ScribApplication", "ScribDomain"]
    )
]

#if !os(Windows)
products.append(.executable(name: "ScribApp", targets: ["ScribApp"]))
targets.append(
    .executableTarget(
        name: "ScribApp",
        dependencies: [
            "ScribDomain",
            "ScribApplication",
            "ScribInfrastructure"
        ],
        swiftSettings: [
            .swiftLanguageMode(.v5)
        ],
        linkerSettings: [
            .linkedFramework("AppKit", .when(platforms: [.macOS])),
            .linkedFramework("SwiftUI", .when(platforms: [.macOS])),
            .linkedFramework("UniformTypeIdentifiers", .when(platforms: [.macOS]))
        ]
    )
)
#endif

let package = Package(
    name: "Scrib",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    dependencies: [],
    targets: targets
)
