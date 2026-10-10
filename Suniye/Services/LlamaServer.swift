import Darwin
import Foundation

struct LlamaServerEndpoint: Equatable {
    let baseURL: URL
    let apiKey: String
}

/// The helper binary and its model arguments. Every start adds the loopback
/// host, a free port, and a fresh API key.
struct LlamaServerLaunch: Equatable {
    let executableURL: URL
    let arguments: [String]
    /// Passed to the load and eviction callbacks.
    let modelName: String
}

enum LlamaServerError: Error, Equatable {
    case launchFailed
    /// `reason` is `server_exited_<status>`, plus the last stderr line when there is one.
    case exited(reason: String)
    case startupTimedOut
    /// `stop()`, or a start for another launch, ended this start first.
    case startupCanceled
}

/// One bundled `llama-server` child: started on demand for a launch, shared by
/// concurrent callers, replaced by a start for a different launch, and stopped
/// by `stop()` or an idle timeout.
actor LlamaServer {
    static let shutdownTimeoutSeconds = 2.0

    private struct Startup {
        let id: UUID
        let launch: LlamaServerLaunch
        let task: Task<LlamaServerEndpoint, Error>
    }

    private let healthSession: URLSession
    /// Fired (model name, cold-start load ms) once per real process start, from
    /// `start()`'s success path. Analytics-only; may be nil.
    private let onModelLoad: (@Sendable (String, Int) -> Void)?
    /// Fired (with the model name) when the idle timeout stops the server.
    /// Analytics-only; may be nil.
    private let onKeepAliveEvicted: (@Sendable (String) -> Void)?
    private var process: Process?
    private var launch: LlamaServerLaunch?
    private var endpoint: LlamaServerEndpoint?
    private var startup: Startup?
    private var idleShutdownTask: Task<Void, Never>?
    private var stoppingTask: Task<Void, Never>?

    init(
        healthSession: URLSession = .shared,
        onModelLoad: (@Sendable (String, Int) -> Void)? = nil,
        onKeepAliveEvicted: (@Sendable (String) -> Void)? = nil
    ) {
        self.healthSession = healthSession
        self.onModelLoad = onModelLoad
        self.onKeepAliveEvicted = onKeepAliveEvicted
    }

    /// The bundled helper, or the `SUNIYE_LLAMA_SERVER_PATH` override.
    static func locateExecutable(fileManager: FileManager = .default) -> URL? {
        let name = "llama-server"
        if let override = ProcessInfo.processInfo.environment["SUNIYE_LLAMA_SERVER_PATH"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let bundleCandidates = [
            Bundle.main.url(forAuxiliaryExecutable: name),
            Bundle.main.url(forResource: name, withExtension: nil),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM"),
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "LocalLLM/bin"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(name),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(name),
        ].compactMap { $0 }

        return bundleCandidates
            .lazy
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func arguments(for launch: LlamaServerLaunch, port: Int, apiKey: String) -> [String] {
        launch.arguments + [
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--api-key", apiKey,
            "--no-webui",
            "--log-disable",
        ]
    }

    func isWarm(for launch: LlamaServerLaunch) -> Bool {
        process?.isRunning == true && self.launch == launch && endpoint != nil
    }

    /// `idleTimeoutSeconds` of 0 or less keeps the server up until `stop()`.
    func endpoint(for launch: LlamaServerLaunch, startupTimeoutSeconds: Double, idleTimeoutSeconds: Double) async throws -> LlamaServerEndpoint {
        if isWarm(for: launch), let endpoint {
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        }

        if let startup, startup.launch == launch {
            let endpoint = try await startup.task.value
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        }

        await stop()
        // `stop()` suspends while an old process exits, and another caller can start
        // or finish a startup meanwhile. Start over so this caller joins or replaces
        // that startup instead of killing its process.
        if startup != nil || process != nil {
            return try await endpoint(
                for: launch,
                startupTimeoutSeconds: startupTimeoutSeconds,
                idleTimeoutSeconds: idleTimeoutSeconds
            )
        }

        let startupID = UUID()
        let startupTask = Task { [weak self] () throws -> LlamaServerEndpoint in
            guard let self else {
                throw LlamaServerError.startupCanceled
            }
            return try await self.start(
                launch: launch,
                startupID: startupID,
                startupTimeoutSeconds: startupTimeoutSeconds
            )
        }
        startup = Startup(id: startupID, launch: launch, task: startupTask)

        do {
            let endpoint = try await startupTask.value
            if startup?.id == startupID {
                startup = nil
            }
            scheduleIdleShutdown(after: idleTimeoutSeconds)
            return endpoint
        } catch {
            if startup?.id == startupID {
                startup = nil
            }
            throw error
        }
    }

    private func start(
        launch: LlamaServerLaunch,
        startupID: UUID,
        startupTimeoutSeconds: Double
    ) async throws -> LlamaServerEndpoint {
        try Task.checkCancellation()
        guard startup?.id == startupID else {
            throw LlamaServerError.startupCanceled
        }

        let loadStart = DispatchTime.now()
        let port = Self.findFreePort()
        let endpoint = LlamaServerEndpoint(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            apiKey: Self.makeAPIKey()
        )
        let process = Process()
        process.executableURL = launch.executableURL
        process.arguments = Self.arguments(for: launch, port: port, apiKey: endpoint.apiKey)
        process.standardOutput = Pipe()
        let standardError = Pipe()
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw LlamaServerError.launchFailed
        }
        LlamaServerChildren.insert(process)

        self.process = process
        self.launch = launch

        do {
            try await waitUntilHealthy(
                endpoint: endpoint,
                process: process,
                standardError: standardError,
                timeoutSeconds: startupTimeoutSeconds
            )
        } catch {
            await cleanUpFailedStartup(process, startupID: startupID)
            throw error
        }
        guard startup?.id == startupID,
              self.process === process,
              process.isRunning,
              self.launch == launch else {
            throw LlamaServerError.startupCanceled
        }
        self.endpoint = endpoint
        let loadMs = Int((DispatchTime.now().uptimeNanoseconds - loadStart.uptimeNanoseconds) / 1_000_000)
        onModelLoad?(launch.modelName, loadMs)
        return endpoint
    }

    private func cleanUpFailedStartup(_ processToStop: Process, startupID: UUID) async {
        guard startup?.id == startupID, process === processToStop else {
            return
        }

        startup = nil
        process = nil
        launch = nil
        endpoint = nil
        await Self.terminateAndWait(processToStop, timeoutSeconds: Self.shutdownTimeoutSeconds)
    }

    func scheduleIdleShutdown(after idleTimeoutSeconds: Double) {
        idleShutdownTask?.cancel()
        guard idleTimeoutSeconds > 0 else {
            return
        }
        idleShutdownTask = Task { [weak self] in
            let delayNanos = UInt64(idleTimeoutSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else {
                return
            }
            await self?.stopForIdleTimeout()
        }
    }

    private func waitUntilHealthy(
        endpoint: LlamaServerEndpoint,
        process: Process,
        standardError: Pipe,
        timeoutSeconds: Double
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try Task.checkCancellation()

            if !process.isRunning {
                throw LlamaServerError.exited(reason: Self.exitReason(
                    status: process.terminationStatus,
                    standardError: standardError
                ))
            }

            if await isHealthy(endpoint: endpoint) {
                return
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw LlamaServerError.startupTimedOut
    }

    private func isHealthy(endpoint: LlamaServerEndpoint) async -> Bool {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 1
        request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await healthSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return false
            }
            return 200 ..< 300 ~= http.statusCode
        } catch {
            return false
        }
    }

    private func stopForIdleTimeout() async {
        AppLogger.shared.log(.info, "llama server idle shutdown")
        let evictedModel = launch?.modelName // capture before stop() clears it
        await stop()
        if let evictedModel { onKeepAliveEvicted?(evictedModel) }
    }

    func stop() async {
        idleShutdownTask?.cancel()
        idleShutdownTask = nil

        let startupTaskToCancel = startup?.task
        startup = nil
        startupTaskToCancel?.cancel()

        if let stoppingTask {
            await stoppingTask.value
            self.stoppingTask = nil
        }

        let processToStop = process
        process = nil
        launch = nil
        endpoint = nil

        guard let processToStop else {
            return
        }

        let task = Task.detached(priority: .utility) {
            await Self.terminateAndWait(processToStop, timeoutSeconds: Self.shutdownTimeoutSeconds)
        }
        stoppingTask = task
        await task.value
        stoppingTask = nil
    }

    private static func makeAPIKey() -> String {
        "suniye-\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    /// Returns an OS-assigned free TCP port (bind to port 0, read it back, release) rather
    /// than a random guess. A random port can collide with an in-use or TIME_WAIT port and
    /// make the server fail to bind — a prime source of CI flakiness for the helper tests.
    private static func findFreePort() -> Int {
        let fallback = Int.random(in: 49_152 ... 65_535)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return fallback }
        defer { close(descriptor) }

        var reuse: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY
        address.sin_port = 0 // let the OS choose a free port

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return fallback }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else { return fallback }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }

    private static func terminateAndWait(_ process: Process, timeoutSeconds: Double) async {
        defer {
            LlamaServerChildren.remove(process)
        }
        guard process.isRunning else {
            return
        }

        process.terminate() // SIGTERM

        // Poll for exit rather than blocking in `waitUntilExit()`, which can hang
        // indefinitely when the child's output pipe isn't drained (its SIGKILL fallback
        // can't help because the blocking call never returns). Escalate to SIGKILL past
        // the grace period. This is always bounded, so it cannot hang the caller.
        if await waitForExit(process, timeoutSeconds: max(0, timeoutSeconds)) {
            return
        }
        Darwin.kill(process.processIdentifier, SIGKILL)
        _ = await waitForExit(process, timeoutSeconds: 2)
    }

    /// Waits (by polling the non-blocking `isRunning` flag) for the process to exit, up to
    /// `timeoutSeconds`. Returns `true` if it exited within the window.
    private static func waitForExit(_ process: Process, timeoutSeconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() >= deadline {
                return false
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private static func exitReason(status: Int32, standardError: Pipe) -> String {
        let data = standardError.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else {
            return "server_exited_\(status)"
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let detail = lines.last { !$0.isEmpty } ?? "stderr"
        return "server_exited_\(status)_\(String(detail.prefix(160)))"
    }
}

/// Every llama-server child this app has started and not yet stopped.
///
/// llama-server does not exit with its parent: after an app quit or crash it
/// keeps running, model loaded, re-parented to launchd. App quit stops the
/// tracked children; app launch stops the orphans of an earlier crash.
enum LlamaServerChildren {
    private static let lock = NSLock()
    private static var processes: [ObjectIdentifier: Process] = [:]

    static func insert(_ process: Process) {
        lock.withLock { processes[ObjectIdentifier(process)] = process }
    }

    static func remove(_ process: Process) {
        lock.withLock { processes[ObjectIdentifier(process)] = nil }
    }

    /// Sends SIGTERM to every running child without waiting: the app is about
    /// to exit, and llama-server finishes its shutdown on its own.
    static func terminateAll() {
        let tracked = lock.withLock { Array(processes.values) }
        for process in tracked where process.isRunning {
            process.terminate()
        }
    }

    /// Sends SIGTERM to every process that runs `executableURL` and whose parent
    /// is launchd, which is where an orphaned child of an earlier run ends up.
    /// Returns how many it signaled.
    @discardableResult
    static func terminateOrphans(of executableURL: URL) -> Int {
        // The kernel reports the canonical path (`/private/var/...`), which
        // `URL.resolvingSymlinksInPath()` would strip back to `/var/...`.
        guard let resolved = realpath(executableURL.path, nil) else {
            return 0
        }
        let target = String(cString: resolved)
        free(resolved)

        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else {
            return 0
        }
        // Room for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: capacity + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))

        var signaled = 0
        for pid in pids.prefix(max(0, count)) where pid > 1 {
            guard parentProcessID(of: pid) == 1, executablePath(of: pid) == target else {
                continue
            }
            if Darwin.kill(pid, SIGTERM) == 0 {
                signaled += 1
            }
        }
        return signaled
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN)) // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func parentProcessID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return pid_t(info.pbi_ppid)
    }
}
