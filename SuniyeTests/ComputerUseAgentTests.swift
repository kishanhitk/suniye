import XCTest
import SuniyeAnalytics
@testable import Suniye

final class ComputerUseAgentTests: XCTestCase {
    func testPublishesScriptActivityThenUpdatesItWithScriptOutput() async {
        let code = observeCalculatorScript
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: code),
                .text("Done."),
                .text("Done."),
            ]
        )
        let recorder = RecordingComputerUseActivitySink()
        let activitySink = ComputerUseActivitySink { activity in
            await recorder.record(activity)
        }
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            activitySink: activitySink
        )

        _ = await agent.run(task: ComputerUseAgentTask(instruction: "Inspect Calculator."))

        let activities = await recorder.activities
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].id, activities[1].id)
        XCTAssertEqual(activities[0].toolName, "node_repl")
        XCTAssertEqual(activities[0].arguments, nodeReplArguments(code))
        XCTAssertNil(activities[0].output)
        XCTAssertEqual(activities[1].output, "0 AXStaticText: 42")
    }

    func testScriptFailureSurfacesAsErrorOutput() async {
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: observeCalculatorScript),
                .text("Could not inspect Calculator."),
            ]
        )
        let recorder = RecordingComputerUseActivitySink()
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(shouldFailObservation: true
            ),
            activitySink: ComputerUseActivitySink { activity in
                await recorder.record(activity)
            }
        )

        _ = await agent.run(task: ComputerUseAgentTask(instruction: "Inspect Calculator."))

        let activities = await recorder.activities
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].id, activities[1].id)
        XCTAssertEqual(activities[1].output, "Error: Tool failed.")
    }

    func testEveryLifecycleAndToolLogIncludesTheTaskDebugSessionID() async {
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: observeCalculatorScript),
                .text("Done."),
                .text("Done."),
            ]
        )
        let logger = RecordingComputerUseLogger()
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            logger: logger
        )
        let debugSessionID = ComputerUseDebugSessionID(rawValue: "CU-ABC123DEF456")

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Inspect Calculator.",
                debugSessionID: debugSessionID
            )
        )

        let messages = logger.messages
        XCTAssertEqual(messages.count, 4)
        XCTAssertTrue(messages.allSatisfy { $0.contains("session=CU-ABC123DEF456") })
        XCTAssertTrue(messages.contains { $0.contains("computer use run started") })
        XCTAssertTrue(messages.contains { $0.contains("computer use script started") })
        XCTAssertTrue(messages.contains { $0.contains("computer use script completed") })
        XCTAssertTrue(messages.contains { $0.contains("computer use run completed") })
    }

    func testModelBatchesObserveActObserveInOneScript() async {
        let code = """
        const s1 = await computer.get_app_state({ app: "Calculator" });
        await computer.press_key({ app: "Calculator", key: "Return" });
        const s2 = await computer.get_app_state({ app: "Calculator" });
        nodeRepl.write(s2.text);
        """
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: code),
                .text("The Calculator result is 42."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend()
        let agent = ComputerUseAgent(
            model: model,
            tools: backend
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Read the Calculator result.")
        )

        XCTAssertEqual(
            result,
            ComputerUseAgentResult(
                outcome: .completed,
                message: "The Calculator result is 42."
            )
        )
        let calls = await backend.calls
        XCTAssertEqual(calls, [.getAppState, .pressKey, .getAppState])
        let requests = await model.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0], [.text(role: .user, text: "Read the Calculator result.")])
        XCTAssertEqual(requests[1].suffix(2), [
            .toolCall(
                id: "script-1",
                name: "node_repl",
                arguments: nodeReplArguments(code)
            ),
            .toolResult(id: "script-1", content: "0 AXStaticText: 42"),
        ])
    }

    func testObservationOnlyCompletionGetsOneGenericOutcomeAudit() async {
        let observeOnly = """
        const s = await computer.get_app_state({ app: "Google Chrome" });
        nodeRepl.write(s.text);
        """
        let clickAndConfirm = """
        await computer.click({ app: "Google Chrome", element_index: 7 });
        const s = await computer.get_app_state({ app: "Google Chrome" });
        nodeRepl.write(s.text);
        """
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: observeOnly),
                .text("The requested email is open."),
                nodeReplCall(id: "script-2", code: clickAndConfirm),
                .text("The requested email is open."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend()
        let agent = ComputerUseAgent(
            model: model,
            tools: backend
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Open the invoice email.")
        )

        XCTAssertEqual(result.outcome, .completed)
        let calls = await backend.calls
        XCTAssertEqual(calls, [.getAppState, .click, .getAppState])
        let auditRequest = await model.requests[2]
        XCTAssertTrue(
            auditRequest.contains { message in
                message.textContent?.contains("Internal completion audit") == true
            }
        )
    }

    func testScriptedActionsStillRequireFreshObservationsBetweenThem() async {
        // The backend's freshness rule (observe before every action) holds
        // inside a script exactly as it did across separate tool calls.
        let code = """
        await computer.get_app_state({ app: "Notes" });
        await computer.press_key({ app: "Notes", key: "Return" });
        await computer.get_app_state({ app: "Notes" });
        await computer.type_text({ app: "Notes", text: "hello" });
        await computer.get_app_state({ app: "Notes" });
        nodeRepl.write("typed");
        """
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: code),
                .text("Done."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend()
        let agent = ComputerUseAgent(
            model: model,
            tools: backend
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Type hello in Notes.")
        )

        XCTAssertEqual(result.outcome, .completed)
        let calls = await backend.calls
        XCTAssertEqual(
            calls,
            [.getAppState, .pressKey, .getAppState, .typeText, .getAppState]
        )
        let requests = await model.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[1].suffix(2),
            [
                nodeReplCallMessage(id: "script-1", code: code),
                .toolResult(id: "script-1", content: "typed"),
            ]
        )
    }

    func testTwoUnchangedPostActionObservationsRequestADifferentRecoveryStrategy() async {
        func clickAndObserve(x: Int) -> String {
            """
            await computer.click({ app: "Google Chrome", x: \(x), y: 200 });
            const s = await computer.get_app_state({ app: "Google Chrome" });
            nodeRepl.write(s.text);
            """
        }
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: observeChromeScript),
                nodeReplCall(id: "script-2", code: clickAndObserve(x: 100)),
                nodeReplCall(id: "script-3", code: clickAndObserve(x: 101)),
                nodeReplCall(id: "script-4", code: """
                await computer.press_key({ app: "Google Chrome", key: "Return" });
                const s = await computer.get_app_state({ app: "Google Chrome" });
                nodeRepl.write(s.text);
                """),
                .text("The requested email is open."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend(
            appStateTexts: [
                "Search results",
                "There has been no change in the accessibility tree for Window: Search results",
                "There has been no change in the accessibility tree for Window: Search results",
                "Invoice Number: MC59950569",
            ]
        )
        let agent = ComputerUseAgent(
            model: model,
            tools: backend
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(instruction: "Open the MacBook invoice email.")
        )

        XCTAssertEqual(result.outcome, .completed)
        let recoveryRequest = await model.requests[3]
        XCTAssertTrue(
            recoveryRequest.contains { message in
                message.textContent?.contains("Repeated unchanged-state recovery") == true
            }
        )
    }

    func testRunEmitsOneCategorizedAnalyticsRecordWithoutAppIdentity() async {
        let analytics = SpyAnalytics()
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: """
                const s = await computer.get_app_state({ app: "com.apple.Safari" });
                nodeRepl.write(s.text);
                """),
                .text("Done."),
                .text("Done."),
            ]
        )
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            analytics: analytics,
            modelID: "gpt-5.6-luna"
        )

        _ = await agent.run(task: ComputerUseAgentTask(instruction: "Read the page."))

        let runs = analytics.trackedEvents.compactMap { event -> ComputerUseRunMetrics? in
            if case let .computerUseRun(metrics) = event { return metrics }
            return nil
        }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].outcome, .completed)
        XCTAssertEqual(runs[0].target, .browser)
        XCTAssertEqual(runs[0].toolFailures, 0)
        XCTAssertEqual(runs[0].model, SafeLabel("gpt-5.6-luna"))
        XCTAssertFalse(
            "\(runs[0])".contains("Safari"),
            "the app identifier must never leave the device; only its category does"
        )
    }

    func testToolFailureIsReportedWithClosedVocabularies() async {
        let analytics = SpyAnalytics()
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: """
                await computer.press_key({ app: "Calculator", key: "Return" });
                """),
                .text("Done."),
                .text("Done."),
            ]
        )
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            analytics: analytics
        )

        _ = await agent.run(task: ComputerUseAgentTask(instruction: "Press return."))

        let failures = analytics.trackedEvents.compactMap {
            event -> (ComputerUseTool, ComputerUseFailureReason)? in
            if case let .computerUseToolFailed(tool, _, reason) = event { return (tool, reason) }
            return nil
        }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].0, .pressKey)
        XCTAssertEqual(failures[0].1, .observationRequired)
    }

    func testStepLimitTerminatesTheRunAsFailure() async {
        let model = ScriptedComputerUseModel(
            responses: Array(
                repeating: nodeReplCall(id: "script", code: observeCalculatorScript),
                count: 6
            )
        )
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            maximumSteps: 2
        )

        let result = await agent.run(task: ComputerUseAgentTask(instruction: "Loop forever."))

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.message.contains("2 steps"))
    }

    func testWallClockDeadlineTerminatesTheRunAsFailure() async {
        let clock = ManualComputerUseClock(advancingBy: .seconds(20))
        let model = ScriptedComputerUseModel(
            responses: Array(
                repeating: nodeReplCall(id: "script", code: observeCalculatorScript),
                count: 6
            )
        )
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            maximumRunDuration: .seconds(30),
            now: { clock.now }
        )

        let result = await agent.run(task: ComputerUseAgentTask(instruction: "Take too long."))

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.message.contains("running too long"))
    }

    func testInterventionAfterAnAtomicActionForcesFreshObservationBeforeContinuing() async {
        let interventions = ComputerUseInterventionChannel()
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: observeCalculatorScript),
                nodeReplCall(id: "script-2", code: """
                await computer.click({ app: "Calculator", element_index: 7 });
                """),
                .text("Stopped after the correction."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend(
            interventionChannel: interventions,
            intervention: "Actually, do not click anything"
        )
        let agent = ComputerUseAgent(
            model: model,
            tools: backend,
            screenshots: MissingComputerUseScreenshotLoader()
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Click 7 in Calculator",
                interventions: interventions
            )
        )

        XCTAssertEqual(result.message, "Stopped after the correction.")
        let calls = await backend.calls
        XCTAssertEqual(calls, [.getAppState, .click, .getAppState])
        let finalRequest = await model.requests[2]
        XCTAssertTrue(
            finalRequest.contains(
                .text(role: .user, text: "Actually, do not click anything")
            )
        )
        // The forced observation enters context as a user message carrying the
        // fresh state, since the model never made a get_app_state tool call.
        XCTAssertTrue(
            finalRequest.contains { message in
                message.role == .user
                    && message.textContent?.hasPrefix("Current state of Calculator") == true
            }
        )
    }

    func testInterventionDuringModelDecisionDiscardsTheStaleProposedAction() async {
        let interventions = ComputerUseInterventionChannel()
        let model = InterventionInjectingComputerUseModel(interventions: interventions)
        let backend = FreshnessCheckingComputerUseBackend()
        let agent = ComputerUseAgent(
            model: model,
            tools: backend,
            screenshots: MissingComputerUseScreenshotLoader()
        )

        let result = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Click 7 in Calculator",
                interventions: interventions
            )
        )

        XCTAssertEqual(result.message, "Understood the correction.")
        let calls = await backend.calls
        XCTAssertEqual(calls, [.getAppState, .getAppState])
    }

    func testFreshAppStateAddsItsScreenshotAfterTheToolResult() async throws {
        let screenshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("computer-use-agent-\(UUID().uuidString).jpg")
        try Data([1, 2, 3]).write(to: screenshotURL)
        defer { try? FileManager.default.removeItem(at: screenshotURL) }
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "state-image", code: observeCalculatorScript),
                .text("Done."),
                .text("Done."),
            ]
        )
        let backend = FreshnessCheckingComputerUseBackend(screenshotURL: screenshotURL)
        let agent = ComputerUseAgent(
            model: model,
            tools: backend
        )

        _ = await agent.run(
            task: ComputerUseAgentTask(instruction: "Inspect Calculator.")
        )

        let requests = await model.requests
        XCTAssertEqual(
            requests[1].last,
            .image(
                role: .user,
                text: "Current Calculator screenshot.",
                dataURL: "data:image/jpeg;base64,AQID"
            )
        )
    }

    func testPriorConversationPrecedesTheCurrentTask() async {
        let model = ScriptedComputerUseModel(responses: [.text("Done.")])
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend()
        )

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Now read it.",
                conversation: [
                    ComputerUseConversationMessage(role: .user, text: "Open Calculator."),
                    ComputerUseConversationMessage(
                        activity: ComputerUseActivity(
                            toolName: "get_app_state",
                            arguments: #"{"app":"Calculator"}"#
                        )
                    ),
                    ComputerUseConversationMessage(role: .assistant, text: "Calculator is ready."),
                ]
            )
        )

        let requests = await model.requests
        XCTAssertEqual(
            requests[0],
            [
                .text(role: .user, text: "Open Calculator."),
                .text(role: .assistant, text: "Calculator is ready."),
                .text(role: .user, text: "Now read it."),
            ]
        )
    }

    func testHistoricalToolCallsAreNormalizedAsPairedProtocolMessagesWithoutLocalScreenshotURL() async {
        let model = ScriptedComputerUseModel(responses: [.text("Done.")])
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend()
        )
        let activity = ComputerUseActivity(
            toolName: "get_app_state",
            arguments: #"{"app":"Calculator"}"#,
            output: #"{"app":"Calculator","screenshot":"file:///private/tmp/state.jpg","text":"0 AXStaticText: 42"}"#
        )

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Now read it.",
                conversation: [ComputerUseConversationMessage(activity: activity)]
            )
        )

        let request = await model.requests[0]
        let callID = "history-\(activity.id.uuidString.lowercased())"
        XCTAssertEqual(request, [
            .toolCall(
                id: callID,
                name: "get_app_state",
                arguments: #"{"app":"Calculator"}"#
            ),
            .toolResult(
                id: callID,
                content: #"{"app":"Calculator","text":"0 AXStaticText: 42"}"#
            ),
            .text(role: .user, text: "Now read it."),
        ])
    }

    func testInitialContextIsAtMostFiftyMessagesAndKeepsCurrentInstruction() async {
        let model = ScriptedComputerUseModel(responses: [.text("Done.")])
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend()
        )
        let conversation = (0..<70).map { index in
            ComputerUseConversationMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "message-\(index)"
            )
        }

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "current instruction",
                conversation: conversation
            )
        )

        let request = await model.requests[0]
        XCTAssertEqual(request.count, 50)
        XCTAssertEqual(request.last, .text(role: .user, text: "current instruction"))
        XCTAssertFalse(request.contains(.text(role: .user, text: "message-0")))
        XCTAssertTrue(request.contains(.text(role: .assistant, text: "message-69")))
    }

    func testContextKeepsLatestObservationEvenWhenFiftyNewerMessagesExist() async {
        let model = ScriptedComputerUseModel(responses: [.text("Done.")])
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend()
        )
        let observation = ComputerUseActivity(
            toolName: "get_app_state",
            arguments: #"{"app":"Calculator"}"#,
            output: #"{"app":"Calculator","screenshot":null,"text":"latest observed state"}"#
        )
        let newerMessages = (0..<60).map { index in
            ComputerUseConversationMessage(role: .assistant, text: "later-\(index)")
        }

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "current instruction",
                conversation: [ComputerUseConversationMessage(activity: observation)] + newerMessages
            )
        )

        let request = await model.requests[0]
        XCTAssertEqual(request.count, 50)
        XCTAssertTrue(request.contains { message in
            message.toolCalls?.first?.function.name == "get_app_state"
        })
        XCTAssertTrue(request.contains { message in
            message.textContent?.contains("latest observed state") == true
        })
    }

    func testActivityKeepsObservationScreenshotURLWhileModelReceivesScriptOutput() async throws {
        let screenshotURL = URL(fileURLWithPath: "/private/tmp/computer-use-state.jpg")
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: observeCalculatorScript),
                .text("Done."),
                .text("Done."),
            ]
        )
        let recorder = RecordingComputerUseActivitySink()
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(screenshotURL: screenshotURL
            ),
            screenshots: MissingComputerUseScreenshotLoader(),
            activitySink: ComputerUseActivitySink { activity in
                await recorder.record(activity)
            }
        )

        _ = await agent.run(task: ComputerUseAgentTask(instruction: "Inspect Calculator."))

        let activities = await recorder.activities
        let requests = await model.requests
        // The raw screenshot URL persists on the activity for replay, even
        // though the file could not be loaded for the model right now.
        let completed = try XCTUnwrap(activities.last)
        XCTAssertEqual(completed.observedScreenshotURL, screenshotURL)
        XCTAssertEqual(completed.observedApp, "Calculator")
        let modelResult = try XCTUnwrap(requests[1].first { $0.toolCallID == "script-1" })
        XCTAssertFalse(modelResult.textContent?.contains("file://") == true)
        XCTAssertEqual(modelResult.textContent, "0 AXStaticText: 42")
    }

    func testLargeScriptOutputUsesReferenceMiddleTokenTruncation() async {
        let longText = String(repeating: "a", count: 50_000) + "TAIL"
        let model = ScriptedComputerUseModel(
            responses: [
                nodeReplCall(id: "script-1", code: observeCalculatorScript),
                .text("Done."),
                .text("Done."),
            ]
        )
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(appStateText: longText
            ),
            screenshots: MissingComputerUseScreenshotLoader(),
            contextPolicy: .referenceAligned(modelID: "gpt-5.6-luna")
        )

        _ = await agent.run(task: ComputerUseAgentTask(instruction: "Inspect Calculator."))

        let request = await model.requests[1]
        let result = request.first { $0.toolCallID == "script-1" }?.textContent ?? ""
        XCTAssertLessThanOrEqual(result.utf8.count, 40_100)
        XCTAssertTrue(result.contains("tokens truncated"))
        XCTAssertTrue(result.hasSuffix("TAIL"))
    }

    func testContextTokenBudgetKeepsCurrentInstructionAndNewestUsefulMessages() {
        let policy = ComputerUseModelContextPolicy(
            maximumMessages: 50,
            maximumContextTokens: 35,
            maximumToolOutputTokens: 10_000,
            maximumScreenshots: 2
        )
        let builder = ComputerUseModelContextBuilder(policy: policy)
        let messages = (0..<8).map { index in
            ComputerUseModelMessage.text(
                role: .assistant,
                text: "message-\(index)-" + String(repeating: "x", count: 24)
            )
        } + [.text(role: .user, text: "current instruction")]

        let compacted = builder.compact(messages, currentInstruction: "current instruction")

        XCTAssertEqual(compacted.last, .text(role: .user, text: "current instruction"))
        XCTAssertTrue(compacted.contains { $0.textContent?.hasPrefix("message-7-") == true })
        XCTAssertFalse(compacted.contains { $0.textContent?.hasPrefix("message-0-") == true })
    }

    func testContextRetainsOnlyTwoLatestScreenshots() {
        let builder = ComputerUseModelContextBuilder(
            policy: .referenceAligned(modelID: "gpt-5.6-luna")
        )
        let messages = (0..<4).map { index in
            ComputerUseModelMessage.image(
                role: .user,
                text: "screenshot-\(index)",
                dataURL: "data:image/jpeg;base64,\(index)"
            )
        } + [.text(role: .user, text: "current instruction")]

        let compacted = builder.compact(messages, currentInstruction: "current instruction")
        let screenshotLabels = compacted.compactMap { message -> String? in
            guard case let .parts(parts) = message.content else { return nil }
            guard case let .text(label)? = parts.first else { return nil }
            return label
        }

        XCTAssertEqual(screenshotLabels, ["screenshot-2", "screenshot-3"])
    }

    func testInitialContextRestoresTwoNewestHistoricalScreenshots() async {
        let model = ScriptedComputerUseModel(responses: [.text("Done.")])
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            screenshots: StubComputerUseScreenshotLoader()
        )
        let conversation = (0..<3).map { index in
            ComputerUseConversationMessage(
                activity: ComputerUseActivity(
                    toolName: "get_app_state",
                    arguments: #"{"app":"App\#(index)"}"#,
                    output: #"{"app":"App\#(index)","screenshot":"file:///tmp/state-\#(index).jpg","text":"state-\#(index)"}"#
                )
            )
        }

        _ = await agent.run(
            task: ComputerUseAgentTask(
                instruction: "Continue.",
                conversation: conversation
            )
        )

        let request = await model.requests[0]
        let imageLabels = request.compactMap { message -> String? in
            guard case let .parts(parts) = message.content else { return nil }
            guard case let .text(label)? = parts.first else { return nil }
            return label
        }
        XCTAssertEqual(
            imageLabels,
            ["Current App1 screenshot.", "Current App2 screenshot."]
        )
    }

    func testInitialContextBackfillsAnOlderScreenshotWhenANewerFileIsMissing() async {
        let model = ScriptedComputerUseModel(responses: [.text("Done.")])
        let agent = ComputerUseAgent(
            model: model,
            tools: FreshnessCheckingComputerUseBackend(),
            screenshots: SelectiveComputerUseScreenshotLoader(missingFile: "state-2.jpg")
        )
        let conversation = (0..<3).map { index in
            ComputerUseConversationMessage(
                activity: ComputerUseActivity(
                    toolName: "get_app_state",
                    arguments: #"{"app":"App\#(index)"}"#,
                    output: #"{"app":"App\#(index)","screenshot":"file:///tmp/state-\#(index).jpg","text":"state-\#(index)"}"#
                )
            )
        }

        _ = await agent.run(
            task: ComputerUseAgentTask(instruction: "Continue.", conversation: conversation)
        )

        let request = await model.requests[0]
        let imageLabels = request.compactMap { message -> String? in
            guard case let .parts(parts) = message.content else { return nil }
            guard case let .text(label)? = parts.first else { return nil }
            return label
        }
        XCTAssertEqual(
            imageLabels,
            ["Current App0 screenshot.", "Current App1 screenshot."]
        )
    }

    func testReferencePolicyUsesSelectedModelMetadata() {
        let luna = ComputerUseModelContextPolicy.referenceAligned(modelID: "gpt-5.6-luna")
        let openRouterLuna = ComputerUseModelContextPolicy.referenceAligned(
            modelID: "openai/gpt-5.6-luna"
        )
        let fallback = ComputerUseModelContextPolicy.referenceAligned(modelID: "custom-model")

        XCTAssertEqual(luna.maximumContextTokens, 272_000)
        XCTAssertEqual(luna.maximumToolOutputTokens, 10_000)
        XCTAssertEqual(openRouterLuna, luna)
        XCTAssertEqual(fallback.maximumContextTokens, 100_000)
        XCTAssertEqual(fallback.maximumToolOutputTokens, 2_500)
    }

    func testMiddleTruncationPreservesUTF8BoundariesAndReportsReferenceTokenEstimate() {
        let text = String(repeating: "🟣", count: 100)

        let truncated = ComputerUseTokenTruncator.truncateMiddle(text, maximumTokens: 10)

        XCTAssertEqual(
            truncated,
            String(repeating: "🟣", count: 5)
                + "…90 tokens truncated…"
                + String(repeating: "🟣", count: 5)
        )
    }

}

