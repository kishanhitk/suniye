import CoreGraphics
import Foundation
import XCTest
@testable import Suniye

final class ComputerUsePhase2ModelTests: XCTestCase {
    func testActionsRoundTripThroughCodableAndExposeSafeSummaries() throws {
        let modifiers = ComputerUseKeyModifiers(
            command: true,
            option: true,
            control: true,
            shift: true,
            function: true
        )
        let actions: [ComputerUseAction] = [
            .click(
                point: ComputerUsePoint(x: 12.5, y: 24.25)
            ),
            .keyPress(key: .named(.returnKey), modifiers: modifiers),
            .keyPress(key: .character("a"), modifiers: ComputerUseKeyModifiers()),
            .scroll(elementIndex: 0, direction: .up),
            .typeText("secret text"),
            .setValue(elementIndex: 2, value: "new value"),
            .drag(
                from: ComputerUsePoint(x: 10, y: 20),
                to: ComputerUsePoint(x: 100, y: 120)
            ),
            .selectText(
                elementIndex: 2,
                text: "secret",
                prefix: "a ",
                suffix: " value",
                selectionType: .text
            ),
            .clickElement(elementIndex: 3, clickCount: 2, mouseButton: .right),
            .secondaryAction(elementIndex: 3, action: "AXShowMenu"),
            .secondaryAction(elementIndex: 3, action: "AXPress"),
        ]

        for action in actions {
            let encoded = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(ComputerUseAction.self, from: encoded)
            XCTAssertEqual(decoded, action)
            XCTAssertFalse(action.summary.isEmpty)
        }

        let referenceClick = try JSONDecoder().decode(
            ComputerUseAction.self,
            from: Data(
                #"{"kind":"click","element_index":3,"click_count":2,"mouse_button":"r"}"#.utf8
            )
        )
        XCTAssertEqual(
            referenceClick,
            .clickElement(
                elementIndex: 3,
                clickCount: 2,
                mouseButton: .right
            )
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseAction.self,
                from: Data(#"{"kind":"click","x":1,"y":2,"mouse_button":2}"#.utf8)
            ),
            .click(
                point: ComputerUsePoint(x: 1, y: 2),
                mouseButton: .middle
            )
        )
        XCTAssertEqual(ComputerUsePoint(x: 3, y: 4).cgPoint, CGPoint(x: 3, y: 4))
        for invalidButton in ["3", "side"] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    ComputerUseAction.self,
                    from: Data(
                        #"{"kind":"click","x":1,"y":2,"mouse_button":\#(invalidButton)}"#.utf8
                    )
                )
            )
        }
        for direction in ["left", "right"] {
            let raw = #"{"kind":"scroll","element_index":1,"direction":"\#(direction)"}"#
            XCTAssertNoThrow(
                try JSONDecoder().decode(ComputerUseAction.self, from: Data(raw.utf8))
            )
        }

        let encodedReferenceAction = try JSONEncoder().encode(referenceClick)
        let encodedReferenceJSON = try XCTUnwrap(String(data: encodedReferenceAction, encoding: .utf8))
        XCTAssertTrue(encodedReferenceJSON.contains("element_index"))
        XCTAssertTrue(encodedReferenceJSON.contains("click_count"))
        XCTAssertTrue(encodedReferenceJSON.contains("mouse_button"))

        XCTAssertEqual(actions[0].risk, .click)
        XCTAssertEqual(actions[1].risk, .keyPress)
        XCTAssertEqual(actions[2].risk, .keyPress)
        XCTAssertEqual(actions[3].risk, .scroll)
        XCTAssertEqual(actions[4].risk, .textEntry)
        XCTAssertEqual(actions[5].risk, .textEntry)
        XCTAssertEqual(actions[6].risk, .drag)
        XCTAssertEqual(actions[7].risk, .textSelection)
        XCTAssertEqual(actions[8].risk, .click)
        XCTAssertEqual(actions[9].risk, .secondaryAccessibility)
        XCTAssertEqual(actions[10].risk, .secondaryAccessibility)

        let referenceScroll = ComputerUseAction.scroll(
            elementIndex: 3,
            direction: .down,
            pages: 2
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseAction.self,
                from: JSONEncoder().encode(referenceScroll)
            ),
            referenceScroll
        )
        XCTAssertEqual(referenceScroll.summary, "Scroll down 2.0x on element 3")
        XCTAssertEqual(ComputerUseKey.named(.forwardDelete).displayName, "Forward Delete")
        XCTAssertEqual(ComputerUseKey.character("a").displayName, "a")
        XCTAssertEqual(
            ComputerUseAction.keyPress(key: .named(.returnKey), modifiers: modifiers).summary,
            "Press Command + Option + Control + Shift + Function + Return"
        )
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskCommand))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskAlternate))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskControl))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskShift))
        XCTAssertTrue(modifiers.cgEventFlags.contains(.maskSecondaryFn))
    }

    func testApprovalAndResultValuesRoundTripThroughCodable() throws {
        let observation = makePhase2Observation()
        let action = ComputerUseAction.typeText("hello")
        let request = ComputerUseApprovalRequest(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            action: action,
            target: observation.target,
            risk: action.risk
        )
        let grant = ComputerUseApprovalGrant(
            requestID: request.id,
            scope: .once,
            applicationID: observation.target.application.id,
            windowID: observation.target.window.id,
            observationGeneration: observation.generation,
            action: action
        )
        let result = ComputerUseActionResult(
            action: action,
            target: observation.target,
            completedAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseApprovalRequest.self,
                from: JSONEncoder().encode(request)
            ),
            request
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseApprovalGrant.self,
                from: JSONEncoder().encode(grant)
            ),
            grant
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ComputerUseActionResult.self,
                from: JSONEncoder().encode(result)
            ),
            result
        )
        XCTAssertEqual(ComputerUseApprovalScope.once, .once)
    }

    func testMalformedReferenceActions() throws {
        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .click(point: ComputerUsePoint(x: 1, y: 1)),
            target: makePhase2Observation().target,
            risk: .click
        )

        for (rawValue, expected) in [("left", ComputerUseMouseButton.left), ("l", .left),
                                     ("middle", .middle), ("m", .middle)] {
            let action = try JSONDecoder().decode(
                ComputerUseAction.self,
                from: Data(
                    #"{"kind":"click","x":1,"y":1,"mouse_button":"\#(rawValue)"}"#.utf8
                )
            )
            XCTAssertEqual(
                action,
                .click(point: ComputerUsePoint(x: 1, y: 1), mouseButton: expected)
            )
        }

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ComputerUseAction.self,
                from: Data(#"{"kind":"click","x":1,"y":1,"mouse_button":"side"}"#.utf8)
            )
        )

        XCTAssertThrowsError(try ComputerUseKey.parseChord(""))
        XCTAssertThrowsError(try ComputerUseKey.parseChord("Command+"))
        XCTAssertThrowsError(try ComputerUseKey.parseChord("Super+Unknown+a"))
        XCTAssertEqual(
            try ComputerUseKey.parseChord("Control_L+less").key,
            .character(",")
        )

        let namedKeys: [String: ComputerUseNamedKey] = [
            "Tab": .tab,
            "Escape": .escape,
            "space": .space,
            "BackSpace": .delete,
            "Delete": .forwardDelete,
            "Left": .arrowLeft,
            "Right": .arrowRight,
            "Down": .arrowDown,
            "Up": .arrowUp,
            "Home": .home,
            "End": .end,
            "Page_Up": .pageUp,
            "Page_Down": .pageDown,
        ]
        for (rawKey, expectedKey) in namedKeys {
            XCTAssertEqual(try ComputerUseKey.parseChord(rawKey).key, .named(expectedKey))
        }

        let malformedActions = [
            #"{"kind":"click","x":1}"#,
            #"{"kind":"scroll","element_index":1,"direction":"side"}"#,
            #"{"kind":"type_text"}"#,
            #"{"kind":"set_value","element_index":1}"#,
            #"{"kind":"drag","from_x":1,"from_y":1,"to_x":2}"#,
            #"{"kind":"select_text","element_index":1,"text":"x","selection_type":"bad"}"#,
        ]
        for rawAction in malformedActions {
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    ComputerUseAction.self,
                    from: Data(rawAction.utf8)
                ),
                "Expected malformed action to be rejected: \(rawAction)"
            )
        }
    }

    func testActionErrorsHaveUserFacingDescriptions() {
        let errors: [ComputerUseActionError] = [
            .cancelled,
            .approvalRequired,
            .staleApproval,
            .permissionRequired,
            .targetActivationFailed,
            .invalidAction("bad bounds"),
            .unsupportedKey("?") ,
            .eventCreationFailed,
            .secondaryActionFailed("AXPress"),
            .accessibilityValueActionFailed("not editable"),
            .textSelectionFailed("not found"),
            .textInsertionFailed("clipboard unavailable"),
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}

final class ComputerUsePhase2ServiceTests: XCTestCase {
    func testActionServiceExecutesEachSupportedActionKind() throws {
        let observation = makePhase2Observation()
        let input = Phase2StubInputEventPoster()
        let text = Phase2StubTextInserter()
        let secondary = Phase2StubSecondaryActionPerformer()
        let value = Phase2StubValueActionPerformer()
        let service = ComputerUseActionService(
            inputEventPoster: input,
            textInserter: text,
            secondaryActionPerformer: secondary,
            valueActionPerformer: value,
            targetActivator: Phase2StubWindowActivator(),
            permissionManager: Phase2StubPermissionManager(granted: true),
            dateProvider: { Date(timeIntervalSince1970: 3_000) }
        )

        let click = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let key = ComputerUseAction.keyPress(
            key: .named(.returnKey),
            modifiers: ComputerUseKeyModifiers(command: true)
        )
        let scroll = ComputerUseAction.scroll(elementIndex: 0, direction: .up)
        let type = ComputerUseAction.typeText("hello")
        let setValue = ComputerUseAction.setValue(elementIndex: 0, value: "new value")
        let drag = ComputerUseAction.drag(
            from: ComputerUsePoint(x: 20, y: 20),
            to: ComputerUsePoint(x: 200, y: 200)
        )
        let selectText = ComputerUseAction.selectText(
            elementIndex: 0,
            text: "hello",
            selectionType: .cursorAfter
        )
        let elementClick = ComputerUseAction.clickElement(
            elementIndex: 0,
            clickCount: 2,
            mouseButton: .right
        )
        let secondaryAction = ComputerUseAction.secondaryAction(
            elementIndex: 99,
            action: "axpress"
        )

        for action in [
            click,
            key,
            scroll,
            type,
            setValue,
            drag,
            selectText,
            elementClick,
            secondaryAction,
        ] {
            let grant = makePhase2Grant(action: action, observation: observation)
            let result = try service.execute(
                action: action,
                observation: observation,
                approval: grant,
                requestID: grant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
            XCTAssertEqual(result.action, action)
            XCTAssertEqual(result.target, observation.target)
            XCTAssertEqual(result.completedAt, Date(timeIntervalSince1970: 3_000))
        }

        XCTAssertEqual(
            input.clicks,
            [
                ComputerUsePoint(x: 50, y: 50),
                ComputerUsePoint(x: 90, y: 60),
                ComputerUsePoint(x: 90, y: 60),
            ]
        )
        XCTAssertEqual(input.keys.count, 1)
        XCTAssertEqual(input.keys[0].key, keyKey(key))
        XCTAssertEqual(
            input.keys[0].targetProcessIdentifier,
            observation.target.application.processIdentifier
        )
        XCTAssertEqual(
            input.scrolls,
            [Phase2StubInputEventPoster.ScrollCall(horizontal: 0, vertical: -400)]
        )
        XCTAssertEqual(text.insertedTexts, ["hello"])
        XCTAssertEqual(
            input.drags,
            [
                Phase2StubInputEventPoster.DragCall(
                    start: ComputerUsePoint(x: 20, y: 20),
                    end: ComputerUsePoint(x: 200, y: 200)
                ),
            ]
        )
        XCTAssertEqual(
            value.setValues,
            [Phase2StubValueActionPerformer.SetValueCall(elementIndex: 0, value: "new value")]
        )
        XCTAssertEqual(
            value.selections,
            [
                Phase2StubValueActionPerformer.SelectTextCall(
                    elementIndex: 0,
                    text: "hello",
                    prefix: nil,
                    suffix: nil,
                    selectionType: .cursorAfter
                ),
            ]
        )
        XCTAssertEqual(
            secondary.actions,
            [
                Phase2StubSecondaryActionPerformer.ActionCall(action: "axpress", elementIndex: 99),
            ]
        )
    }

    func testActionServiceValidatesTransportShapeWithoutInspectingCachedElements() {
        let observation = makePhase2Observation()
        let service = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: Phase2StubTextInserter(),
            secondaryActionPerformer: Phase2StubSecondaryActionPerformer(),
            targetActivator: Phase2StubWindowActivator(),
            permissionManager: Phase2StubPermissionManager(granted: true)
        )

        let unknownElementAction = ComputerUseAction.secondaryAction(
            elementIndex: 1234,
            action: "AXWhatever"
        )
        let unknownElementGrant = makePhase2Grant(
            action: unknownElementAction,
            observation: observation
        )
        XCTAssertNoThrow(
            try service.execute(
                action: unknownElementAction,
                observation: observation,
                approval: unknownElementGrant,
                requestID: unknownElementGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        )

        let invalidClick = ComputerUseAction.click(
            point: ComputerUsePoint(x: .nan, y: 1)
        )
        let invalidClickGrant = makePhase2Grant(action: invalidClick, observation: observation)
        assertActionError(.invalidAction("click coordinates must be finite")) {
            _ = try service.execute(
                action: invalidClick,
                observation: observation,
                approval: invalidClickGrant,
                requestID: invalidClickGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let invalidScroll = ComputerUseAction.scroll(
            elementIndex: 999,
            direction: .down,
            pages: 0
        )
        let invalidScrollGrant = makePhase2Grant(action: invalidScroll, observation: observation)
        assertActionError(.invalidAction("pages must be a finite number greater than 0")) {
            _ = try service.execute(
                action: invalidScroll,
                observation: observation,
                approval: invalidScrollGrant,
                requestID: invalidScrollGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let invalidClickCount = ComputerUseAction.click(
            point: ComputerUsePoint(x: 1, y: 1),
            clickCount: 0
        )
        let invalidClickCountGrant = makePhase2Grant(
            action: invalidClickCount,
            observation: observation
        )
        assertActionError(.invalidAction("click count must be at least 1")) {
            _ = try service.execute(
                action: invalidClickCount,
                observation: observation,
                approval: invalidClickCountGrant,
                requestID: invalidClickCountGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let invalidElementClickCount = ComputerUseAction.clickElement(
            elementIndex: 999,
            clickCount: 0
        )
        let invalidElementClickCountGrant = makePhase2Grant(
            action: invalidElementClickCount,
            observation: observation
        )
        assertActionError(.invalidAction("click count must be at least 1")) {
            _ = try service.execute(
                action: invalidElementClickCount,
                observation: observation,
                approval: invalidElementClickCountGrant,
                requestID: invalidElementClickCountGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let invalidDrag = ComputerUseAction.drag(
            from: ComputerUsePoint(x: .nan, y: 1),
            to: ComputerUsePoint(x: 2, y: 3)
        )
        let invalidDragGrant = makePhase2Grant(action: invalidDrag, observation: observation)
        assertActionError(.invalidAction("drag coordinates must be finite")) {
            _ = try service.execute(
                action: invalidDrag,
                observation: observation,
                approval: invalidDragGrant,
                requestID: invalidDragGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }
    }

    func testActionServiceDelegatesUnknownIndexedClicksAndHorizontalScrolls() throws {
        let observation = makePhase2Observation()
        let input = Phase2StubInputEventPoster()
        let secondary = Phase2StubSecondaryActionPerformer()
        let service = ComputerUseActionService(
            inputEventPoster: input,
            textInserter: Phase2StubTextInserter(),
            secondaryActionPerformer: secondary,
            targetActivator: Phase2StubWindowActivator(),
            permissionManager: Phase2StubPermissionManager(granted: true)
        )

        let indexedClick = ComputerUseAction.clickElement(
            elementIndex: 999,
            clickCount: 2
        )
        let clickGrant = makePhase2Grant(action: indexedClick, observation: observation)
        _ = try service.execute(
            action: indexedClick,
            observation: observation,
            approval: clickGrant,
            requestID: clickGrant.requestID,
            cancellation: ComputerUseCancellationToken()
        )

        for direction in [ComputerUseScrollDirection.left, .right] {
            let scroll = ComputerUseAction.scroll(
                elementIndex: 999,
                direction: direction,
                pages: 1.5
            )
            let grant = makePhase2Grant(action: scroll, observation: observation)
            _ = try service.execute(
                action: scroll,
                observation: observation,
                approval: grant,
                requestID: grant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        XCTAssertEqual(
            secondary.actions,
            [
                Phase2StubSecondaryActionPerformer.ActionCall(action: "AXPress", elementIndex: 999),
                Phase2StubSecondaryActionPerformer.ActionCall(action: "AXPress", elementIndex: 999),
            ]
        )
        XCTAssertEqual(
            input.scrolls,
            [
                Phase2StubInputEventPoster.ScrollCall(horizontal: -600, vertical: 0),
                Phase2StubInputEventPoster.ScrollCall(horizontal: 600, vertical: 0),
            ]
        )
    }

    func testActionServiceEnforcesApprovalPermissionAndTargetActivation() {
        let observation = makePhase2Observation()
        let action = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let permission = Phase2StubPermissionManager(granted: true)
        let targetActivator = Phase2StubWindowActivator()
        let service = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: Phase2StubTextInserter(),
            secondaryActionPerformer: Phase2StubSecondaryActionPerformer(),
            targetActivator: targetActivator,
            permissionManager: permission
        )

        let policyBlockedService = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: Phase2StubTextInserter(),
            secondaryActionPerformer: Phase2StubSecondaryActionPerformer(),
            targetActivator: targetActivator,
            permissionManager: permission,
            policy: ComputerUsePolicyService(
                configuration: ComputerUsePolicyConfiguration(
                    deniedBundleIdentifiers: [observation.target.application.bundleIdentifier]
                )
            )
        )
        let policyGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.approvalRequired) {
            _ = try policyBlockedService.execute(
                action: action,
                observation: observation,
                approval: policyGrant,
                requestID: policyGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let staleGrant = ComputerUseApprovalGrant(
            requestID: UUID(),
            scope: .once,
            applicationID: observation.target.application.id,
            windowID: observation.target.window.id,
            observationGeneration: observation.generation + 1,
            action: action
        )
        assertActionError(.staleApproval) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: staleGrant,
                requestID: staleGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let mismatchedRequestGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.staleApproval) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: mismatchedRequestGrant,
                requestID: UUID(),
                cancellation: ComputerUseCancellationToken()
            )
        }

        permission.setGranted(false)
        let permissionGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.permissionRequired) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: permissionGrant,
                requestID: permissionGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        permission.setGranted(true)
        targetActivator.result = false
        let targetGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.targetActivationFailed) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: targetGrant,
                requestID: targetGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let cancellation = ComputerUseCancellationToken()
        cancellation.cancel()
        let cancellationGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.cancelled) {
            _ = try service.execute(
                action: action,
                observation: observation,
                approval: cancellationGrant,
                requestID: cancellationGrant.requestID,
                cancellation: cancellation
            )
        }
    }

    func testActionServiceMapsTextInsertionFailuresAndPropagatesNativeErrors() {
        let observation = makePhase2Observation()
        let text = Phase2StubTextInserter()
        text.insertError = Phase2TestError.insertion
        let service = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: text,
            secondaryActionPerformer: Phase2StubSecondaryActionPerformer(),
            targetActivator: Phase2StubWindowActivator(),
            permissionManager: Phase2StubPermissionManager(granted: true)
        )
        let type = ComputerUseAction.typeText("hello")
        let textGrant = makePhase2Grant(action: type, observation: observation)

        assertActionError(.textInsertionFailed("insert failed")) {
            _ = try service.execute(
                action: type,
                observation: observation,
                approval: textGrant,
                requestID: textGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        text.insertError = ComputerUseActionError.cancelled
        assertActionError(.cancelled) {
            _ = try service.execute(
                action: type,
                observation: observation,
                approval: textGrant,
                requestID: textGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }

        let input = Phase2StubInputEventPoster()
        input.error = ComputerUseActionError.eventCreationFailed
        let eventService = ComputerUseActionService(
            inputEventPoster: input,
            textInserter: Phase2StubTextInserter(),
            secondaryActionPerformer: Phase2StubSecondaryActionPerformer(),
            targetActivator: Phase2StubWindowActivator(),
            permissionManager: Phase2StubPermissionManager(granted: true)
        )
        let click = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let eventGrant = makePhase2Grant(action: click, observation: observation)
        assertActionError(.eventCreationFailed) {
            _ = try eventService.execute(
                action: click,
                observation: observation,
                approval: eventGrant,
                requestID: eventGrant.requestID,
                cancellation: ComputerUseCancellationToken()
            )
        }
    }

    func testActionServiceActivatesTheObservedTargetBeforeInput() throws {
        let observation = makePhase2Observation()
        let activator = Phase2StubWindowActivator()
        let service = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: Phase2StubTextInserter(),
            secondaryActionPerformer: Phase2StubSecondaryActionPerformer(),
            targetActivator: activator,
            permissionManager: Phase2StubPermissionManager(granted: true)
        )
        let action = ComputerUseAction.keyPress(
            key: .named(.escape),
            modifiers: ComputerUseKeyModifiers()
        )
        let grant = makePhase2Grant(action: action, observation: observation)

        _ = try service.execute(
            action: action,
            observation: observation,
            approval: grant,
            requestID: grant.requestID,
            cancellation: ComputerUseCancellationToken()
        )

        XCTAssertEqual(activator.targets, [observation.target])
    }
}
