import Foundation
import ReleaseCore
import ReleaseEngine
import SignoffEngine
import TapeoutEngine
import ToolQualification
import CircuiteFoundation

@main
struct ReleaseEngineCLI {
    static func main() async {
        do {
            let exitCode = try await run(arguments: Array(CommandLine.arguments.dropFirst()))
            Foundation.exit(exitCode)
        } catch {
            let message = "release-engine: \(error.localizedDescription)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) async throws -> Int32 {
        guard let command = arguments.first else {
            printHelp()
            return 0
        }
        switch command {
        case "profile":
            return try writeProfile(arguments: Array(arguments.dropFirst()))
        case "signoff":
            let envelope = try await executeSignoff(arguments: Array(arguments.dropFirst()))
            try writeJSON(envelope)
            return exitCode(for: envelope.status)
        case "tapeout":
            let envelope = try await executeTapeout(arguments: Array(arguments.dropFirst()))
            try writeJSON(envelope)
            return exitCode(for: envelope.status)
        case "authorize":
            let envelope = try await executeAuthorization(arguments: Array(arguments.dropFirst()))
            try writeJSON(envelope)
            return envelope.status == .authorized ? 0 : 2
        case "help", "--help", "-h":
            printHelp()
            return 0
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private static func writeProfile(arguments: [String]) throws -> Int32 {
        let profileID = argumentValue("--profile", in: arguments) ?? argumentValue("--design-kind", in: arguments) ?? "digital"
        guard let profile = DefaultSignoffProfileProvider().profile(profileID: profileID) else {
            throw CLIError.invalidArgument("unknown profile: \(profileID)")
        }
        try writeJSON(profile)
        return 0
    }

    private static func executeSignoff(arguments: [String]) async throws -> SignoffResult {
        let data = try inputData(arguments: arguments)
        let request = try decoder.decode(SignoffRequest.self, from: data)
        return try await DefaultSignoffEvaluator().execute(request)
    }

    private static func executeTapeout(arguments: [String]) async throws -> TapeoutResult {
        let data = try inputData(arguments: arguments)
        let request = try decoder.decode(TapeoutRequest.self, from: data)
        return try await DefaultTapeoutPackaging().execute(request)
    }

    private static func executeAuthorization(arguments: [String]) async throws -> ReleaseAuthorizationResult {
        let data = try inputData(arguments: arguments)
        let request = try decoder.decode(ReleaseAuthorizationRequest.self, from: data)
        guard let rootPath = argumentValue("--project-root", in: arguments) else {
            throw CLIError.invalidArgument("authorize requires --project-root")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let qualificationReader = LocalToolQualificationArtifactReader(workspaceRoot: root)
        let qualificationEngine = DefaultToolQualificationEngine(
            artifactReader: qualificationReader,
            producer: try ProducerIdentity(
                kind: .library,
                identifier: "ToolQualification",
                version: "1.0.0"
            )
        )
        return try await DefaultReleaseAuthorizer(
            qualificationEngine: qualificationEngine,
            artifactReader: LocalReleaseArtifactReader(workspaceRoot: root)
        ).execute(request)
    }

    private static func inputData(arguments: [String]) throws -> Data {
        guard let path = argumentValue("--request", in: arguments) ?? arguments.first else {
            throw CLIError.requestRequired
        }
        if path == "-" {
            return FileHandle.standardInput.readDataToEndOfFile()
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private static func argumentValue(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func writeJSON<Value: Encodable>(_ value: Value) throws {
        var data = try encoder.encode(value)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static func exitCode(for status: ReleaseExecutionStatus) -> Int32 {
        switch status {
        case .completed:
            0
        case .blocked:
            2
        case .failed:
            3
        case .cancelled:
            4
        }
    }

    private static func printHelp() {
        print("""
        release-engine profile [--profile <digital|analog|mixed-signal>]
        release-engine signoff --request <path|->
        release-engine tapeout --request <path|->
        release-engine authorize --request <path|-> --project-root <path>

        The signoff, tapeout, and authorize commands emit typed JSON results.
        Exit codes: 0 completed or authorized, 2 blocked, 3 failed, 4 cancelled.
        """)
    }
}

private enum CLIError: Error, LocalizedError {
    case unknownCommand(String)
    case invalidArgument(String)
    case requestRequired

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command):
            "unknown command: \(command)"
        case .invalidArgument(let message):
            message
        case .requestRequired:
            "--request <path|-> is required"
        }
    }
}
