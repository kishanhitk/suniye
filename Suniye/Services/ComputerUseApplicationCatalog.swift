import Foundation

struct ComputerUseApplicationRecord: Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String?
    let applicationURL: URL
    let lastUsedDate: Date?
    let useCount: Int?
    let processIdentifier: Int32?
    let isFrontmost: Bool

    var isRunning: Bool {
        processIdentifier != nil
    }

    /// Storage identity for observation bookkeeping. Distinct from
    /// `publicApplication.id`, which prefers the display name for
    /// model-visible listings.
    var identityKey: String {
        bundleIdentifier ?? applicationURL.standardizedFileURL.path
    }

    var publicApplication: ComputerUseApplication {
        ComputerUseApplication(
            id: bundleIdentifier ?? displayName,
            displayName: displayName,
            lastUsedDate: lastUsedDate,
            useCount: useCount,
            isRunning: isRunning
        )
    }
}

enum ComputerUseApplicationCatalogError: LocalizedError, Equatable, Sendable {
    case notFound(String)
    case ambiguous(identifier: String, applicationPaths: [String])
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .notFound(identifier):
            "No application matches \(identifier)."
        case let .ambiguous(identifier, applicationPaths):
            "More than one application matches \(identifier): \(applicationPaths.joined(separator: ", "))."
        case let .launchFailed(name):
            "Could not launch \(name)."
        }
    }
}

protocol ComputerUseApplicationInventoryProviding: Sendable {
    func runningApplications() async -> [ComputerUseApplicationRecord]
    func recentApplications() async throws -> [ComputerUseApplicationRecord]
}

protocol ComputerUseApplicationLaunching: Sendable {
    func launchInBackground(_ application: ComputerUseApplicationRecord) async throws
        -> ComputerUseApplicationRecord
}

protocol ComputerUseApplicationCatalogProviding: Sendable {
    func listApps() async throws -> [ComputerUseApplication]
    /// Lookup without side effects. Action paths use this: acting must never
    /// change application lifecycle.
    func resolve(_ identifier: String) async throws -> ComputerUseApplicationRecord
    func resolveOrLaunch(_ identifier: String) async throws -> ComputerUseApplicationRecord
    func reopen(_ application: ComputerUseApplicationRecord) async throws
        -> ComputerUseApplicationRecord
}

actor ComputerUseApplicationCatalog: ComputerUseApplicationCatalogProviding {
    private let inventory: ComputerUseApplicationInventoryProviding
    private let launcher: ComputerUseApplicationLaunching
    private let excludedBundleIdentifiers: Set<String>

    init(
        inventory: ComputerUseApplicationInventoryProviding = SystemComputerUseApplicationInventory(),
        launcher: ComputerUseApplicationLaunching = SystemComputerUseApplicationLauncher(),
        excludedBundleIdentifiers: Set<String> = Set(
            [Bundle.main.bundleIdentifier].compactMap { $0 }
        )
    ) {
        self.inventory = inventory
        self.launcher = launcher
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
    }

    func listApps() async throws -> [ComputerUseApplication] {
        try await applicationRecords().map(\.publicApplication)
    }

    func resolve(_ identifier: String) async throws -> ComputerUseApplicationRecord {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let applications = try await applicationRecords()

        if let pathMatch = applications.first(where: {
            $0.applicationURL.standardizedFileURL.path == normalizedIdentifier
        }) {
            return pathMatch
        }

        let nameMatches = applications.filter {
            $0.displayName.compare(normalizedIdentifier, options: .caseInsensitive) == .orderedSame
        }
        if !nameMatches.isEmpty {
            return try selectUnambiguous(
                nameMatches,
                identifier: normalizedIdentifier
            )
        }

        let bundleMatches = applications.filter {
            $0.bundleIdentifier?.compare(normalizedIdentifier, options: .caseInsensitive)
                == .orderedSame
        }
        guard !bundleMatches.isEmpty else {
            throw ComputerUseApplicationCatalogError.notFound(normalizedIdentifier)
        }
        return try selectUnambiguous(
            bundleMatches,
            identifier: normalizedIdentifier
        )
    }

    func resolveOrLaunch(_ identifier: String) async throws -> ComputerUseApplicationRecord {
        let application = try await resolve(identifier)
        guard !application.isRunning else {
            return application
        }
        return try await launcher.launchInBackground(application)
    }

    func reopen(_ application: ComputerUseApplicationRecord) async throws
        -> ComputerUseApplicationRecord
    {
        try await launcher.launchInBackground(application)
    }

    private func applicationRecords() async throws -> [ComputerUseApplicationRecord] {
        async let running = inventory.runningApplications()
        async let recent = inventory.recentApplications()
        return merge(running: await running, recent: try await recent)
    }

    private func merge(
        running: [ComputerUseApplicationRecord],
        recent: [ComputerUseApplicationRecord]
    ) -> [ComputerUseApplicationRecord] {
        var records: [ComputerUseApplicationRecord] = []
        var indexesByPath: [String: Int] = [:]

        for application in running + recent {
            guard !isExcluded(application) else {
                continue
            }
            let path = application.applicationURL.standardizedFileURL.path
            if let index = indexesByPath[path] {
                records[index] = merge(records[index], application)
            } else {
                indexesByPath[path] = records.count
                records.append(application)
            }
        }
        return records
    }

    private func merge(
        _ existing: ComputerUseApplicationRecord,
        _ incoming: ComputerUseApplicationRecord
    ) -> ComputerUseApplicationRecord {
        let primary = [existing, incoming].first(where: \.isRunning) ?? existing
        return ComputerUseApplicationRecord(
            displayName: primary.displayName,
            bundleIdentifier: primary.bundleIdentifier
                ?? existing.bundleIdentifier
                ?? incoming.bundleIdentifier,
            applicationURL: primary.applicationURL,
            lastUsedDate: existing.lastUsedDate ?? incoming.lastUsedDate,
            useCount: existing.useCount ?? incoming.useCount,
            processIdentifier: primary.processIdentifier,
            isFrontmost: primary.isFrontmost
        )
    }

    private func isExcluded(_ application: ComputerUseApplicationRecord) -> Bool {
        application.bundleIdentifier.map(excludedBundleIdentifiers.contains) ?? false
    }

    private func selectUnambiguous(
        _ applications: [ComputerUseApplicationRecord],
        identifier: String
    ) throws -> ComputerUseApplicationRecord {
        if applications.count == 1, let application = applications.first {
            return application
        }
        let running = applications.filter(\.isRunning)
        if running.count == 1, let application = running.first {
            return application
        }
        throw ComputerUseApplicationCatalogError.ambiguous(
            identifier: identifier,
            applicationPaths: applications.map(\.applicationURL.path)
        )
    }
}
