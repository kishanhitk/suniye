import Darwin
import Foundation
import SuniyeAnalytics

/// Reads a coarse, non-identifying hardware/OS profile via sysctl. All values are
/// hardware classes shared by many machines; RAM is bucketed to standard tiers.
enum DeviceProfileReader {
    static func read() -> DeviceProfile {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceProfile(
            osVersion: SafeLabel("\(os.majorVersion).\(os.minorVersion)"),
            arch: SafeLabel(ProcessInfo.suniyeArchitecture),
            macModel: SafeLabel(sysctlString("hw.model") ?? "unknown"),
            chip: SafeLabel(sysctlString("machdep.cpu.brand_string") ?? "unknown"),
            ramGB: bucketRAM(sysctlUInt64("hw.memsize")),
            cpuCores: Int(sysctlUInt32("hw.physicalcpu") ?? 0),
            perfCores: sysctlUInt32("hw.perflevel0.physicalcpu").map(Int.init),
            effCores: sysctlUInt32("hw.perflevel1.physicalcpu").map(Int.init),
            language: SafeLabel(Locale.current.language.languageCode?.identifier ?? "en")
        )
    }

    /// Rounds physical memory to the nearest common configuration tier.
    static func bucketRAM(_ bytes: UInt64?) -> Int {
        guard let bytes, bytes > 0 else { return 0 }
        let gb = Double(bytes) / 1_073_741_824.0
        let tiers = [8, 16, 24, 32, 36, 48, 64, 96, 128, 192, 256, 512]
        return tiers.min(by: { abs(Double($0) - gb) < abs(Double($1) - gb) }) ?? Int(gb.rounded())
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func sysctlUInt32(_ name: String) -> UInt32? {
        var value: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

/// Maps a frontmost app bundle id to a coarse category. The raw bundle id is
/// never sent (it would be a usage fingerprint) — only the category.
enum TargetCategoryMapper {
    static func category(for bundleID: String?) -> TargetCategory {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return .other }
        func has(_ needles: String...) -> Bool { needles.contains { id.contains($0) } }

        if has("mail", "outlook", "spark", "airmail", "sparrow", "canary") { return .email }
        // Terminal before IDE: "com.googlecode.iterm2" contains "code".
        if has("terminal", "iterm", "warp", "ghostty", "alacritty", "kitty", "hyper") { return .terminal }
        if has("xcode", "vscode", "vscodium", "jetbrains", "intellij", "pycharm", "sublimetext", "nova", "zed", "cursor") { return .ide }
        if has("safari", "chrome", "firefox", "arc", "edge", "brave", "vivaldi", "orion") { return .browser }
        if has("slack", "discord", "messages", "telegram", "whatsapp", "signal", "teams", "zoom") { return .chat }
        if has("notes", "notion", "obsidian", "bear", "craft", "logseq", "roam") { return .notes }
        if has("word", "pages", "keynote", "powerpoint", "excel", "numbers", "docs") { return .office }
        if has("textedit", "editor", "ia.writer", "iawriter", "ulysses") { return .editor }
        return .other
    }
}

/// Converts app-side dictation enums to the analytics vocabulary. Uses
/// description-based matching so it stays robust if the app enums gain cases.
enum AnalyticsMapping {
    static func source(_ source: FloatingIndicatorState.Source) -> SuniyeAnalytics.DictationSource {
        switch source {
        case .hotkey, .editHotkey: return .hotkey
        case .manual: return .manual
        }
    }

    static func audioOutcome(_ outcome: AudioCaptureOutcome) -> AudioOutcome {
        let d = String(describing: outcome).lowercased()
        if d.contains("complete") { return .complete }
        if d.contains("short") { return .tooShort }
        if d.contains("silent") { return .silent }
        if d.contains("clip") { return .clipped }
        if d.contains("overflow") { return .bufferOverflow }
        if d.contains("invalid") { return .invalidSamples }
        if d.contains("interrupt") { return .interrupted }
        return .unknown
    }

    static func interruptionReason(_ reason: AudioCaptureInterruption) -> AudioInterruptionReason {
        let d = String(describing: reason).lowercased()
        if d.contains("max") || d.contains("duration") { return .maximumDurationReached }
        if d.contains("sleep") { return .systemSleep }
        if d.contains("mute") { return .inputMuted }
        if d.contains("device") { return .deviceChanged }
        if d.contains("route") { return .routeLost }
        return .other
    }

    static func cleanupProvider(describing provider: String) -> CleanupProvider {
        let d = provider.lowercased()
        if d.contains("apple") { return .appleFoundationModels }
        if d.contains("localgemma") || d.contains("local") || d.contains("gemma") { return .localGemma }
        if d.contains("openai") || d.contains("compatible") || d.contains("generic") { return .openAICompatible }
        if d.contains("automatic") { return .automatic }
        return .unknown
    }
}

/// Monotonic per-dictation latency marks. Dictation is serialized by the phase
/// machine, so a single instance on AppState is safe. Uses `DispatchTime`
/// (uptime), immune to wall-clock changes.
struct DictationTiming {
    var recordStart: DispatchTime?
    var captureStarted: DispatchTime?
    var stopped: DispatchTime?
    var asrStart: DispatchTime?
    var asrEnd: DispatchTime?
    var llmStart: DispatchTime?
    var llmEnd: DispatchTime?
    var inserted: DispatchTime?

    func latency() -> DictationMetrics.Latency {
        DictationMetrics.Latency(
            triggerToCaptureMs: delta(recordStart, captureStarted),
            asrProcessingMs: delta(asrStart, asrEnd),
            llmTotalMs: delta(llmStart, llmEnd),
            endToEndMs: delta(stopped, inserted)
        )
    }

    private func delta(_ start: DispatchTime?, _ end: DispatchTime?) -> Int? {
        guard let start, let end, end.uptimeNanoseconds >= start.uptimeNanoseconds else { return nil }
        return Int((end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}
