import AppKit
import ApplicationServices

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
