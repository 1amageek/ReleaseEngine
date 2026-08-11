// swift-tools-version: 6.3
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    exact: "26.812.0"
)

let pdkKitDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/PDKKit.git",
    exact: "26.812.0"
)

let toolQualificationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/ToolQualification.git",
    exact: "26.812.0"
)

let designFlowKernelDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/DesignFlowKernel.git",
    exact: "26.812.0"
)

let designDatabaseDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/DesignDatabase.git",
    exact: "26.812.1"
)

let physicalDesignEngineDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/PhysicalDesignEngine.git",
    exact: "26.812.0"
)

let logicDesignDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/LogicDesign.git",
    exact: "26.812.0"
)

let signoffToolSupportDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/SignoffToolSupport.git",
    exact: "26.812.0"
)

let package = Package(
    name: "ReleaseEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ReleaseCore", targets: ["ReleaseCore"]),
        .library(name: "SignoffEngine", targets: ["SignoffEngine"]),
        .library(name: "TapeoutEngine", targets: ["TapeoutEngine"]),
        .library(name: "ReleaseEngine", targets: ["ReleaseEngine"]),
        .executable(name: "release-engine", targets: ["ReleaseEngineCLI"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
        pdkKitDependency,
        toolQualificationDependency,
        designFlowKernelDependency,
        designDatabaseDependency,
        physicalDesignEngineDependency,
        logicDesignDependency,
        signoffToolSupportDependency,
    ],
    targets: [
        .target(
            name: "ReleaseCore",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"), .product(name: "CircuiteFoundationFileSystem", package: "CircuiteFoundation"), .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"), .product(name: "DesignDatabaseCore", package: "DesignDatabase"), .product(name: "DesignFlowKernel", package: "DesignFlowKernel"), .product(name: "PDKCore", package: "PDKKit"), .product(name: "ToolQualification", package: "ToolQualification"), .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"), .product(name: "LogicIR", package: "LogicDesign")]
        ),
        .target(
            name: "SignoffEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"), .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"), "ReleaseCore", .product(name: "LogicIR", package: "LogicDesign")]
        ),
        .target(
            name: "TapeoutEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"), .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"), .product(name: "SignoffToolSupport", package: "SignoffToolSupport"), .product(name: "ToolQualification", package: "ToolQualification"), "ReleaseCore", "SignoffEngine"]
        ),
        .target(
            name: "ReleaseEngine",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                "ReleaseCore",
                "SignoffEngine",
                "TapeoutEngine",
            ]
        ),
        .executableTarget(
            name: "ReleaseEngineCLI",
            dependencies: [
                "ReleaseCore",
                "SignoffEngine",
                "TapeoutEngine",
                "ReleaseEngine",
                .product(name: "ToolQualification", package: "ToolQualification"),
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "ReleaseEngineTests",
            dependencies: [
                "ReleaseCore",
                "SignoffEngine",
                "TapeoutEngine",
                "ReleaseEngine",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFileSystem", package: "CircuiteFoundation"),
                .product(name: "DesignDatabaseCore", package: "DesignDatabase"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
                .product(name: "SignoffToolSupport", package: "SignoffToolSupport"),
            ]
        ),
    ]
)