/// Scripts observe Calculator/Chrome and write the observed text — the
/// code-mode equivalent of the old single get_app_state tool call.
private let observeCalculatorScript = """
const s = await computer.get_app_state({ app: "Calculator" });
nodeRepl.write(s.text);
"""

private let observeChromeScript = """
const s = await computer.get_app_state({ app: "Google Chrome" });
nodeRepl.write(s.text);
"""

private func nodeReplArguments(_ code: String) -> String {
    let data = try! JSONEncoder().encode(["code": code])
    return String(decoding: data, as: UTF8.self)
}

private func nodeReplCall(id: String, code: String) -> ComputerUseModelResponse {
    .toolCall(id: id, name: "node_repl", arguments: nodeReplArguments(code))
}

private func nodeReplCallMessage(id: String, code: String) -> ComputerUseModelMessage {
    .toolCall(id: id, name: "node_repl", arguments: nodeReplArguments(code))
}

private actor RecordingComputerUseActivitySink {
    private(set) var activities: [ComputerUseActivity] = []

    func record(_ activity: ComputerUseActivity) {
        activities.append(activity)
    }
}

/// Advances a fixed step on every read, so a run reaches its deadline
/// deterministically without sleeping.
private final class ManualComputerUseClock: @unchecked Sendable {
    private let lock = NSLock()
    private let step: Duration
    private var instant = ContinuousClock().now

