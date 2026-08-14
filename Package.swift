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
            "ScribApplication",
            .product(
                name: "ZIPFoundation",
                package: "ZIPFoundation",
                condition: .when(platforms: [.macOS])
            )
        ],
        linkerSettings: [
            .linkedFramework("IOKit", .when(platforms: [.macOS])),
            .linkedFramework("PDFKit", .when(platforms: [.macOS])),
            .linkedFramework("Security", .when(platforms: [.macOS]))
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
    dependencies: [
        .package(
            url: "https://github.com/weichsel/ZIPFoundation.git",
            exact: "0.9.20"
        )
    ],
    targets: targets
)
