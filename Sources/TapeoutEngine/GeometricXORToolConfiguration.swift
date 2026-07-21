import Foundation
import CircuiteFoundation
import ToolQualification

public struct GeometricXORToolConfiguration: Sendable, Hashable {
    public let qualification: ToolProcessQualificationEvidence
    public let reportOutput: ArtifactLocator
    public let arguments: [String]
    public let environment: [String: String]
    public let timeoutSeconds: Double

    public init(
        qualification: ToolProcessQualificationEvidence,
        reportOutput: ArtifactLocator,
        arguments: [String] = [],
        environment: [String: String] = ["LANG": "C", "LC_ALL": "C", "TZ": "UTC"],
        timeoutSeconds: Double = 300
    ) throws {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw GeometricXORToolConfigurationError.invalidTimeout(timeoutSeconds)
        }
        guard reportOutput.location.storage == .workspaceRelative,
              reportOutput.role == .output,
              reportOutput.kind == .report,
              reportOutput.format == .json else {
            throw GeometricXORToolConfigurationError.invalidReportArtifact
        }
        for argument in arguments where Self.containsControlCharacter(argument) {
            throw GeometricXORToolConfigurationError.argumentContainsControlCharacter(argument)
        }
        let reservedArguments = ["--source-layout", "--streamed-layout", "--report"]
        if let reservedArgument = arguments.first(where: reservedArguments.contains) {
            throw GeometricXORToolConfigurationError.reservedArgument(reservedArgument)
        }
        for (key, value) in environment where
            key.isEmpty || Self.containsControlCharacter(key) || Self.containsControlCharacter(value)
        {
            throw GeometricXORToolConfigurationError.environmentContainsControlCharacter(key)
        }
        self.qualification = qualification
        self.reportOutput = reportOutput
        self.arguments = arguments
        self.environment = environment.merging([
            "LANG": "C",
            "LC_ALL": "C",
            "TZ": "UTC",
        ]) { _, deterministicValue in
            deterministicValue
        }
        self.timeoutSeconds = timeoutSeconds
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
