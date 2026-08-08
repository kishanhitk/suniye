import AppKit
import CoreServices
import Foundation

struct SystemComputerUseApplicationInventory: ComputerUseApplicationInventoryProviding {
    func runningApplications() async -> [ComputerUseApplicationRecord] {
        await MainActor.run {
            let workspace = NSWorkspace.shared
            let frontmostProcessIdentifier = workspace.frontmostApplication?.processIdentifier
            return workspace.runningApplications.compactMap { application in
                guard !application.isTerminated,
                      let applicationURL = application.bundleURL else {
                    return nil
                }
                return ComputerUseApplicationRecord(
                    displayName: application.localizedName
                        ?? applicationURL.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: application.bundleIdentifier,
                    applicationURL: applicationURL,
                    lastUsedDate: nil,
                    useCount: nil,
                    processIdentifier: application.processIdentifier,
                    isFrontmost: application.processIdentifier == frontmostProcessIdentifier
                )
            }
        }
    }

    func recentApplications() async throws -> [ComputerUseApplicationRecord] {
        try await Task.detached(priority: .utility) {
            try SpotlightComputerUseApplicationQuery.snapshot()
        }.value
    }
}

struct SystemComputerUseApplicationLauncher: ComputerUseApplicationLaunching {
    func launchInBackground(_ application: ComputerUseApplicationRecord) async throws
        -> ComputerUseApplicationRecord
    {
        try await launch(application)
    }

    @MainActor
    private func launch(_ application: ComputerUseApplicationRecord) async throws
        -> ComputerUseApplicationRecord
    {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: application.applicationURL,
                configuration: configuration
            ) { runningApplication, error in
                guard let runningApplication,
                      let applicationURL = runningApplication.bundleURL else {
                    continuation.resume(
                        throwing: error
                            ?? ComputerUseApplicationCatalogError.launchFailed(
                                application.displayName
                            )
                    )
                    return
                }
                continuation.resume(
                    returning: ComputerUseApplicationRecord(
                        displayName: runningApplication.localizedName
                            ?? application.displayName,
                        bundleIdentifier: runningApplication.bundleIdentifier
                            ?? application.bundleIdentifier,
                        applicationURL: applicationURL,
                        lastUsedDate: application.lastUsedDate,
                        useCount: application.useCount,
                        processIdentifier: runningApplication.processIdentifier,
                        isFrontmost: runningApplication.isActive
                    )
                )
            }
        }
    }
}

private enum SpotlightComputerUseApplicationQuery {
    private static let query = """
    kMDItemContentType == "com.apple.application-bundle" && \
    kMDItemFSName == "*.app" && \
    kMDItemLastUsedDate_Ranking >= $time.today(-14)
    """

    private static let useCountAttribute = "kMDItemUseCount" as CFString

    static func snapshot() throws -> [ComputerUseApplicationRecord] {
        let attributes = [
            kMDItemCFBundleIdentifier as String,
            kMDItemDisplayName as String,
            kMDItemPath as String,
            kMDItemLastUsedDate as String,
            useCountAttribute as String,
        ] as CFArray
        guard let metadataQuery = MDQueryCreate(
            kCFAllocatorDefault,
            query as CFString,
            attributes,
            nil
        ) else {
            throw ComputerUseApplicationInventoryError.queryCreationFailed
        }
        defer {
            MDQueryStop(metadataQuery)
        }

        MDQuerySetSearchScope(metadataQuery, [kMDQueryScopeComputer as String] as CFArray, 0)
        guard MDQueryExecute(metadataQuery, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            throw ComputerUseApplicationInventoryError.queryExecutionFailed
        }

        return (0..<MDQueryGetResultCount(metadataQuery)).compactMap { index in
            guard let pointer = MDQueryGetResultAtIndex(metadataQuery, index) else {
                return nil
            }
            return application(from: unsafeBitCast(pointer, to: MDItem.self))
        }
    }

    private static func application(from item: MDItem) -> ComputerUseApplicationRecord? {
        guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else {
            return nil
        }
        let applicationURL = URL(fileURLWithPath: path)
        let bundle = Bundle(url: applicationURL)
        return ComputerUseApplicationRecord(
            displayName: displayName(item: item, bundle: bundle, url: applicationURL),
            bundleIdentifier: (MDItemCopyAttribute(
                item,
                kMDItemCFBundleIdentifier
            ) as? String) ?? bundle?.bundleIdentifier,
            applicationURL: applicationURL,
            lastUsedDate: MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date,
            useCount: (MDItemCopyAttribute(item, useCountAttribute) as? NSNumber)?.intValue,
            processIdentifier: nil,
            isFrontmost: false
        )
    }

    private static func displayName(item: MDItem, bundle: Bundle?, url: URL) -> String {
        (MDItemCopyAttribute(item, kMDItemDisplayName) as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
}

private enum ComputerUseApplicationInventoryError: LocalizedError {
    case queryCreationFailed
    case queryExecutionFailed

    var errorDescription: String? {
        switch self {
        case .queryCreationFailed:
            "Could not create the recent application query."
        case .queryExecutionFailed:
            "Could not query recent applications."
        }
    }
}
