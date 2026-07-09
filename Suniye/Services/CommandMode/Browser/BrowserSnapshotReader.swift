import Foundation

/// Perceives a web page through the extension: sends `snapshot`, renders the
/// actionable elements as `e0/e1…` rows in the SAME text shape as `AXTreeReader`
/// (so the brain's "reference an id" model is identical on web and native), and
/// remembers each ref's label/role for the risky-action confirmation.
@MainActor
final class BrowserSnapshotReader: ScreenReading {
    private let transport: BrowserTransport
    private var refLabels: [String: String] = [:]
    private var refRoles: [String: String] = [:]

    init(transport: BrowserTransport) { self.transport = transport }

    func readScreen() async -> String {
        refLabels = [:]
        refRoles = [:]
        do {
            let response = try await transport.send(tool: "snapshot", args: [:])
            guard response.ok,
                  let rowsJSON = response.result["rows"],
                  let data = rowsJSON.data(using: .utf8),
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return "The browser page could not be read."
            }
            var lines: [String] = []
            for row in rows {
                guard let ref = row["ref"] as? String else { continue }
                let role = row["role"] as? String ?? ""
                let label = row["label"] as? String ?? ""
                refLabels[ref] = label
                refRoles[ref] = role
                lines.append(Self.rowLine(ref: ref, role: role, label: label))
            }
            return Self.summary(url: response.result["url"] ?? "", title: response.result["title"] ?? "", rows: lines)
        } catch {
            return "The browser page could not be read (extension disconnected)."
        }
    }

    func label(forRef ref: String) -> String? { refLabels[ref] }
    func role(forRef ref: String) -> String? { refRoles[ref] }

    nonisolated static func rowLine(ref: String, role: String, label: String) -> String {
        label.isEmpty ? "\(ref): \(role)" : "\(ref): \(role) \"\(label)\""
    }

    /// Mirrors `AXTreeReader.summary`'s block so the observation reads identically.
    nonisolated static func summary(url: String, title: String, rows: [String]) -> String {
        var lines = ["Frontmost app: Google Chrome" + (title.isEmpty ? "" : " — \(title)")]
        if !url.isEmpty { lines.append("URL: \(url)") }
        if rows.isEmpty {
            lines.append("No actionable elements found.")
        } else {
            lines.append("Actionable elements — reference an id with click/focus:")
            lines.append(contentsOf: rows)
        }
        return lines.joined(separator: "\n")
    }
}
