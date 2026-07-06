import Foundation

/// Coarse, non-identifying hardware/OS profile. The full profile ships on
/// `app_launch` (→ the D1 install registry); `batchProps` also rides every
/// batch envelope so the ingest Worker can stamp device dims onto each event's
/// AE row, making every metric hardware-sliceable.
///
/// The app assembles this — the package never reads `sysctl`/`ProcessInfo`
/// itself, so it carries no platform knowledge. Rare-combo bucketing (to avoid
/// singling out unusual machines) is the app's responsibility before it builds
/// this value.
public struct DeviceProfile: Sendable, Equatable {
    public let osVersion: SafeLabel      // major.minor, e.g. "15.5"
    public let arch: SafeLabel           // "arm64" / "x86_64"
    public let macModel: SafeLabel       // e.g. "mac15-3" (bucketed if rare)
    public let chip: SafeLabel           // e.g. "apple-m3-pro"
    public let ramGB: Int                // bucketed tier (8/16/24/32/36/48/64/96/128)
    public let cpuCores: Int             // total physical
    public let perfCores: Int?           // P-cores (nil on Intel)
    public let effCores: Int?            // E-cores (nil on Intel)
    public let language: SafeLabel       // language code only, e.g. "en"

    public init(
        osVersion: SafeLabel,
        arch: SafeLabel,
        macModel: SafeLabel,
        chip: SafeLabel,
        ramGB: Int,
        cpuCores: Int,
        perfCores: Int?,
        effCores: Int?,
        language: SafeLabel
    ) {
        self.osVersion = osVersion
        self.arch = arch
        self.macModel = macModel
        self.chip = chip
        self.ramGB = ramGB
        self.cpuCores = cpuCores
        self.perfCores = perfCores
        self.effCores = effCores
        self.language = language
    }

    var props: [String: AnalyticsValue] {
        var out: [String: AnalyticsValue] = [
            "os_version": .label(osVersion),
            "arch": .label(arch),
            "mac_model": .label(macModel),
            "chip": .label(chip),
            "ram_gb": .int(ramGB),
            "cpu_cores": .int(cpuCores),
            "language": .label(language)
        ]
        if let perfCores { out["perf_cores"] = .int(perfCores) }
        if let effCores { out["eff_cores"] = .int(effCores) }
        return out
    }

    /// Device props for the batch envelope, stamped onto EVERY event's AE row so
    /// any metric can be sliced by hardware. Excludes `language` — the ingest
    /// merge lets event props win, but on events with no language of their own
    /// the device UI language would FILL the spoken-language slot (blob7) and
    /// corrupt language slicing; the full `props` still ship on `app_launch`.
    var batchProps: [String: AnalyticsValue] {
        var out = props
        out.removeValue(forKey: "language")
        return out
    }
}

/// Snapshot of user-facing settings/toggles, sent on `app_launch`. Enums and
/// bools/counts only — never device names, keycodes, or free text.
public struct SettingsSnapshot: Sendable, Equatable {
    public var values: [String: AnalyticsValue]

    public init(_ values: [String: AnalyticsValue] = [:]) {
        self.values = values
    }

    /// Namespaced under `setting_*` so settings never collide with device keys.
    var props: [String: AnalyticsValue] {
        var out: [String: AnalyticsValue] = [:]
        for (key, value) in values { out["setting_\(key)"] = value }
        return out
    }
}