    init(advancingBy step: Duration) {
        self.step = step
    }

    var now: ContinuousClock.Instant {
        lock.withLock {
            let current = instant
            instant = instant.advanced(by: step)
            return current
        }
    }
}

private final class RecordingComputerUseLogger: ComputerUseLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.withLock { recordedMessages }
    }

    func log(_ level: AppLogger.Level, _ message: String) {
        lock.withLock {
            recordedMessages.append(message)
        }
    }
}

private actor ScriptedComputerUseModel: ComputerUseModelServing {
    private var responses: [ComputerUseModelResponse]
    private(set) var requests: [[ComputerUseModelMessage]] = []

    init(responses: [ComputerUseModelResponse]) {
        self.responses = responses
    }

    func respond(to messages: [ComputerUseModelMessage]) async throws -> ComputerUseModelResponse {
        requests.append(messages)
        guard !responses.isEmpty else {
            throw ComputerUseModelError.invalidResponse("no scripted response")
        }
        return responses.removeFirst()
    }
}

private actor InterventionInjectingComputerUseModel: ComputerUseModelServing {
    private let interventions: ComputerUseInterventionChannel
    private var responseIndex = 0

    init(interventions: ComputerUseInterventionChannel) {
        self.interventions = interventions
    }

    func respond(to messages: [ComputerUseModelMessage]) async throws -> ComputerUseModelResponse {
        defer { responseIndex += 1 }
        switch responseIndex {
        case 0:
            return nodeReplCall(id: "script-1", code: observeCalculatorScript)
        case 1:
            interventions.submit("Actually, do not click anything")
            return nodeReplCall(id: "stale-script", code: """
            await computer.click({ app: "Calculator", element_index: 7 });
            """)
        default:
            return .text("Understood the correction.")
        }
    }
}

