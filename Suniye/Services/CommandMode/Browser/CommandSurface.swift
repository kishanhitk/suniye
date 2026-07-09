import ApplicationServices
import Foundation

enum CommandSurfaceKind { case native, browser }

/// Perception + action seam the core tools (`read_screen`/`click`/`focus`/
/// `type_text`) route through. `readScreen()` picks the live surface each turn;
/// the action verbs act on whichever surface is active — one `e0/e1` id space.
@MainActor
protocol CommandActing: ScreenReading {
    func click(id: String) async -> ToolResult
    func focus(id: String) async -> ToolResult
    func typeText(_ text: String) async -> ToolResult
    var activeKind: CommandSurfaceKind { get }
}

/// Routes between the native accessibility tree and a connected browser page.
/// Reads the LIVE frontmost app every `readScreen()`, so a mid-run `open_app` that
/// brings a browser forward flips subsequent turns to the page automatically.
@MainActor
final class RoutingCommandSurface: CommandActing {
    private let native: AXTreeReader
    private let browser: BrowserSnapshotReader?
    private let transport: BrowserTransport?
    private let nativeTyper: TextTyping
    private let frontmostBundleID: () -> String?
    private let isBrowser: (String?) -> Bool
    /// Returns true to allow a risky web action. Presented to the user.
    private let confirmRisky: @MainActor (String) async -> Bool

    private(set) var activeKind: CommandSurfaceKind = .native

    init(native: AXTreeReader,
         browser: BrowserSnapshotReader?,
         transport: BrowserTransport?,
         nativeTyper: TextTyping,
         frontmostBundleID: @escaping () -> String?,
         isBrowser: @escaping (String?) -> Bool,
         confirmRisky: @escaping (String) async -> Bool) {
        self.native = native
        self.browser = browser
        self.transport = transport
        self.nativeTyper = nativeTyper
        self.frontmostBundleID = frontmostBundleID
        self.isBrowser = isBrowser
        self.confirmRisky = confirmRisky
    }

    func readScreen() async -> String {
        let connected = (await transport?.isConnected) ?? false
        if isBrowser(frontmostBundleID()), connected, let browser {
            activeKind = .browser
            return await browser.readScreen()
        }
        activeKind = .native
        return await native.readScreen()
    }

    func click(id: String) async -> ToolResult {
        switch activeKind {
        case .native:
            guard let element = native.element(forId: id) else { return noElement(id) }
            let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
            return ToolResult(output: status == .success ? "clicked \(id)" : "click \(id) failed (ax \(status.rawValue))", isTerminal: false)
        case .browser:
            // Risky web action → confirm (unless it's a plain navigation link).
            if isConsequential(id) {
                let label = browser?.label(forRef: id) ?? id
                if await confirmRisky("click “\(label)”") == false {
                    return ToolResult(output: "cancelled — the user declined that action", isTerminal: false)
                }
            }
            return await forward("click", ["ref": id], fallback: "clicked \(id)")
        }
    }

    func focus(id: String) async -> ToolResult {
        switch activeKind {
        case .native:
            guard let element = native.element(forId: id) else { return noElement(id) }
            let status = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return ToolResult(output: status == .success ? "focused \(id)" : "focus \(id) failed", isTerminal: false)
        case .browser:
            return await forward("focus", ["ref": id], fallback: "focused \(id)")
        }
    }

    func typeText(_ text: String) async -> ToolResult {
        switch activeKind {
        case .native:
            nativeTyper.type(text)
            return ToolResult(output: "typed \(text.count) chars", isTerminal: false)
        case .browser:
            return await forward("type", ["text": text], fallback: "typed \(text.count) chars")
        }
    }

    private func noElement(_ id: String) -> ToolResult {
        ToolResult(output: "no element \(id) — call read_screen first", isTerminal: false)
    }

    /// A consequential page action (submit/purchase/delete/auth) worth confirming.
    /// Plain link navigation is not — confirming every click would be unusable.
    private func isConsequential(_ ref: String) -> Bool {
        let label = (browser?.label(forRef: ref) ?? "").lowercased()
        let keywords = [
            "buy", "add to cart", "add to bag", "checkout", "check out", "place order",
            "pay", "purchase", "confirm", "submit", "delete", "remove",
            "sign in", "log in", "order now", "continue",
        ]
        return keywords.contains { label.contains($0) }
    }

    private func forward(_ tool: String, _ args: [String: String], fallback: String) async -> ToolResult {
        guard let transport else { return ToolResult(output: "browser not connected", isTerminal: false) }
        do {
            let response = try await transport.send(tool: tool, args: args)
            if response.ok { return ToolResult(output: response.result["output"] ?? fallback, isTerminal: false) }
            return ToolResult(output: response.errorMessage ?? "the web action failed", isTerminal: false)
        } catch {
            return ToolResult(output: "browser not connected", isTerminal: false)
        }
    }
}
