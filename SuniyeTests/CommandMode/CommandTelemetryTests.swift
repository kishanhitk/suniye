import XCTest
import SuniyeAnalytics
@testable import Suniye

@MainActor
final class CommandTelemetryTests: XCTestCase {
    // MARK: Live-log labels name the action, never the content

    func testStepLabelsNameActionNotContent() {
        XCTAssertEqual(AppState.commandStepLabel(for: ToolCall(name: "open_app", arguments: ["name": "Safari"])), "Opening Safari")
        XCTAssertEqual(AppState.commandStepLabel(for: ToolCall(name: "press_keys", arguments: ["keys": "cmd+t"])), "Pressing cmd+t")
        XCTAssertEqual(AppState.commandStepLabel(for: ToolCall(name: "read_screen", arguments: [:])), "Reading the screen")

        // type_text must NOT echo the typed text into the on-screen pill.
        let typing = AppState.commandStepLabel(for: ToolCall(name: "type_text", arguments: ["text": "my secret password"]))
        XCTAssertEqual(typing, "Typing")
        XCTAssertFalse(typing.contains("secret"))

        // run_applescript must NOT echo the script body.
        let script = AppState.commandStepLabel(for: ToolCall(name: "run_applescript", arguments: ["script": "do shell script \"rm x\""]))
        XCTAssertEqual(script, "Running a script")
        XCTAssertFalse(script.contains("rm"))

        XCTAssertEqual(AppState.commandStepLabel(for: ToolCall(name: "unheard_of", arguments: [:])), "Working…")
    }

    // MARK: AgentOutcome → CommandOutcome mapping

    func testCommandOutcomeMapping() {
        XCTAssertEqual(AnalyticsMapping.commandOutcome(.completed), .completed)
        XCTAssertEqual(AnalyticsMapping.commandOutcome(.stalled), .stalled)
        XCTAssertEqual(AnalyticsMapping.commandOutcome(.stepLimit), .stepLimit)
        XCTAssertEqual(AnalyticsMapping.commandOutcome(.cancelled), .cancelled)
        XCTAssertEqual(AnalyticsMapping.commandOutcome(.brainFailure), .brainFailure)
    }

    // MARK: command_completed / command_blocked are counts/enums only — no free text

    func testCommandCompletedEventIsContentFree() {
        let metrics = CommandMetrics(
            outcome: .completed, stepCount: 3, toolInvocations: 2, invalidActions: 1,
            brainProvider: .localGemma, brainModel: SafeLabel("gemma-3n-e2b"),
            targetCategory: .browser, spokenDurationMs: 1500, agentRuntimeMs: 4200
        )
        let event = AnalyticsEvent.commandCompleted(metrics)
        XCTAssertEqual(event.name, "command_completed")

        let props = event.props
        XCTAssertEqual(props["outcome"], .label("completed"))
        XCTAssertEqual(props["step_count"], .int(3))
        XCTAssertEqual(props["tool_invocations"], .int(2))
        XCTAssertEqual(props["invalid_actions"], .int(1))
        XCTAssertEqual(props["brain_provider"], .label("local_gemma"))
        XCTAssertEqual(props["brain_model"], .label("gemma-3n-e2b"))
        XCTAssertEqual(props["target_category"], .label("browser"))
        XCTAssertEqual(props["spoken_duration_ms"], .int(1500))
        XCTAssertEqual(props["agent_runtime_ms"], .int(4200))

        // Structural privacy: every value is a number, bool, or a bounded label.
        for value in props.values {
            switch value {
            case .int, .double, .bool:
                continue
            case let .label(text):
                XCTAssertLessThanOrEqual(text.count, SafeLabel.maxLength)
            }
        }
    }

    func testCommandBlockedEvent() {
        let event = AnalyticsEvent.commandBlocked(reason: .accessibilityDenied)
        XCTAssertEqual(event.name, "command_blocked")
        XCTAssertEqual(event.props["reason"], .label("accessibility_denied"))
    }

    func testBrainModelOmittedWhenNil() {
        let metrics = CommandMetrics(
            outcome: .stepLimit, stepCount: 12, toolInvocations: 8, invalidActions: 0,
            brainProvider: .appleFoundationModels, targetCategory: .other,
            spokenDurationMs: 900, agentRuntimeMs: 15000
        )
        XCTAssertNil(AnalyticsEvent.commandCompleted(metrics).props["brain_model"])
    }
}
