import XCTest
@testable import Suniye

/// The code-mode JS runtime: write capture, the computer bridge round trip, top-level
/// await, error surfacing, and the timeout bound.
final class ComputerUseScriptRuntimeTests: XCTestCase {
    /// Records every decoded call and returns scripted results.
    private final class SpyPerformer: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [ComputerUseToolCall] = []
        var handler: @Sendable (ComputerUseToolCall) async -> Result<ComputerUseToolResult, Error> = { _ in
            .success(.actionCompleted)
        }

        var calls: [ComputerUseToolCall] {
            lock.withLock { _calls }
        }

        func perform(_ call: ComputerUseToolCall) async -> Result<ComputerUseToolResult, Error> {
            lock.withLock { _calls.append(call) }
            return await handler(call)
        }
    }

    private func makeRuntime(_ spy: SpyPerformer) -> ComputerUseScriptRuntime {
        ComputerUseScriptRuntime { await spy.perform($0) }
    }

    func testNodeReplWriteCapturesOutputWithoutNewline() async {
        let spy = SpyPerformer()
        let result = await makeRuntime(spy).run(script: """
        nodeRepl.write("a");
        nodeRepl.write("b");
        """)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.output, "ab")
    }

    func testConsoleLogAppendsNewlinePerCall() async {
        let spy = SpyPerformer()
        let result = await makeRuntime(spy).run(script: #"console.log("line one"); console.log("line two");"#)
        XCTAssertEqual(result.output, "line one\nline two\n")
    }

    func testTopLevelAwaitChainsSkyCallsInOrder() async {
        let spy = SpyPerformer()
        spy.handler = { call in
            if case let .getAppState(app, _) = call {
                return .success(.appState(ComputerUseAppState(app: app, screenshot: nil, text: "tree-of-\(app)")))
            }
            return .success(.actionCompleted)
        }
        let result = await makeRuntime(spy).run(script: """
        const a = await computer.get_app_state({ app: "Chrome" });
        nodeRepl.write(a.text + "|");
        const b = await computer.get_app_state({ app: "Safari" });
        nodeRepl.write(b.text);
        """)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.output, "tree-of-Chrome|tree-of-Safari")
        XCTAssertEqual(spy.calls.count, 2)
    }

    func testActionArgumentsDecodeThroughTheSharedDecoder() async {
        let spy = SpyPerformer()
        let result = await makeRuntime(spy).run(
            script: #"await computer.click({ app: "Chrome", element_index: 7, click_count: 2 });"#
        )
        XCTAssertNil(result.error)
        guard case let .click(request) = spy.calls.first else {
            return XCTFail("expected a click call, got \(spy.calls)")
        }
        XCTAssertEqual(request.app, "Chrome")
        XCTAssertEqual(request.clickCount, 2)
        XCTAssertEqual(request.target, .element(index: 7))
    }

    func testActionCompletedResolvesToUndefined() async {
        let spy = SpyPerformer()
        let result = await makeRuntime(spy).run(script: """
        const r = await computer.press_key({ app: "Chrome", key: "Return" });
        nodeRepl.write(String(r));
        """)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.output, "undefined")
    }

    func testInvalidArgumentsRejectAndAreCatchable() async {
        let spy = SpyPerformer()
        // click with neither element_index nor coordinates fails the shared decoder.
        let result = await makeRuntime(spy).run(script: """
        try {
          await computer.click({ app: "Chrome" });
          nodeRepl.write("no-throw");
        } catch (e) {
          nodeRepl.write("caught:" + e.message);
        }
        """)
        XCTAssertNil(result.error)
        XCTAssertTrue(result.output.hasPrefix("caught:"), result.output)
        XCTAssertTrue(spy.calls.isEmpty, "decode failed, so the backend must not run")
    }

    func testBackendFailureRejectsWithLocalizedMessage() async {
        let spy = SpyPerformer()
        spy.handler = { _ in .failure(ComputerUseModelToolCallError.unknownTool("boom")) }
        let result = await makeRuntime(spy).run(script: """
        try {
          await computer.list_apps();
        } catch (e) {
          nodeRepl.write(e.message);
        }
        """)
        XCTAssertEqual(result.output, "Unknown Computer Use tool: boom.")
    }

    func testUncaughtThrowSurfacesAsScriptError() async {
        let spy = SpyPerformer()
        let result = await makeRuntime(spy).run(script: #"throw new Error("nope");"#)
        XCTAssertEqual(result.error, "nope")
    }

    func testListAppsShapesFrontmostFlag() async {
        let spy = SpyPerformer()
        spy.handler = { _ in
            .success(.applications([
                ComputerUseApplication(
                    id: "com.apple.TextEdit", displayName: "TextEdit",
                    lastUsedDate: nil, useCount: nil, isRunning: true, isFrontmost: true
                ),
            ]))
        }
        let result = await makeRuntime(spy).run(script: """
        const apps = await computer.list_apps();
        nodeRepl.write(apps[0].id + ":" + apps[0].isFrontmost);
        """)
        XCTAssertEqual(result.output, "com.apple.TextEdit:true")
    }

    func testNeverResolvingCallHitsTimeout() async {
        let spy = SpyPerformer()
        spy.handler = { _ in
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in } // never resolves
            return .success(.actionCompleted)
        }
        let result = await makeRuntime(spy).run(
            script: #"await computer.list_apps(); nodeRepl.write("unreachable");"#,
            timeout: .milliseconds(300)
        )
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.error, "Script timed out after 0.3 seconds without finishing.")
    }

    func testRuntimeIsReusableAcrossCalls() async {
        let spy = SpyPerformer()
        let runtime = makeRuntime(spy)
        let first = await runtime.run(script: #"nodeRepl.write("one");"#)
        let second = await runtime.run(script: #"nodeRepl.write("two");"#)
        XCTAssertEqual(first.output, "one")
        XCTAssertEqual(second.output, "two")
    }
}
