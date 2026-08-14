import Foundation
import XCTest
@testable import Suniye

/// End-to-end Computer Use evals: real agent, real model, real machine.
/// Task prompts enter as text (the post-ASR handoff point); success is a
/// per-task verifier — a shell probe of machine state or a regex over the
/// spoken answer. Results are a scored rate written to evals/runs/, never a
/// red/green gate: the model is stochastic, so this suite is opt-in and the
/// test only fails on harness errors.
///
/// Run: SUNIYE_CU_EVALS=1 (see scripts/run_computer_use_evals.sh). Requires a
/// GUI session with Accessibility + Screen Recording granted and a configured
/// model key. Mutating tasks reset after themselves; still, prefer a dedicated
/// test user for full sweeps.
final class ComputerUseEvalTests: XCTestCase {
    private struct EvalPlan: Decodable {
        let trials: Int
        let tasks: [EvalTask]
    }

    private struct EvalTask: Decodable {
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

    private struct TrialRecord: Encodable {
        let task: String
        let trial: Int
        let passed: Bool
        let outcome: String
        let steps: Int?
        let durationSeconds: Double
        let answer: String
    }

    func testComputerUseTaskEvals() async throws {
        guard ProcessInfo.processInfo.environment["SUNIYE_CU_EVALS"] == "1" else {
            throw XCTSkip("Set SUNIYE_CU_EVALS=1 to run the scored Computer Use evals.")
        }
        let plan = try loadPlan()
        let configuration = try modelConfiguration()
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
                    steps: nil,
                    durationSeconds: Date().timeIntervalSince(startedAt),
                    answer: result.message
                ))
                print(
                    "eval task=\(task.id) trial=\(trial) passed=\(passed) "
                        + "outcome=\(result.outcome) answer=\(result.message.prefix(120))"
                )
                runShell(task.reset)
            }
        }

        try writeResults(records, trials: plan.trials)
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

    private func loadPlan() throws -> EvalPlan {
        let url = repositoryRoot()
            .appendingPathComponent("evals/computer-use/tasks.json")
        return try JSONDecoder().decode(EvalPlan.self, from: Data(contentsOf: url))
    }

    private func modelConfiguration() throws -> ComputerUseRemoteModelConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let endpoint = environment["SUNIYE_CU_EVAL_ENDPOINT"]
            ?? "https://openrouter.ai/api/v1/chat/completions"
        let modelID = environment["SUNIYE_CU_EVAL_MODEL"] ?? "openai/gpt-5.6-luna"
        let key = try apiKey(environment: environment)
        return ComputerUseRemoteModelConfiguration(
            endpointURL: try XCTUnwrap(URL(string: endpoint)),
            modelID: modelID,
            apiKey: key
        )
    }

    private func apiKey(environment: [String: String]) throws -> String {
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
            throw XCTSkip("No model key: set SUNIYE_CU_EVAL_API_KEY or configure the app.")
        }
        return key
    }

    // MARK: Results

    private func writeResults(_ records: [TrialRecord], trials: Int) throws {
        var byTask: [String: (passed: Int, total: Int)] = [:]
        for record in records {
            var entry = byTask[record.task] ?? (0, 0)
            entry.total += 1
            if record.passed { entry.passed += 1 }
            byTask[record.task] = entry
        }
        let totalPassed = records.filter(\.passed).count
        print("=== Computer Use eval summary (\(trials) trials/task) ===")
        for (task, entry) in byTask.sorted(by: { $0.key < $1.key }) {
            print("  \(task): \(entry.passed)/\(entry.total)")
        }
        print("  overall: \(totalPassed)/\(records.count)")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let runsDirectory = repositoryRoot().appendingPathComponent("evals/runs")
        try FileManager.default.createDirectory(
            at: runsDirectory,
            withIntermediateDirectories: true
        )
        let output = runsDirectory.appendingPathComponent("cu_eval_\(stamp).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: output)
        print("results written to \(output.path)")
    }

    private func repositoryRoot() -> URL {
        // #filePath = <repo>/SuniyeTests/ComputerUseEvalTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
