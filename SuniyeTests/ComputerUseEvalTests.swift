import Foundation
import XCTest
@testable import Suniye

/// Host-lane frontend for the scored Computer Use evals; the logic lives in
/// ComputerUseEvalEngine, shared with SuniyeEvalRunner (the VM lane). Opt-in
/// via SUNIYE_CU_EVALS=1 (scripts/run_computer_use_evals.sh); requires a GUI
/// session with Accessibility + Screen Recording granted to the test host and
/// a configured model key. Results are a scored rate written to evals/runs/,
/// never a red/green gate: the test only fails on harness errors.
final class ComputerUseEvalTests: XCTestCase {
    func testComputerUseTaskEvals() async throws {
        guard ProcessInfo.processInfo.environment["SUNIYE_CU_EVALS"] == "1" else {
            throw XCTSkip("Set SUNIYE_CU_EVALS=1 to run the scored Computer Use evals.")
        }
        // #filePath = <repo>/SuniyeTests/ComputerUseEvalTests.swift
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let engine = try ComputerUseEvalEngine.fromEnvironment(repositoryRoot: repositoryRoot)
        try await engine.run()
    }
}
