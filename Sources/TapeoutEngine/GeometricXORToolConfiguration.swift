import Foundation
import CircuiteFoundation
import ReleaseCore
import ToolQualification

public struct GeometricXORToolConfiguration: Sendable, Hashable {
    public let qualification: ToolProcessQualificationEvidence
    public let qualificationBindings: [ReleaseArtifactBinding]
    public let reportOutput: ReleaseArtifactDestination
    public let arguments: [String]
    public let environment: [String: String]
    public let timeoutSeconds: Double

    public init(
        qualification: ToolProcessQualificationEvidence,
        qualificationBindings: [ReleaseArtifactBinding],
        reportOutput: ReleaseArtifactDestination,
        arguments: [String] = [],
        environment: [String: String] = ["LANG": "C", "LC_ALL": "C", "TZ": "UTC"],
        timeoutSeconds: Double = 300
    ) throws {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw GeometricXORToolConfigurationError.invalidTimeout(timeoutSeconds)
        }
        guard reportOutput.descriptor.role == .output,
              reportOutput.descriptor.kind == .report,
              reportOutput.descriptor.format == .json else {
            throw GeometricXORToolConfigurationError.invalidReportArtifact
        }
        let requiredQualificationArtifacts = Set(
            qualification.identityArtifacts.all
                + qualification.evidenceArtifacts
                + qualification.inputArtifacts
                + qualification.outputArtifacts
        )
        let groupedBindings = Dictionary(
            grouping: qualificationBindings,
            by: \.reference
        )
        for (reference, bindings) in groupedBindings {
            if Set(bindings.map(\.availability)).count != 1 {
                throw GeometricXORToolConfigurationError.conflictingQualificationBinding(
                    reference.id.description
                )
            }
            if bindings.count != 1 {
                throw GeometricXORToolConfigurationError.duplicateQualificationBinding(
                    reference.id.description
                )
            }
        }
        guard Set(groupedBindings.keys) == requiredQualificationArtifacts else {
            throw GeometricXORToolConfigurationError.qualificationBindingInventoryMismatch
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
        self.qualificationBindings = qualificationBindings.sorted {
            $0.reference.id.description < $1.reference.id.description
        }
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
