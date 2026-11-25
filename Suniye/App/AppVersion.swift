import Foundation

struct SemVer: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(parts.count) else {
            return nil
        }
        guard let major = Int(parts[0]), major >= 0 else {
            return nil
        }
        let minor = parts.count >= 2 ? Int(parts[1]) : 0
        let patch = parts.count == 3 ? Int(parts[2]) : 0
        guard let minor, let patch, minor >= 0, patch >= 0 else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

struct AppVersion {
    let marketing: SemVer
    let build: Int?
    let channel: UpdateChannel

    init(marketing: SemVer, build: Int?, channel: UpdateChannel = .stable) {
        self.marketing = marketing
        self.build = build
        self.channel = channel
    }

    /// v0.0.83 (2988), or v0.0.84 (2991) Tip.
    var displayString: String {
        "v\(number)\(buildSuffix)\(channelSuffix)"
    }

    /// The version without the build number: v0.0.83, or v0.0.84 Tip.
    var shortDisplayString: String {
        "v\(number)\(channelSuffix)"
    }

    /// Version 0.0.83 (2988), for a tooltip.
    var helpString: String {
        "Version \(number)\(buildSuffix)\(channelSuffix)"
    }

    private var number: String {
        "\(marketing.major).\(marketing.minor).\(marketing.patch)"
    }

    private var buildSuffix: String {
        build.map { " (\($0))" } ?? ""
    }

    private var channelSuffix: String {
        channel == .tip ? " Tip" : ""
    }

    static func fromBundle(_ bundle: Bundle = .main) -> AppVersion? {
        guard
            let marketingRaw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let marketing = SemVer(rawValue: marketingRaw)
        else {
            return nil
        }

        let buildRaw = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let build = buildRaw.flatMap(Int.init)
        let channelRaw = bundle.object(forInfoDictionaryKey: "SuniyeBuildChannel") as? String
        let channel = channelRaw.flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        return AppVersion(marketing: marketing, build: build, channel: channel)
    }
}

struct AppIdentity: Equatable {
    let displayName: String
    let isPreview: Bool

    static let fallbackDisplayName = "Suniye"

    static var current: AppIdentity {
        fromBundle()
    }

    static func fromBundle(_ bundle: Bundle = .main) -> AppIdentity {
        let displayName = (
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? fallbackDisplayName
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        return AppIdentity(
            displayName: displayName.isEmpty ? fallbackDisplayName : displayName,
            isPreview: bundleIdentifier == "dev.suniye.app.preview" || bundleIdentifier.hasSuffix(".preview")
        )
    }
}
