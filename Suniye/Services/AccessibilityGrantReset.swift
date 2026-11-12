import Foundation

/// Removes this app's own entry from the Accessibility list with `tccutil`.
/// After a signing change macOS keeps the old entry switched on, but the entry
/// no longer matches the app. Only a new grant records the current signature.
struct AccessibilityGrantReset {
    var bundleIdentifier: String? = Bundle.main.bundleIdentifier
    var executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")

    /// True when `tccutil` accepted the reset (exit 0). An app without an
    /// entry also exits 0.
    func run() async -> Bool {
        // `tccutil reset Accessibility` without a bundle id resets every app.
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            AppLogger.shared.log(.warning, "accessibility repair: no bundle identifier, reset skipped")
            return false
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["reset", "Accessibility", bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        let status: Int32
        do {
            status = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            AppLogger.shared.log(.warning, "accessibility repair: could not run tccutil: \(error.localizedDescription)")
            return false
        }

        guard status == 0 else {
            let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogger.shared.log(.warning, "accessibility repair: tccutil exited \(status): \(stderr)")
            return false
        }
        AppLogger.shared.log(.info, "accessibility repair: tccutil reset \(bundleIdentifier)")
        return true
    }
}
