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

    var displayString: String {
        let version = "\(marketing.major).\(marketing.minor).\(marketing.patch)"
        if let build {
            return "v\(version) (\(build))"
        }
        return "v\(version)"
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
        return AppVersion(marketing: marketing, build: build)
    }
}
