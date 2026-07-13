// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ReleaseEngine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ReleaseCore", targets: ["ReleaseCore"]),
        .library(name: "SignoffEngine", targets: ["SignoffEngine"]),
        .library(name: "TapeoutEngine", targets: ["TapeoutEngine"]),
        .library(name: "QualificationEngine", targets: ["QualificationEngine"]),
        .library(name: "ReleaseEngine", targets: ["ReleaseEngine"]),
        .executable(name: "release-engine", targets: ["ReleaseEngineCLI"]),
    ],
    dependencies: [
        .package(path: "../CircuiteFoundation"),
        .package(path: "../PDKKit"),
        .package(path: "../ToolQualification"),
        .package(path: "../PhysicalDesignEngine"),
        .package(path: "../LogicDesign"),
    ],
    targets: [
        .target(
            name: "ReleaseCore",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), .product(name: "PDKCore", package: "PDKKit"), .product(name: "ToolQualification", package: "ToolQualification"), .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"), .product(name: "LogicIR", package: "LogicDesign")]
        ),
        .target(
            name: "SignoffEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "ReleaseCore", .product(name: "LogicIR", package: "LogicDesign")]
        ),
        .target(
            name: "TapeoutEngine",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "ReleaseCore", "SignoffEngine"]
        ),
        .target(
            name: "QualificationEngine",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "LogicIR", package: "LogicDesign"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                "ReleaseCore",
            ]
        ),
        .target(
            name: "ReleaseEngine",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                "ReleaseCore",
                "SignoffEngine",
                "TapeoutEngine",
                "QualificationEngine",
            ]
        ),
        .executableTarget(
            name: "ReleaseEngineCLI",
            dependencies: ["ReleaseCore", "SignoffEngine", "TapeoutEngine", "QualificationEngine", "ReleaseEngine"]
        ),
        .testTarget(
            name: "ReleaseEngineTests",
            dependencies: [
                "ReleaseCore",
                "SignoffEngine",
                "TapeoutEngine",
                "QualificationEngine",
                "ReleaseEngine",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "ToolQualification", package: "ToolQualification"),
            ]
        ),
    ]
)
