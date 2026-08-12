import XCTest
@testable import Suniye

final class ComputerUseApplicationCatalogTests: XCTestCase {
    func testListAppsMergesRunningAndRecentMetadataWithoutInventingIdentifiers() async throws {
        let usedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let inventory = StubComputerUseApplicationInventory(
            running: [
                record(
                    name: "Calculator",
                    bundleIdentifier: "com.apple.calculator",
                    path: "/System/Applications/Calculator.app",
                    processIdentifier: 101,
                    isFrontmost: false
                ),
                record(
                    name: "TextEdit",
                    bundleIdentifier: "com.apple.TextEdit",
                    path: "/System/Applications/TextEdit.app",
                    processIdentifier: 102,
                    isFrontmost: true
                ),
            ],
            recent: [
                record(
                    name: "Calculator",
                    bundleIdentifier: "com.apple.calculator",
                    path: "/System/Applications/Calculator.app",
                    lastUsedDate: usedAt,
                    useCount: 12
                ),
                record(
                    name: "Preview",
                    bundleIdentifier: "com.apple.Preview",
                    path: "/System/Applications/Preview.app",
                    lastUsedDate: usedAt,
                    useCount: 3
                ),
                record(
                    name: "No Identifier",
                    bundleIdentifier: nil,
                    path: "/Applications/No Identifier.app",
                    lastUsedDate: usedAt,
                    useCount: 1
                ),
            ]
        )
        let catalog = ComputerUseApplicationCatalog(
            inventory: inventory,
            launcher: StubComputerUseApplicationLauncher()
        )

        let apps = try await catalog.listApps()

        XCTAssertEqual(
            apps,
            [
                ComputerUseApplication(
                    id: "com.apple.calculator",
                    displayName: "Calculator",
                    lastUsedDate: usedAt,
                    useCount: 12,
                    isRunning: true
                ),
                ComputerUseApplication(
                    id: "com.apple.TextEdit",
                    displayName: "TextEdit",
                    lastUsedDate: nil,
                    useCount: nil,
                    isRunning: true
                ),
                ComputerUseApplication(
                    id: "com.apple.Preview",
                    displayName: "Preview",
                    lastUsedDate: usedAt,
                    useCount: 3,
                    isRunning: false
                ),
                ComputerUseApplication(
                    id: "No Identifier",
                    displayName: "No Identifier",
                    lastUsedDate: usedAt,
                    useCount: 1,
                    isRunning: false
                ),
            ]
        )
    }

    func testCatalogExcludesOnlyExplicitBundleIdentifiers() async throws {
        let inventory = StubComputerUseApplicationInventory(
            running: [
                record(
                    name: "Suniye",
                    bundleIdentifier: "dev.suniye.app",
                    path: "/Applications/Suniye.app",
                    processIdentifier: 100,
                    isFrontmost: true
                ),
                record(
                    name: "Calculator",
                    bundleIdentifier: "com.apple.calculator",
                    path: "/System/Applications/Calculator.app",
                    processIdentifier: 101,
                    isFrontmost: false
                ),
            ],
            recent: []
        )
        let catalog = ComputerUseApplicationCatalog(
            inventory: inventory,
            launcher: StubComputerUseApplicationLauncher(),
            excludedBundleIdentifiers: ["dev.suniye.app"]
        )

        let apps = try await catalog.listApps()

        XCTAssertEqual(apps.map(\.id), ["com.apple.calculator"])
    }

    func testDuplicateRecentRecordsKeepFirstIdentityAndFillMissingMetadata() async throws {
        let usedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let catalog = ComputerUseApplicationCatalog(
            inventory: StubComputerUseApplicationInventory(
                running: [],
                recent: [
                    record(
                        name: "Example",
                        bundleIdentifier: nil,
                        path: "/Applications/Example.app"
                    ),
                    record(
                        name: "Renamed Example",
                        bundleIdentifier: "com.example.app",
                        path: "/Applications/Example.app",
                        lastUsedDate: usedAt,
                        useCount: 4
                    ),
                ]
            ),
            launcher: StubComputerUseApplicationLauncher()
        )

        let applications = try await catalog.listApps()

        XCTAssertEqual(
            applications,
            [
                ComputerUseApplication(
                    id: "com.example.app",
                    displayName: "Example",
                    lastUsedDate: usedAt,
                    useCount: 4,
                    isRunning: false
                ),
            ]
        )
    }

    func testResolutionAcceptsOnlyExactNamePathOrBundleIdentifier() async throws {
        let calculator = record(
            name: "Calculator",
            bundleIdentifier: "com.apple.calculator",
            path: "/System/Applications/Calculator.app",
            processIdentifier: 101,
            isFrontmost: false
        )
        let catalog = ComputerUseApplicationCatalog(
            inventory: StubComputerUseApplicationInventory(running: [calculator], recent: []),
            launcher: StubComputerUseApplicationLauncher()
        )

        let byName = try await catalog.resolve("calculator")
        let byBundleIdentifier = try await catalog.resolve("com.apple.calculator")
        let byPath = try await catalog.resolve("/System/Applications/Calculator.app")

        XCTAssertEqual(byName, calculator)
        XCTAssertEqual(byBundleIdentifier, calculator)
        XCTAssertEqual(byPath, calculator)

        await assertCatalogError(.notFound("calc")) {
            try await catalog.resolve("calc")
        }
        await assertCatalogError(.notFound("bluetooth")) {
            try await catalog.resolve("bluetooth")
        }
    }

