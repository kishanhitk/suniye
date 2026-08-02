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
                point: ComputerUsePoint(x: 12.5, y: 24.25),
                screenshotID: "shot-1"
            ),
            .keyPress(key: .named(.returnKey), modifiers: modifiers),
            .keyPress(key: .character("a"), modifiers: ComputerUseKeyModifiers()),
            .scroll(horizontal: 4, vertical: -8),
            .typeText("secret text"),
            .setValue(elementIndex: 2, value: "new value"),
            .drag(
                from: ComputerUsePoint(x: 10, y: 20),
                to: ComputerUsePoint(x: 100, y: 120),
                screenshotID: "shot-1"
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
            .semantic(elementIndex: 3, action: .press),
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
                #"{"kind":"click","element_index":3,"click_count":2,"mouse_button":"r","screenshotId":"shot-1"}"#.utf8
            )
        )
        XCTAssertEqual(
            referenceClick,
            .clickElement(
                elementIndex: 3,
                clickCount: 2,
                mouseButton: .right,
                screenshotID: "shot-1"
            )
        )

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
        XCTAssertEqual(actions[9].risk, .semanticAccessibility)
        XCTAssertEqual(actions[10].risk, .semanticAccessibility)
        XCTAssertEqual(actions[4].textPreview, "secret text")
        XCTAssertEqual(actions[5].textPreview, "new value")
        XCTAssertEqual(actions[7].textPreview, "secret")
        XCTAssertNil(actions[0].textPreview)

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
            risk: action.risk,
            reason: "The user approved this exact text entry."
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
        XCTAssertEqual(request.textPreview, "(5 characters hidden)")
        XCTAssertEqual(ComputerUseApprovalScope.once, .once)
        XCTAssertEqual(ComputerUseApprovalDecision.allowOnce, .allowOnce)
        XCTAssertEqual(ComputerUseApprovalDecision.deny, .deny)
        XCTAssertEqual(ComputerUseApprovalDecision.stopSession, .stopSession)
    }

    func testPresentationValuesAndMalformedReferenceActions() throws {
        for risk in ComputerUseActionRisk.allCases {
            XCTAssertFalse(risk.title.isEmpty)
        }
        XCTAssertEqual(
            ComputerUseApprovalScope.allCases.map(\.title),
            ["Allow Once", "Allow for Session", "Always Allow"]
        )
        XCTAssertFalse(ComputerUseApprovalScope.once.isPersistent)
        XCTAssertTrue(ComputerUseApprovalScope.session.isPersistent)
        XCTAssertTrue(ComputerUseApprovalScope.always.isPersistent)
        XCTAssertEqual(ComputerUseApprovalDecision.allowOnce.scope, .once)
        XCTAssertEqual(ComputerUseApprovalDecision.allowForSession.scope, .session)
        XCTAssertEqual(ComputerUseApprovalDecision.allowAlways.scope, .always)
        XCTAssertNil(ComputerUseApprovalDecision.deny.scope)
        XCTAssertNil(ComputerUseApprovalDecision.stopSession.scope)

        let request = ComputerUseApprovalRequest(
            id: UUID(),
            action: .click(point: ComputerUsePoint(x: 1, y: 1)),
            target: makePhase2Observation().target,
            risk: .click,
            reason: "Click"
        )
        XCTAssertNil(request.textPreview)

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

        let malformedActions = [
            #"{"kind":"click","x":1}"#,
            #"{"kind":"scroll","horizontal":0,"vertical":0,"x":1}"#,
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
            .targetNotFrontmost,
            .invalidAction("bad bounds"),
            .unsupportedKey("?") ,
            .eventCreationFailed,
            .semanticActionFailed("AXPress"),
            .accessibilityValueActionFailed("not editable"),
            .textSelectionFailed("not found"),
            .textInsertionFailed("clipboard unavailable"),
            .staleScreenshot,
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}

final class ComputerUsePhase2PolicyTests: XCTestCase {
    func testPolicyAcceptsSupportedActionsFromTheObservation() throws {
        let observation = makePhase2Observation()

        let actions: [ComputerUseAction] = [
            .click(point: ComputerUsePoint(x: 100, y: 100)),
            .keyPress(key: .named(.returnKey), modifiers: ComputerUseKeyModifiers()),
            .keyPress(key: .character("a"), modifiers: ComputerUseKeyModifiers()),
            .scroll(horizontal: 0, vertical: -400),
            .typeText("hello"),
            .setValue(elementIndex: 0, value: "hello"),
            .drag(
                from: ComputerUsePoint(x: 10, y: 10),
                to: ComputerUsePoint(x: 200, y: 200)
            ),
            .selectText(elementIndex: 0, text: "hello"),
            .clickElement(elementIndex: 0),
            .secondaryAction(elementIndex: 0, action: "AXPress"),
            .semantic(elementIndex: 0, action: .press),
            .semantic(elementIndex: 1, action: .increment),
        ]

        for action in actions {
            XCTAssertNoThrow(try ComputerUseActionPolicy.validate(action: action, observation: observation))
        }
    }

    func testPolicyRejectsOutOfBoundsAndNonFiniteClicks() {
        let observation = makePhase2Observation()

        assertActionError(.invalidAction("click must be inside the target window")) {
            try ComputerUseActionPolicy.validate(
                action: .click(point: ComputerUsePoint(x: 640.1, y: 100)),
                observation: observation
            )
        }
        assertActionError(.invalidAction("click must be inside the target window")) {
            try ComputerUseActionPolicy.validate(
                action: .click(point: ComputerUsePoint(x: .nan, y: 100)),
                observation: observation
            )
        }
    }

    func testPolicyRejectsInvalidKeysScrollTextAndSemanticActions() {
        let observation = makePhase2Observation()

        assertActionError(.invalidAction("character key must contain one character")) {
            try ComputerUseActionPolicy.validate(
                action: .keyPress(key: .character("ab"), modifiers: ComputerUseKeyModifiers()),
                observation: observation
            )
        }
        assertActionError(.invalidAction("scroll values exceed the allowed range")) {
            try ComputerUseActionPolicy.validate(
                action: .scroll(horizontal: 5_001, vertical: 0),
                observation: observation
            )
        }
        assertActionError(.invalidAction("scroll values exceed the allowed range")) {
            try ComputerUseActionPolicy.validate(
                action: .scroll(horizontal: .infinity, vertical: 0),
                observation: observation
            )
        }
        assertActionError(.invalidAction("text must contain between 1 and 10,000 characters")) {
            try ComputerUseActionPolicy.validate(
                action: .typeText(""),
                observation: observation
            )
        }
        assertActionError(.invalidAction("text must contain between 1 and 10,000 characters")) {
            try ComputerUseActionPolicy.validate(
                action: .typeText(String(repeating: "x", count: 10_001)),
                observation: observation
            )
        }
        assertActionError(.invalidAction("element index is not in the observation")) {
            try ComputerUseActionPolicy.validate(
                action: .semantic(elementIndex: 99, action: .press),
                observation: observation
            )
        }
        assertActionError(.invalidAction("the element does not expose AXPress")) {
            try ComputerUseActionPolicy.validate(
                action: .semantic(elementIndex: 1, action: .press),
                observation: observation
            )
        }
        assertActionError(.invalidAction("the element does not expose AXShowMenu")) {
            try ComputerUseActionPolicy.validate(
                action: .secondaryAction(elementIndex: 1, action: "AXShowMenu"),
                observation: observation
            )
        }

        let disabledElement = ComputerUseAXElement(
            index: 0,
            role: "AXButton",
            subrole: nil,
            title: "OK",
            description: nil,
            value: nil,
            isEnabled: false,
            isFocused: false,
            isSelected: false,
            bounds: nil,
            actions: ["AXPress"],
            childIndexes: []
        )
        let disabledObservation = ComputerUseObservation(
            generation: observation.generation,
            capturedAt: observation.capturedAt,
            target: observation.target,
            accessibility: ComputerUseAXSnapshot(
                text: "disabled",
                elements: [disabledElement],
                wasTruncated: false
            ),
            screenshot: nil
        )
        assertActionError(.invalidAction("the element is disabled")) {
            try ComputerUseActionPolicy.validate(
                action: .semantic(elementIndex: 0, action: .press),
                observation: disabledObservation
            )
        }
    }
}

final class ComputerUsePhase2ServiceTests: XCTestCase {
    func testActionServiceExecutesEachSupportedActionKind() throws {
        let observation = makePhase2Observation()
        let input = Phase2StubInputEventPoster()
        let text = Phase2StubTextInserter()
        let semantic = Phase2StubSemanticActionPerformer()
        let value = Phase2StubValueActionPerformer()
        let service = ComputerUseActionService(
            inputEventPoster: input,
            textInserter: text,
            semanticActionPerformer: semantic,
            valueActionPerformer: value,
            targetValidator: Phase2StubTargetValidator(isCurrent: true),
            permissionManager: Phase2StubPermissionManager(granted: true),
            dateProvider: { Date(timeIntervalSince1970: 3_000) }
        )

        let click = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let key = ComputerUseAction.keyPress(
            key: .named(.returnKey),
            modifiers: ComputerUseKeyModifiers(command: true)
        )
        let scroll = ComputerUseAction.scroll(horizontal: 2, vertical: -400)
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
            elementIndex: 0,
            action: "axpress"
        )
        let semanticAction = ComputerUseAction.semantic(elementIndex: 0, action: .press)

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
            semanticAction,
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
            input.scrolls,
            [Phase2StubInputEventPoster.ScrollCall(horizontal: 2, vertical: -400)]
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
            semantic.actions,
            [
                Phase2StubSemanticActionPerformer.ActionCall(action: "AXPress", elementIndex: 0),
                Phase2StubSemanticActionPerformer.ActionCall(action: "AXPress", elementIndex: 0),
            ]
        )
    }

    func testActionServiceEnforcesApprovalPermissionAndCurrentTarget() {
        let observation = makePhase2Observation()
        let action = ComputerUseAction.click(point: ComputerUsePoint(x: 50, y: 50))
        let permission = Phase2StubPermissionManager(granted: true)
        let target = Phase2StubTargetValidator(isCurrent: true)
        let service = ComputerUseActionService(
            inputEventPoster: Phase2StubInputEventPoster(),
            textInserter: Phase2StubTextInserter(),
            semanticActionPerformer: Phase2StubSemanticActionPerformer(),
            targetValidator: target,
            permissionManager: permission
        )

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
        target.isCurrent = false
        let targetGrant = makePhase2Grant(action: action, observation: observation)
        assertActionError(.targetNotFrontmost) {
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
            semanticActionPerformer: Phase2StubSemanticActionPerformer(),
            targetValidator: Phase2StubTargetValidator(isCurrent: true),
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

        let input = Phase2StubInputEventPoster()
        input.error = ComputerUseActionError.eventCreationFailed
        let eventService = ComputerUseActionService(
            inputEventPoster: input,
            textInserter: Phase2StubTextInserter(),
            semanticActionPerformer: Phase2StubSemanticActionPerformer(),
            targetValidator: Phase2StubTargetValidator(isCurrent: true),
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

    func testPolicyRejectsInvalidExpandedActions() {
        let observation = makePhase2Observation()

        assertActionError(.invalidAction("click count must be between 1 and 3")) {
            try ComputerUseActionPolicy.validate(
                action: .click(point: ComputerUsePoint(x: 10, y: 10), clickCount: 4),
                observation: observation
            )
        }
        assertActionError(.invalidAction("drag points must be inside the target window")) {
            try ComputerUseActionPolicy.validate(
                action: .drag(
                    from: ComputerUsePoint(x: 10, y: 10),
                    to: ComputerUsePoint(x: 700, y: 10)
                ),
                observation: observation
            )
        }
        assertActionError(.invalidAction("value must contain between 1 and 10,000 characters")) {
            try ComputerUseActionPolicy.validate(
                action: .setValue(elementIndex: 0, value: ""),
                observation: observation
            )
        }
        assertActionError(.invalidAction("selected text must contain between 1 and 10,000 characters")) {
            try ComputerUseActionPolicy.validate(
                action: .selectText(elementIndex: 0, text: ""),
                observation: observation
            )
        }
        assertActionError(.invalidAction("text selection context is too large")) {
            try ComputerUseActionPolicy.validate(
                action: .selectText(
                    elementIndex: 0,
                    text: "hello",
                    prefix: String(repeating: "x", count: 2_001)
                ),
                observation: observation
            )
        }
        assertActionError(.invalidAction("element bounds must be inside the target window")) {
            let noBoundsElement = ComputerUseAXElement(
                index: 2,
                role: "AXButton",
                subrole: nil,
                title: "No bounds",
                description: nil,
                value: nil,
                isEnabled: true,
                isFocused: false,
                isSelected: false,
                bounds: nil,
                actions: ["AXPress"],
                childIndexes: []
            )
            let noBoundsObservation = ComputerUseObservation(
                generation: observation.generation,
                capturedAt: observation.capturedAt,
                target: observation.target,
                accessibility: ComputerUseAXSnapshot(
                    text: "no bounds",
                    elements: [noBoundsElement],
                    wasTruncated: false
                ),
                screenshot: nil
            )
            try ComputerUseActionPolicy.validate(
                action: .clickElement(elementIndex: 2),
                observation: noBoundsObservation
            )
        }

        let screenshotObservation = ComputerUseObservation(
            generation: observation.generation,
            capturedAt: observation.capturedAt,
            target: observation.target,
            accessibility: observation.accessibility,
            screenshot: ComputerUseScreenshot(
                id: "shot-1",
                data: Data(),
                mimeType: "image/png",
                width: 1,
                height: 1
            )
        )
        XCTAssertNoThrow(
            try ComputerUseActionPolicy.validate(
                action: .click(
                    point: ComputerUsePoint(x: 10, y: 10),
                    screenshotID: "shot-1"
                ),
                observation: screenshotObservation
            )
        )
        assertActionError(.staleScreenshot) {
            try ComputerUseActionPolicy.validate(
                action: .click(
                    point: ComputerUsePoint(x: 10, y: 10),
                    screenshotID: "old-shot"
                ),
                observation: screenshotObservation
            )
        }
    }

    func testTargetValidatorRequiresFrontmostProcessAndCurrentWindow() {
        let application = makePhase2Observation().target.application
        let window = makePhase2Observation().target.window
        let discovery = Phase2StubWindowDiscovery(windows: [window])
        var frontmostProcessIdentifier: Int32? = application.processIdentifier
        let validator = SystemComputerUseTargetValidator(
            windowDiscovery: discovery,
            frontmostProcessIdentifierProvider: { frontmostProcessIdentifier }
        )
        let target = ComputerUseTarget(application: application, window: window)

        XCTAssertTrue(validator.isCurrent(target: target))
        frontmostProcessIdentifier = 999
        XCTAssertFalse(validator.isCurrent(target: target))
        frontmostProcessIdentifier = application.processIdentifier
        discovery.windows = []
        XCTAssertFalse(validator.isCurrent(target: target))

        let nonKeyWindow = ComputerUseWindow(
            id: window.id,
            title: window.title,
            ownerProcessIdentifier: window.ownerProcessIdentifier,
            bounds: window.bounds,
            layer: window.layer,
            isOnScreen: window.isOnScreen,
            isKeyWindow: false
        )
        discovery.windows = [nonKeyWindow]
        XCTAssertFalse(validator.isCurrent(target: target))
    }
}
