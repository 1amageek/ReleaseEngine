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
    : .package(url: "https://github.com/1amageek/CircuiteFoundation.git", revision: "1dd75ecf2b8758c54c4e008ff5fd59e263cce0e6")

let pdkKitDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PDKKit/Package.swift").path
)
    ? .package(path: "../PDKKit")
    : .package(url: "https://github.com/1amageek/PDKKit.git", revision: "3ab7e3b6094d2de672b582d90076cf58b6527766")

let toolQualificationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("ToolQualification/Package.swift").path
)
    ? .package(path: "../ToolQualification")
    : .package(url: "https://github.com/1amageek/ToolQualification.git", revision: "c489783a5673bc2dd0b94c438c2f53a65d9a2d8b")

let designFlowKernelDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("DesignFlowKernel/Package.swift").path
)
    ? .package(path: "../DesignFlowKernel")
    : .package(url: "https://github.com/1amageek/DesignFlowKernel.git", revision: "5d60047c1c322ed3f8fc741ebee1f35ce7a99533")

let designDatabaseDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("DesignDatabase/Package.swift").path
)
    ? .package(path: "../DesignDatabase")
    : .package(url: "https://github.com/1amageek/DesignDatabase.git", branch: "main")

let physicalDesignEngineDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("PhysicalDesignEngine/Package.swift").path
)
    ? .package(path: "../PhysicalDesignEngine")
    : .package(url: "https://github.com/1amageek/PhysicalDesignEngine.git", revision: "a3befb76dc3c5053a9636ccb8c0e8989a060dd98")

let logicDesignDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("LogicDesign/Package.swift").path
)
    ? .package(path: "../LogicDesign")
    : .package(url: "https://github.com/1amageek/LogicDesign.git", revision: "1ad3b929412e9d459be45a7cb3a426d99aa9417b")

let signoffToolSupportDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("SignoffToolSupport/Package.swift").path
)
    ? .package(path: "../SignoffToolSupport")
    : .package(url: "https://github.com/1amageek/SignoffToolSupport.git", revision: "2c36104106bdfc8c279629c162c3ced9d7401328")

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
