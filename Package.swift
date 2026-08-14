// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .library(name: "ScribDomain", targets: ["ScribDomain"]),
    .library(name: "ScribApplication", targets: ["ScribApplication"])
]

var targets: [Target] = [
    .target(name: "ScribDomain"),
    .target(
        name: "ScribApplication",
        dependencies: ["ScribDomain"]
    ),
    .target(
        name: "ScribInfrastructure",
        dependencies: ["ScribDomain", "ScribApplication"],
        linkerSettings: [
            .linkedFramework("IOKit", .when(platforms: [.macOS]))
        ]
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
    targets: targets
)
