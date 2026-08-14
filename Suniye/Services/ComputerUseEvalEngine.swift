import Foundation

/// Shared engine for the scored Computer Use task evals. Two frontends run it:
/// the env-gated XCTest (host sweeps) and SuniyeEvalRunner (disposable-VM
/// sweeps). Tasks enter as text at the post-ASR handoff; success is a shell
/// probe of machine state or a regex over the spoken answer. Results are a
/// rate, never a gate.
struct ComputerUseEvalEngine {
    struct Plan: Decodable {
        let trials: Int
        let tasks: [EvalTask]
    }

    struct EvalTask: Decodable {
        struct Verify: Decodable {
            let type: String
            let command: String?
            let pattern: String?
        }

        let id: String
        let prompt: String
        let verify: Verify
        let reset: String?
        let timeoutSeconds: Double?
    }

    struct TrialRecord: Encodable {
        let task: String
        let trial: Int
        let passed: Bool
        let outcome: String
        let durationSeconds: Double
        let answer: String
    }

    struct Summary {
        let records: [TrialRecord]
        let outputFile: URL

        var passed: Int { records.filter(\.passed).count }
        var total: Int { records.count }
    }

    enum EngineError: LocalizedError {
        case missingAPIKey
        case invalidEndpoint(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "No model key: set SUNIYE_CU_EVAL_API_KEY or configure the app."
            case let .invalidEndpoint(value):
                "Invalid eval endpoint URL: \(value)"
            }
        }
    }

    let configuration: ComputerUseRemoteModelConfiguration
    let tasksURL: URL
    let outputDirectory: URL
    /// Progress lines ("eval task=... passed=...") and the final summary.
    let log: (String) -> Void

    /// Builds the engine from SUNIYE_CU_EVAL_* environment, matching the
    /// documented runner contract.
    static func fromEnvironment(
        repositoryRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        log: @escaping (String) -> Void = { print($0) }
    ) throws -> ComputerUseEvalEngine {
        let endpoint = environment["SUNIYE_CU_EVAL_ENDPOINT"]
            ?? "https://openrouter.ai/api/v1/chat/completions"
        guard let endpointURL = URL(string: endpoint) else {
            throw EngineError.invalidEndpoint(endpoint)
        }
        let tasksFile = environment["SUNIYE_CU_EVAL_TASKS"] ?? "tasks.json"
        return ComputerUseEvalEngine(
            configuration: ComputerUseRemoteModelConfiguration(
                endpointURL: endpointURL,
                modelID: environment["SUNIYE_CU_EVAL_MODEL"] ?? "openai/gpt-5.6-luna",
                apiKey: try apiKey(environment: environment)
            ),
            tasksURL: repositoryRoot.appendingPathComponent("evals/computer-use/\(tasksFile)"),
            outputDirectory: repositoryRoot.appendingPathComponent("evals/runs"),
            log: log
        )
    }

    @discardableResult
    func run() async throws -> Summary {
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: tasksURL))
        var records: [TrialRecord] = []

        for task in plan.tasks {
            for trial in 1 ... plan.trials {
                runShell(task.reset)
                let startedAt = Date()
                let agent = ComputerUseAgent(
                    model: ComputerUseRemoteModelClient(configuration: configuration),
                    tools: ComputerUseToolBackend(),
                    modelID: configuration.modelID,
                    contextPolicy: .referenceAligned(modelID: configuration.modelID),
                    maximumRunDuration: .seconds(task.timeoutSeconds ?? 180)
                )
                let result = await agent.run(
                    task: ComputerUseAgentTask(instruction: task.prompt)
                )
                let passed = verify(task.verify, answer: result.message)
                    && result.outcome == .completed
                records.append(TrialRecord(
                    task: task.id,
                    trial: trial,
                    passed: passed,
                    outcome: "\(result.outcome)",
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    answer: result.message
                ))
                log(
                    "eval task=\(task.id) trial=\(trial) passed=\(passed) "
                        + "outcome=\(result.outcome) answer=\(result.message.prefix(120))"
                )
                runShell(task.reset)
            }
        }
        return try writeResults(records, trials: plan.trials)
    }

    // MARK: Verification

    private func verify(_ verify: EvalTask.Verify, answer: String) -> Bool {
        switch verify.type {
        case "shell":
            guard let command = verify.command else { return false }
            return runShell(command) == 0
        case "answer":
            guard let pattern = verify.pattern else { return false }
            // An apologetic non-answer must never score as a pass, whatever
            // the positive pattern happens to match inside it.
            let refusal = "(?i)(can['’]?t|cannot|unable|not (authorized|enabled|available)|blocked|disabled|permission)"
            guard answer.range(of: refusal, options: .regularExpression) == nil else {
                return false
            }
            return answer.range(of: pattern, options: .regularExpression) != nil
        default:
            return false
        }
    }

    @discardableResult
    private func runShell(_ command: String?) -> Int32 {
        guard let command, !command.isEmpty else { return 0 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    // MARK: Configuration

    private static func apiKey(environment: [String: String]) throws -> String {
        if let key = environment["SUNIYE_CU_EVAL_API_KEY"], !key.isEmpty {
            return key
        }
        // Fall back to the key the app already uses.
        let stored = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Suniye/config/llm_api_key.txt")
        let key = (try? String(contentsOf: stored, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else {
            throw EngineError.missingAPIKey
        }
        return key
    }

    // MARK: Results

    private func writeResults(_ records: [TrialRecord], trials: Int) throws -> Summary {
        var byTask: [String: (passed: Int, total: Int)] = [:]
        for record in records {
            var entry = byTask[record.task] ?? (0, 0)
            entry.total += 1
            if record.passed { entry.passed += 1 }
            byTask[record.task] = entry
        }
        log("=== Computer Use eval summary (\(trials) trials/task) ===")
        for (task, entry) in byTask.sorted(by: { $0.key < $1.key }) {
            log("  \(task): \(entry.passed)/\(entry.total)")
        }
        log("  overall: \(records.filter(\.passed).count)/\(records.count)")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let output = outputDirectory.appendingPathComponent("cu_eval_\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: output)
        log("results written to \(output.path)")
        return Summary(records: records, outputFile: output)
    }
}
