import Foundation
import JavaScriptCore

/// Outcome of running one model-authored `node_repl` script.
struct ComputerUseScriptResult: Equatable, Sendable {
    /// Concatenated `nodeRepl.write` / `console.log` output, in emission order.
    let output: String
    /// The error message when the script threw or timed out; nil on success.
    let error: String?
}

/// Runs model-authored JavaScript for code-mode Computer Use. The single
/// capability exposed to the script is `sky.*`, bridged to the native tool
/// backend; a bare `JSContext` has no filesystem, network, or process access,
/// so the script is sandboxed by construction.
///
/// Each call wraps the source in an async IIFE, so top-level `await` works
/// without AST rewriting. Top-level bindings do not persist between calls (they
/// are IIFE-local) — a deliberate divergence from the reference REPL, since
/// Computer Use re-derives element indexes from the latest observation each
/// turn. Each call gets a fresh `JSContext` on its own serial queue.
///
/// Timeout bounds two failure modes differently. A native call or promise that
/// never resolves leaves the queue idle; the off-queue watchdog resumes with a
/// timeout error and the runtime keeps working. A synchronous runaway
/// (`while(true){}`) blocks its queue; the watchdog still resumes the caller,
/// but that queue's thread stays busy until the process exits. Interrupting
/// running JavaScript in-process needs private API; killing it needs a
/// subprocess. Neither is built here — a hung native call is the realistic case
/// and it is fully recovered; a pure-CPU runaway from a broken model is not.
final class ComputerUseScriptRuntime: @unchecked Sendable {
    /// Executes one decoded `sky.*` call. Side effects (activity, analytics,
    /// audit, screenshot collection) belong to the caller; the runtime only
    /// shapes the result back into JavaScript.
    typealias Perform = @Sendable (ComputerUseToolCall) async -> Result<ComputerUseToolResult, Error>

    private let perform: Perform
    /// Fires timeouts off the JS queue so a blocked queue cannot delay them.
    private let watchdog = DispatchQueue(label: "dev.suniye.computeruse.script.watchdog")

    init(perform: @escaping Perform) {
        self.perform = perform
    }

    func run(script: String, timeout: Duration = .seconds(30)) async -> ComputerUseScriptResult {
        let execution = Execution(perform: perform, watchdog: watchdog)
        return await execution.run(script: script, timeout: timeout)
    }
}

/// One isolated script execution: its own context, queue, and output buffer.
/// All `JSContext` access is confined to `queue`; results from `perform` run
/// off-queue and are re-dispatched onto `queue` to resolve their JS promise.
private final class Execution: @unchecked Sendable {
    private let perform: ComputerUseScriptRuntime.Perform
    private let watchdog: DispatchQueue
    private let queue = DispatchQueue(label: "dev.suniye.computeruse.script.exec", qos: .userInitiated)
    private let context = JSContext()!
    private var output = ""
    private var settled = false

    init(perform: @escaping ComputerUseScriptRuntime.Perform, watchdog: DispatchQueue) {
        self.perform = perform
        self.watchdog = watchdog
    }

