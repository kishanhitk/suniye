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
    private let applicationActivator: (NSRunningApplication) -> Bool
    private let windowRaiser: (ComputerUseTarget) -> Bool

    init(
        runningApplicationProvider: @escaping (Int32) -> NSRunningApplication? = {
            NSRunningApplication(processIdentifier: $0)
        },
        applicationActivator: @escaping (NSRunningApplication) -> Bool = {
            $0.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        },
        windowRaiser: @escaping (ComputerUseTarget) -> Bool = { target in
            let applicationElement = AXUIElementCreateApplication(
                target.application.processIdentifier
            )
            guard let windowElement = SystemComputerUseAccessibilityReader.resolveWindowElement(
                in: applicationElement,
                target: target.window,
                shouldCancel: { false }
            ) else {
                return false
            }
            return AXUIElementPerformAction(
                windowElement,
                kAXRaiseAction as CFString
            ) == .success
        }
    ) {
        self.runningApplicationProvider = runningApplicationProvider
        self.applicationActivator = applicationActivator
        self.windowRaiser = windowRaiser
    }

    func activate(target: ComputerUseTarget) -> Bool {
        guard let application = runningApplicationProvider(target.application.processIdentifier) else {
            return false
        }
        let applicationActivated = applicationActivator(application)

        // Raising our own window through AX re-enters AppKit's accessibility path and can
        // trap while AppKit is ordering the window. Activation already brings this app forward.
        guard ComputerUseWindowActivationPolicy.shouldUseAccessibilityRaise(
            targetProcessIdentifier: target.application.processIdentifier,
            currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        ) else {
            return applicationActivated
        }

        return windowRaiser(target) || applicationActivated
    }
}
