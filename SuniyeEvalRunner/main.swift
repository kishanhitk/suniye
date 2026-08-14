import AppKit
import Foundation

// VM-lane frontend for the scored Computer Use evals (KIS-182). Runs as an
// LSUIElement app so TCC has a stable bundle identity to grant Accessibility
// and Screen Recording to, and so overlay windows (the virtual cursor) have a
// real app context. The engine is shared with the host-lane XCTest.
//
// Environment: SUNIYE_CU_EVAL_REPO (repository root containing evals/;
// defaults to the working directory), plus the SUNIYE_CU_EVAL_* variables the
// engine documents. Exits 0 when the sweep ran and wrote results, 1 on
// harness errors — task failures are data, not exit codes.

@MainActor
final class EvalRunnerDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let status: Int32
            do {
                let environment = ProcessInfo.processInfo.environment
                let root = URL(
                    fileURLWithPath: environment["SUNIYE_CU_EVAL_REPO"]
                        ?? FileManager.default.currentDirectoryPath
                )
                let engine = try ComputerUseEvalEngine.fromEnvironment(repositoryRoot: root)
                try await engine.run()
                status = 0
            } catch {
                FileHandle.standardError.write(
                    Data("eval runner failed: \(error.localizedDescription)\n".utf8)
                )
                status = 1
            }
            exit(status)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = EvalRunnerDelegate()
    app.delegate = delegate
    app.run()
}
