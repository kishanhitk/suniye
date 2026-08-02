import CoreGraphics
import Foundation

/// A Codable rectangle for Computer Use observations.
///
/// Computer Use data may cross an actor or process boundary later. Keep
/// CoreGraphics objects inside the platform adapters.
struct ComputerUseRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var isEmpty: Bool {
        width <= 0 || height <= 0
    }
}

struct ComputerUseApplication: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let bundleIdentifier: String
    let displayName: String
    let processIdentifier: Int32
    let isRunning: Bool
    let isActive: Bool
    let launchDate: Date?
}

struct ComputerUseWindow: Codable, Equatable, Identifiable, Sendable {
    let id: UInt32
    let title: String?
    let ownerProcessIdentifier: Int32
    let bounds: ComputerUseRect
    let layer: Int
    let isOnScreen: Bool
    let isKeyWindow: Bool
}

struct ComputerUseTarget: Codable, Equatable, Sendable {
    let application: ComputerUseApplication
    let window: ComputerUseWindow
}

struct ComputerUseAXElement: Codable, Equatable, Sendable {
    let index: Int
    let role: String?
    let subrole: String?
    let title: String?
    let description: String?
    let value: String?
    let isEnabled: Bool?
    let isFocused: Bool
    let isSelected: Bool
    let bounds: ComputerUseRect?
    let actions: [String]
    let childIndexes: [Int]
}

struct ComputerUseAXSnapshot: Codable, Equatable, Sendable {
    let text: String
    let elements: [ComputerUseAXElement]
    let wasTruncated: Bool
}

struct ComputerUseScreenshot: Codable, Equatable, Sendable {
    let data: Data
    let mimeType: String
    let width: Int
    let height: Int
}

struct ComputerUseObservation: Codable, Equatable, Sendable {
    let generation: UInt64
    let capturedAt: Date
    let target: ComputerUseTarget
    let accessibility: ComputerUseAXSnapshot
    let screenshot: ComputerUseScreenshot?
}

struct ComputerUseObservationConfiguration: Equatable, Sendable {
    var maxDepth: Int = 8
    var maxElements: Int = 500
    var maxTextLength: Int = 100_000
    var includeElementBounds: Bool = true
    var redactSensitiveValues: Bool = true

    static let `default` = ComputerUseObservationConfiguration()
}

enum ComputerUsePermissionState: String, Codable, Equatable, Sendable {
    case granted
    case notGranted
    case unavailable
}

struct ComputerUsePermissionSnapshot: Codable, Equatable, Sendable {
    let accessibility: ComputerUsePermissionState
    let screenRecording: ComputerUsePermissionState

    var canReadAccessibility: Bool {
        accessibility == .granted
    }

    var canCaptureScreen: Bool {
        screenRecording == .granted
    }

    var canObserveWithScreenshot: Bool {
        canReadAccessibility && canCaptureScreen
    }
}

enum ComputerUseObservationError: LocalizedError, Equatable, Sendable {
    case cancelled
    case applicationNotFound(String)
    case applicationNotRunning(String)
    case noWindow(String)
    case accessibilityNotTrusted
    case accessibilityWindowNotFound(String)
    case accessibilityReadFailed(String)
    case screenRecordingNotGranted
    case screenshotUnavailable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Computer Use observation was canceled."
        case let .applicationNotFound(identifier):
            return "The application was not found: \(identifier)."
        case let .applicationNotRunning(identifier):
            return "The application is not running: \(identifier)."
        case let .noWindow(identifier):
            return "The application has no visible window: \(identifier)."
        case .accessibilityNotTrusted:
            return "Accessibility permission is required to read this application."
        case let .accessibilityWindowNotFound(title):
            return "The Accessibility window was not found: \(title)."
        case let .accessibilityReadFailed(attribute):
            return "Accessibility did not return the required attribute: \(attribute)."
        case .screenRecordingNotGranted:
            return "Screen Recording permission is required to capture this window."
        case .screenshotUnavailable:
            return "The target window screenshot is not available."
        }
    }
}

/// A cancellation source that can be shared with synchronous macOS adapters.
///
/// The adapters check this token between native calls. They do not stop a
/// CoreGraphics or Accessibility call that is already in progress.
final class ComputerUseCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

protocol ComputerUseApplicationCatalog {
    func listApplications() -> [ComputerUseApplication]
    func application(withID identifier: String) -> ComputerUseApplication?
}

protocol ComputerUseWindowDiscovering {
    func listWindows(for application: ComputerUseApplication) -> [ComputerUseWindow]
}

protocol ComputerUseAccessibilityReading {
    func read(
        application: ComputerUseApplication,
        window: ComputerUseWindow,
        configuration: ComputerUseObservationConfiguration,
        shouldCancel: () -> Bool
    ) throws -> ComputerUseAXSnapshot
}

protocol ComputerUseScreenshotCapturing {
    func capture(window: ComputerUseWindow) throws -> ComputerUseScreenshot
}

protocol ComputerUsePermissionManaging {
    func snapshot() -> ComputerUsePermissionSnapshot
    @discardableResult
    func requestAccessibility() -> Bool
    @discardableResult
    func requestScreenRecording() -> Bool
}

protocol ComputerUseObservationServicing {
    func observe(
        applicationID: String,
        includeScreenshot: Bool,
        configuration: ComputerUseObservationConfiguration,
        cancellation: ComputerUseCancellationToken
    ) throws -> ComputerUseObservation
}
