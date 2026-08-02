import AppKit
import ApplicationServices
import Foundation

enum ComputerUseWindowActivationPolicy {
    static func shouldUseAccessibilityRaise(
        targetProcessIdentifier: Int32,
        currentProcessIdentifier: Int32
    ) -> Bool {
        targetProcessIdentifier != currentProcessIdentifier
    }
}

struct SystemComputerUseWindowActivator: ComputerUseWindowActivating {
    private let runningApplicationProvider: (Int32) -> NSRunningApplication?

    init(
        runningApplicationProvider: @escaping (Int32) -> NSRunningApplication? = {
            NSRunningApplication(processIdentifier: $0)
        }
    ) {
        self.runningApplicationProvider = runningApplicationProvider
    }

    func activate(target: ComputerUseTarget) -> Bool {
        guard let application = runningApplicationProvider(target.application.processIdentifier),
              application.activate(options: [.activateAllWindows]) else {
            return false
        }

        // Raising our own window through AX re-enters AppKit's accessibility path and can
        // trap while AppKit is ordering the window. Activation already brings this app forward.
        guard ComputerUseWindowActivationPolicy.shouldUseAccessibilityRaise(
            targetProcessIdentifier: target.application.processIdentifier,
            currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        ) else {
            return true
        }

        let applicationElement = AXUIElementCreateApplication(target.application.processIdentifier)
        guard let windowElement = SystemComputerUseAccessibilityReader.resolveWindowElement(
            in: applicationElement,
            target: target.window,
            shouldCancel: { false }
        ) else {
            return false
        }

        return AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString) == .success
    }
}
