// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "29cc9f6f8d24562a7dcb5fd43d8dc6437e695c21")

let toolQualificationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("ToolQualification/Package.swift").path
)
    ? .package(path: "../ToolQualification")
    : .package(url: "https://github.com/1amageek/ToolQualification.git", revision: "81305bc9e603e0fbd6a9bda9084e13d3f59814f0")

let designFlowKernelDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("DesignFlowKernel/Package.swift").path
)
    ? .package(path: "../DesignFlowKernel")
    : .package(url: "https://github.com/1amageek/DesignFlowKernel.git", revision: "8bad03bbccddfb32f3767c8df00e816ee10cd4f3")

let physicalDesignEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PhysicalDesignEngine/Package.swift").path
)
    ? .package(path: "../PhysicalDesignEngine")
    : .package(url: "https://github.com/1amageek/PhysicalDesignEngine.git", revision: "ef04beea945c122a0185ac0da08af285c43aa809")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "cc39c974bf14624e6ce29fd8722620385fde0762")

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
        physicalDesignEngineDependency,
        logicDesignDependency,
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
                .product(name: "PDKCore", package: "PDKKit"),
                .product(name: "PhysicalDesignCore", package: "PhysicalDesignEngine"),
                .product(name: "ToolQualification", package: "ToolQualification"),
                .product(name: "DesignFlowKernel", package: "DesignFlowKernel"),
            ]
        ),
    ]
)