private struct MissingComputerUseScreenshotLoader: ComputerUseScreenshotLoading {
    func dataURL(for url: URL) async throws -> String {
        throw CocoaError(.fileNoSuchFile)
    }
}

private struct StubComputerUseScreenshotLoader: ComputerUseScreenshotLoading {
    func dataURL(for url: URL) async throws -> String {
        "data:image/jpeg;base64,\(url.lastPathComponent)"
    }
}

private struct SelectiveComputerUseScreenshotLoader: ComputerUseScreenshotLoading {
    let missingFile: String

    func dataURL(for url: URL) async throws -> String {
        guard url.lastPathComponent != missingFile else {
            throw CocoaError(.fileNoSuchFile)
        }
        return "data:image/jpeg;base64,\(url.lastPathComponent)"
    }
}

private actor FreshnessCheckingComputerUseBackend: ComputerUseToolServing {
    private(set) var calls: [ComputerUseToolName] = []
    private var hasObservedState = false
    private let screenshotURL: URL?
    private let shouldFailObservation: Bool
    private var appStateTexts: [String]
    private let interventionChannel: ComputerUseInterventionChannel?
    private let intervention: String?

    init(
        screenshotURL: URL? = nil,
        shouldFailObservation: Bool = false,
        appStateText: String = "0 AXStaticText: 42",
        appStateTexts: [String]? = nil,
        interventionChannel: ComputerUseInterventionChannel? = nil,
        intervention: String? = nil
    ) {
        self.screenshotURL = screenshotURL
        self.shouldFailObservation = shouldFailObservation
        self.appStateTexts = appStateTexts ?? [appStateText]
        self.interventionChannel = interventionChannel
        self.intervention = intervention
    }

    @discardableResult
    func execute(_ call: ComputerUseToolCall) async throws -> ComputerUseToolResult {
        switch call {
        case .listApps:
            calls.append(.listApps)
            return .applications([])
        case let .getAppState(app, _):
            calls.append(.getAppState)
            if shouldFailObservation {
                throw StubComputerUseToolError.failed
            }
            hasObservedState = true
            let text = appStateTexts.count > 1
                ? appStateTexts.removeFirst()
                : appStateTexts.first ?? ""
            return .appState(
                ComputerUseAppState(
                    app: app,
                    screenshot: screenshotURL,
                    text: text
                )
            )
        default:
            try requireObservedState(for: call.name)
            return .actionCompleted
        }
    }

    private func requireObservedState(for call: ComputerUseToolName) throws {
        guard hasObservedState else {
            throw ComputerUseActionError.observationRequired("Calculator")
        }
        hasObservedState = false
        calls.append(call)
        if let intervention {
            interventionChannel?.submit(intervention)
        }
    }
}

private enum StubComputerUseToolError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Tool failed."
    }
}