    func testBundleResolutionPrefersTheSingleRunningCopy() async throws {
        let running = record(
            name: "Example Beta",
            bundleIdentifier: "com.example.app",
            path: "/Applications/Example Beta.app",
            processIdentifier: 222,
            isFrontmost: false
        )
        let installed = record(
            name: "Example",
            bundleIdentifier: "com.example.app",
            path: "/Applications/Example.app"
        )
        let catalog = ComputerUseApplicationCatalog(
            inventory: StubComputerUseApplicationInventory(
                running: [running],
                recent: [installed]
            ),
            launcher: StubComputerUseApplicationLauncher()
        )

        let resolved = try await catalog.resolve("com.example.app")

        XCTAssertEqual(resolved, running)
    }

    func testDuplicateNonrunningBundleIdentifierIsReportedAsAmbiguous() async {
        let catalog = ComputerUseApplicationCatalog(
            inventory: StubComputerUseApplicationInventory(
                running: [],
                recent: [
                    record(
                        name: "Example",
                        bundleIdentifier: "com.example.app",
                        path: "/Applications/Example.app"
                    ),
                    record(
                        name: "Example Beta",
                        bundleIdentifier: "com.example.app",
                        path: "/Applications/Example Beta.app"
                    ),
                ]
            ),
            launcher: StubComputerUseApplicationLauncher()
        )

        await assertCatalogError(
            .ambiguous(
                identifier: "com.example.app",
                applicationPaths: [
                    "/Applications/Example.app",
                    "/Applications/Example Beta.app",
                ]
            )
        ) {
            try await catalog.resolve("com.example.app")
        }
    }

    func testResolveOrLaunchUsesBackgroundLauncherForNonrunningApp() async throws {
        let installed = record(
            name: "Calculator",
            bundleIdentifier: "com.apple.calculator",
            path: "/System/Applications/Calculator.app"
        )
        let launched = record(
            name: "Calculator",
            bundleIdentifier: "com.apple.calculator",
            path: "/System/Applications/Calculator.app",
            processIdentifier: 444,
            isFrontmost: false
        )
        let launcher = StubComputerUseApplicationLauncher(result: launched)
        let catalog = ComputerUseApplicationCatalog(
            inventory: StubComputerUseApplicationInventory(running: [], recent: [installed]),
            launcher: launcher
        )

        let result = try await catalog.resolveOrLaunch("Calculator")

        XCTAssertEqual(result, launched)
        let launchedPaths = await launcher.launchedPaths
        XCTAssertEqual(launchedPaths, ["/System/Applications/Calculator.app"])
    }

    func testReopenUsesBackgroundLauncherForRunningApp() async throws {
        let running = record(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            path: "/Applications/Google Chrome.app",
            processIdentifier: 444,
            isFrontmost: false
        )
        let reopened = record(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            path: "/Applications/Google Chrome.app",
            processIdentifier: 444,
            isFrontmost: false
        )
        let launcher = StubComputerUseApplicationLauncher(result: reopened)
        let catalog = ComputerUseApplicationCatalog(
            inventory: StubComputerUseApplicationInventory(running: [running], recent: []),
            launcher: launcher
        )

        let result = try await catalog.reopen(running)

        XCTAssertEqual(result, reopened)
        let launchedPaths = await launcher.launchedPaths
        XCTAssertEqual(launchedPaths, ["/Applications/Google Chrome.app"])
    }

    private func assertCatalogError(
        _ expected: ComputerUseApplicationCatalogError,
        operation: () async throws -> ComputerUseApplicationRecord,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected catalog error", file: file, line: line)
        } catch let error as ComputerUseApplicationCatalogError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func record(
        name: String,
        bundleIdentifier: String?,
        path: String,
        lastUsedDate: Date? = nil,
        useCount: Int? = nil,
        processIdentifier: Int32? = nil,
        isFrontmost: Bool = false
    ) -> ComputerUseApplicationRecord {
        ComputerUseApplicationRecord(
            displayName: name,
            bundleIdentifier: bundleIdentifier,
            applicationURL: URL(fileURLWithPath: path),
            lastUsedDate: lastUsedDate,
            useCount: useCount,
            processIdentifier: processIdentifier,
            isFrontmost: isFrontmost
        )
    }
}

private struct StubComputerUseApplicationInventory: ComputerUseApplicationInventoryProviding {
    let running: [ComputerUseApplicationRecord]
    let recent: [ComputerUseApplicationRecord]

    func runningApplications() async -> [ComputerUseApplicationRecord] {
        running
    }

    func recentApplications() async throws -> [ComputerUseApplicationRecord] {
        recent
    }
}

private actor StubComputerUseApplicationLauncher: ComputerUseApplicationLaunching {
    private(set) var launchedPaths: [String] = []
    private let result: ComputerUseApplicationRecord?

    init(result: ComputerUseApplicationRecord? = nil) {
        self.result = result
    }

    func launchInBackground(_ application: ComputerUseApplicationRecord) async throws
        -> ComputerUseApplicationRecord
    {
        launchedPaths.append(application.applicationURL.path)
        guard let result else {
            throw ComputerUseApplicationCatalogError.launchFailed(application.displayName)
        }
        return result
    }
}
