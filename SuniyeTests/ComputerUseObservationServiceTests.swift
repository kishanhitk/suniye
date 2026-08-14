import XCTest
@testable import Suniye

final class ComputerUseObservationServiceTests: XCTestCase {
    func testObservationErrorsHaveUserReadableDescriptions() throws {
        XCTAssertFalse(
            try XCTUnwrap(
                ComputerUseObservationError.targetDidNotLaunch("Example").errorDescription
            ).isEmpty
        )
        XCTAssertFalse(
            try XCTUnwrap(ComputerUseObservationError.noWindow("Example").errorDescription).isEmpty
        )
    }

    func testObservationResolvesTargetAndCapturesAXAndScreenshotInBackground() async throws {
        let application = makeApplication(processIdentifier: 123)
        let screenshot = ComputerUseCapturedScreenshot(
            url: URL(fileURLWithPath: "/tmp/window.jpg"),
            pixelWidth: 800,
            pixelHeight: 600,
            coordinateScale: 0.5,
            windowFrame: CGRect(x: 10, y: 20, width: 400, height: 300)
        )
        let accessibility = StubAccessibilitySnapshotProvider(
            result: ComputerUseAXSnapshot(roots: [makeNode(role: "AXWindow", title: "Document")])
        )
        let screenshots = StubScreenshotCapturer(result: screenshot)
        let service = ComputerUseObservationService(
            windows: StubWindowDiscovery(result: [makeWindow(id: 44, ordinal: 2)]),
            accessibility: accessibility,
            screenshots: screenshots
        )

        let observation = try await service.observe(
            application: application,
            requestedIdentifier: "TextEdit",
            disableDiff: false
        )

        XCTAssertEqual(observation.state.app, "TextEdit")
        XCTAssertEqual(observation.state.screenshot, screenshot.url)
        XCTAssertEqual(observation.screenshot, screenshot)
        XCTAssertEqual(observation.state.text, "0: AXWindow \"Document\"")
        XCTAssertEqual(observation.revision.elements[0]?.rootIndex, 0)
        let accessibilityRequests = await accessibility.requests
        let screenshotWindowIDs = await screenshots.windowIDs
        XCTAssertEqual(
            accessibilityRequests,
            [StubAccessibilitySnapshotProvider.Request(pid: 123, ordinal: 2)]
        )
        XCTAssertEqual(screenshotWindowIDs, [44])
    }

    func testObservationFailsWhenLaunchHasNoProcess() async {
        let application = makeApplication(processIdentifier: nil)
        let service = makeService(windows: [])

        await assertObservationError(.targetDidNotLaunch("Example")) {
            try await service.observe(
                application: application,
                requestedIdentifier: "Example",
                disableDiff: false
            )
        }
    }

    func testObservationFailsWhenTargetHasNoWindow() async {
        let application = makeApplication(processIdentifier: 123)
        let service = makeService(windows: [])

        await assertObservationError(.noWindow("Example")) {
            try await service.observe(
                application: application,
                requestedIdentifier: "Example",
                disableDiff: false
            )
        }
    }

    private func makeService(windows: [ComputerUseWindow]) -> ComputerUseObservationService {
        ComputerUseObservationService(
            windows: StubWindowDiscovery(result: windows),
            accessibility: StubAccessibilitySnapshotProvider(
                result: ComputerUseAXSnapshot(roots: [])
            ),
            screenshots: StubScreenshotCapturer(result: nil)
        )
    }

    private func assertObservationError(
        _ expected: ComputerUseObservationError,
        operation: () async throws -> ComputerUseObservation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected observation error", file: file, line: line)
        } catch let error as ComputerUseObservationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func makeApplication(processIdentifier: Int32?) -> ComputerUseApplicationRecord {
        ComputerUseApplicationRecord(
            displayName: "Example",
            bundleIdentifier: "com.example.app",
            applicationURL: URL(fileURLWithPath: "/Applications/Example.app"),
            lastUsedDate: nil,
            useCount: nil,
            processIdentifier: processIdentifier,
            isFrontmost: false
        )
    }

    private func makeWindow(id: UInt32, ordinal: Int) -> ComputerUseWindow {
        ComputerUseWindow(
            id: id,
            ownerProcessIdentifier: 123,
            title: "Document",
            bounds: CGRect(x: 0, y: 0, width: 400, height: 300),
            layer: 0,
            isOnScreen: true,
            accessibilityOrdinal: ordinal,
            isFocused: false,
            isMain: false
        )
    }

    private func makeNode(role: String, title: String?) -> ComputerUseAXNode {
        ComputerUseAXNode(
            role: role,
            roleDescription: nil,
            subrole: nil,
            title: title,
            description: nil,
            help: nil,
            identifier: nil,
            value: nil,
            isEnabled: true,
            isValueSettable: false,
            isFocused: false,
            secondaryActions: [],
            children: []
        )
    }
}

private struct StubWindowDiscovery: ComputerUseWindowDiscovering {
    let result: [ComputerUseWindow]

    func orderedWindows(processIdentifier: Int32) async throws -> [ComputerUseWindow] {
        result
    }
}

private actor StubAccessibilitySnapshotProvider: ComputerUseAccessibilitySnapshotProviding {
    struct Request: Equatable {
        let pid: Int32
        let ordinal: Int
    }

    private(set) var requests: [Request] = []
    let result: ComputerUseAXSnapshot

    init(result: ComputerUseAXSnapshot) {
        self.result = result
    }

    func snapshot(processIdentifier: Int32, windowOrdinal: Int) async throws
        -> ComputerUseAXSnapshot
    {
        requests.append(.init(pid: processIdentifier, ordinal: windowOrdinal))
        return result
    }
}

private actor StubScreenshotCapturer: ComputerUseScreenshotCapturing {
    private(set) var windowIDs: [UInt32] = []
    let result: ComputerUseCapturedScreenshot?

    init(result: ComputerUseCapturedScreenshot?) {
        self.result = result
    }

    func capture(windowID: UInt32) async throws -> ComputerUseCapturedScreenshot? {
        windowIDs.append(windowID)
        return result
    }
}