    func run(script: String, timeout: Duration) async -> ComputerUseScriptResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                installGlobals()
                start(script: script, timeout: timeout, continuation: continuation)
            }
        }
    }

    // MARK: Run lifecycle

    private func start(
        script: String,
        timeout: Duration,
        continuation: CheckedContinuation<ComputerUseScriptResult, Never>
    ) {
        // `finish` always runs on `queue` for the completion path; the watchdog
        // hops onto `queue` too, so `settled` needs no extra lock.
        let finish: (String?) -> Void = { [self] error in
            guard !settled else { return }
            settled = true
            continuation.resume(returning: ComputerUseScriptResult(output: output, error: error))
        }

        let done: @convention(block) () -> Void = { finish(nil) }
        let fail: @convention(block) (JSValue) -> Void = { finish(Self.describe(error: $0)) }
        context.setObject(done, forKeyedSubscript: "__scriptDone" as NSString)
        context.setObject(fail, forKeyedSubscript: "__scriptFail" as NSString)

        let seconds = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18
        watchdog.asyncAfter(deadline: .now() + seconds) { [self] in
            queue.async {
                finish("Script timed out after \(Self.format(seconds: seconds)) seconds without finishing.")
            }
        }

        let wrapped = "(async () => {\n\(script)\n})().then(__scriptDone, __scriptFail);"
        context.evaluateScript(wrapped)
    }

    // MARK: Global injection

    private func installGlobals() {
        context.exceptionHandler = { _, _ in } // Script errors surface via __scriptFail.

        let write: @convention(block) (JSValue) -> Void = { [weak self] value in
            self?.output += value.toString() ?? ""
        }
        let writeLine: @convention(block) (JSValue) -> Void = { [weak self] value in
            self?.output += (value.toString() ?? "") + "\n"
        }
        let nodeRepl = JSValue(newObjectIn: context)!
        nodeRepl.setObject(write, forKeyedSubscript: "write" as NSString)
        context.setObject(nodeRepl, forKeyedSubscript: "nodeRepl" as NSString)

        let console = JSValue(newObjectIn: context)!
        for method in ["log", "info", "warn", "error", "debug"] {
            console.setObject(writeLine, forKeyedSubscript: method as NSString)
        }
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        let sky = JSValue(newObjectIn: context)!
        for tool in ComputerUseToolName.allCases where tool != .nodeRepl {
            sky.setObject(bridge(for: tool), forKeyedSubscript: tool.rawValue as NSString)
        }
        context.setObject(sky, forKeyedSubscript: "sky" as NSString)
    }

    /// One `sky.<tool>` method: decode the JS argument object, run the native
    /// tool, and resolve/reject the returned promise. Decode and execution
    /// failures reject so the script can `catch` them.
    private func bridge(for tool: ComputerUseToolName) -> JSValue {
        let block: @convention(block) (JSValue?) -> JSValue = { [weak self] argument in
            guard let self else {
                return JSValue(undefinedIn: nil)
            }
            return self.makePromise { resolve, reject in
                let call: ComputerUseToolCall
                do {
                    call = try ComputerUseModelToolCallDecoder.decode(
                        name: tool.rawValue,
                        arguments: Self.argumentsJSON(from: argument)
                    )
                } catch {
                    reject(Self.localized(error))
                    return
                }
                Task {
                    let result = await self.perform(call)
                    self.queue.async {
                        guard !self.settled else {
                            return // Run already settled (timeout); drop the late resolution.
                        }
                        switch result {
                        case let .success(value):
                            resolve(self.javaScriptValue(for: value))
                        case let .failure(error):
                            reject(Self.localized(error))
                        }
                    }
                }
            }
        }
        return JSValue(object: block, in: context)
    }

    /// Builds a JS Promise whose resolve/reject are handed to `executor`, which
    /// may call them synchronously or later (from `queue`).
    private func makePromise(
        _ executor: @escaping (@escaping (JSValue) -> Void, @escaping (String) -> Void) -> Void
    ) -> JSValue {
        var resolveFn: JSValue?
        var rejectFn: JSValue?
        let capture: @convention(block) (JSValue, JSValue) -> Void = { resolve, reject in
            resolveFn = resolve
            rejectFn = reject
        }
        let promiseCtor = context.objectForKeyedSubscript("Promise")!
        let promise = promiseCtor.construct(withArguments: [JSValue(object: capture, in: context)!])!
        executor(
            { value in resolveFn?.call(withArguments: [value]) },
            { [context] message in
                rejectFn?.call(withArguments: [JSValue(newErrorFromMessage: message, in: context)!])
            }
        )
        return promise
    }

    /// Shapes a tool result into the JS value the sky API returns: an app-state
    /// object, an app array, or undefined for a completed action.
    private func javaScriptValue(for result: ComputerUseToolResult) -> JSValue {
        switch result {
        case let .appState(state):
            var object: [String: Any] = ["app": state.app, "text": state.text]
            object["screenshot"] = state.screenshot.map { ["url": $0.absoluteString] } ?? NSNull()
            return JSValue(object: object, in: context)
        case let .applications(applications):
            let array = applications.map { application -> [String: Any] in
                var object: [String: Any] = ["id": application.id]
                object["displayName"] = application.displayName ?? NSNull()
                object["isRunning"] = application.isRunning ?? NSNull()
                object["isFrontmost"] = application.isFrontmost ?? NSNull()
                return object
            }
            return JSValue(object: array, in: context)
        case .actionCompleted:
            return JSValue(undefinedIn: context)
        }
    }

    // MARK: Helpers

    private static func argumentsJSON(from argument: JSValue?) -> String {
        guard let argument, !argument.isUndefined, !argument.isNull,
              let object = argument.toObject(),
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func format(seconds: Double) -> String {
        String(format: "%g", seconds)
    }

    private static func localized(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func describe(error value: JSValue) -> String {
        if value.isObject, let message = value.objectForKeyedSubscript("message"),
           !message.isUndefined, let text = message.toString(), !text.isEmpty {
            return text
        }
        return value.toString() ?? "Script error."
    }
}
