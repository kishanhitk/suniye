import XCTest
@testable import Suniye

@MainActor
final class ComputerUseModelConfigurationTests: XCTestCase {
    func testCustomProviderBuildsTrimmedIndependentConfiguration() throws {
        let settings = ComputerUseModelSettings(
            provider: .custom,
            modelID: "  gpt-5.6-luna  ",
            customEndpointURLString: " https://example.com/v1/chat/completions "
        )

        let configuration = try XCTUnwrap(settings.configuration(apiKey: "  secret  "))

        XCTAssertEqual(
            configuration,
            ComputerUseRemoteModelConfiguration(
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!,
                modelID: "gpt-5.6-luna",
                apiKey: "secret"
            )
        )
    }

    func testProviderOwnsItsEndpointWhileCustomEndpointIsEditable() {
        XCTAssertEqual(
            ComputerUseModelSettings(provider: .openAI).endpointURLString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            ComputerUseModelSettings(provider: .openRouter).endpointURLString,
            "https://openrouter.ai/api/v1/chat/completions"
        )
        XCTAssertEqual(
            ComputerUseModelSettings(
                provider: .custom,
                customEndpointURLString: "https://localhost:8080/v1/chat/completions"
            ).endpointURLString,
            "https://localhost:8080/v1/chat/completions"
        )
    }

    func testSettingsStoreRoundTripsWithoutMagicFormatSettings() {
        let suite = "dev.suniye.tests.computerUse.model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ComputerUseModelSettingsStore(userDefaults: defaults, storageKey: "settings")
        let settings = ComputerUseModelSettings(
            provider: .custom,
            modelID: "desktop-model",
            customEndpointURLString: "https://computer.example/v1/chat/completions",
            timeoutSeconds: 90,
            maxTokens: 4_096
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testControllerSavesCredentialAndReconfiguresCoordinator() throws {
        let store = TestComputerUseModelSettingsStore(
            value: ComputerUseModelSettings(provider: .openAI, modelID: "computer-model")
        )
        let credentials = TestComputerUseCredentialStore()
        var configurations: [ComputerUseRemoteModelConfiguration?] = []
        let controller = ComputerUseModelSettingsController(
            settingsStore: store,
            credentialStore: credentials,
            connectionTester: StubComputerUseModelConnectionTester(),
            onConfigurationChange: { configurations.append($0) }
        )

        XCTAssertNil(controller.modelConfiguration)
        controller.saveAPIKey("  computer-secret  ")

        XCTAssertEqual(try credentials.getAPIKey(), "computer-secret")
        XCTAssertEqual(controller.modelConfiguration?.modelID, "computer-model")
        XCTAssertEqual(configurations.last??.apiKey, "computer-secret")

        controller.clearAPIKey()

        XCTAssertFalse(credentials.hasAPIKey())
        XCTAssertNil(controller.modelConfiguration)
        XCTAssertNil(configurations.last!)
    }

    func testConnectionTestUsesComputerUseConfiguration() async {
        let tester = StubComputerUseModelConnectionTester()
        let sharedCredentials = TestKeychainService(value: "run-key")
        let controller = ComputerUseModelSettingsController(
            settingsStore: TestComputerUseModelSettingsStore(
                value: ComputerUseModelSettings(provider: .openRouter, modelID: "run-model")
            ),
            credentialStore: TestComputerUseCredentialStore(),
            sharedOpenRouterCredentialStore: MagicFormatOpenRouterCredentialStore(
                keychainService: sharedCredentials
            ),
            connectionTester: tester
        )

        await controller.testConnection()

        let configurations = await tester.configurations()
        XCTAssertEqual(controller.connectionState, .connected)
        XCTAssertEqual(configurations.map(\.modelID), ["run-model"])
    }

    func testOpenRouterUsesSharedMagicFormatCredential() {
        let sharedCredentials = TestKeychainService(value: "  shared-key  ")
        let controller = ComputerUseModelSettingsController(
            settingsStore: TestComputerUseModelSettingsStore(
                value: ComputerUseModelSettings(provider: .openRouter, modelID: "run-model")
            ),
            credentialStore: TestComputerUseCredentialStore(),
            sharedOpenRouterCredentialStore: MagicFormatOpenRouterCredentialStore(
                keychainService: sharedCredentials
            )
        )

        XCTAssertEqual(controller.modelConfiguration?.apiKey, "shared-key")
        XCTAssertTrue(controller.hasAPIKey)
    }

    func testOpenRouterAlwaysUsesSharedCredentialInsteadOfDedicatedCredential() {
        let sharedCredentials = TestKeychainService(value: "shared-key")
        let controller = ComputerUseModelSettingsController(
            settingsStore: TestComputerUseModelSettingsStore(
                value: ComputerUseModelSettings(provider: .openRouter, modelID: "run-model")
            ),
            credentialStore: TestComputerUseCredentialStore(value: "computer-use-key"),
            sharedOpenRouterCredentialStore: MagicFormatOpenRouterCredentialStore(
                keychainService: sharedCredentials
            )
        )

        XCTAssertEqual(controller.modelConfiguration?.apiKey, "shared-key")
        XCTAssertTrue(controller.hasAPIKey)
    }

    func testSharedOpenRouterKeyIsNotUsedForOtherProviders() {
        let sharedCredentials = TestKeychainService(value: "shared-key")
        let controller = ComputerUseModelSettingsController(
            settingsStore: TestComputerUseModelSettingsStore(
                value: ComputerUseModelSettings(provider: .openAI, modelID: "run-model")
            ),
            credentialStore: TestComputerUseCredentialStore(),
            sharedOpenRouterCredentialStore: MagicFormatOpenRouterCredentialStore(
                keychainService: sharedCredentials
            )
        )

        XCTAssertNil(controller.modelConfiguration)
        XCTAssertFalse(controller.hasAPIKey)
    }

    func testMagicFormatChangesDoNotChangeComputerUseModel() {
        let computerUseStore = TestComputerUseModelSettingsStore(
            value: ComputerUseModelSettings(provider: .openAI, modelID: "computer-model")
        )
        let appState = makeTestAppState(
            computerUseModelSettingsStore: computerUseStore,
            computerUseCredentialStore: TestComputerUseCredentialStore(value: "computer-key")
        )

        XCTAssertEqual(appState.computerUseCoordinator.modelID, "computer-model")

        appState.llmSelectedModelPreset = .custom
        appState.llmCustomModelId = "magic-format-model"
        appState.llmEndpointURLString = "https://magic.example/v1/chat/completions"
        appState.saveLLMAPIKey("magic-key")

        XCTAssertEqual(appState.computerUseCoordinator.modelID, "computer-model")
        XCTAssertEqual(appState.computerUseModelSettings.settings.modelID, "computer-model")
    }

    func testSavingCredentialAfterLaunchConfiguresAppOwnedCoordinator() {
        let appState = makeTestAppState(
            computerUseModelSettingsStore: TestComputerUseModelSettingsStore(
                value: ComputerUseModelSettings(provider: .openAI, modelID: "computer-model")
            ),
            computerUseCredentialStore: TestComputerUseCredentialStore()
        )
        XCTAssertFalse(appState.computerUseCoordinator.isModelConfigured)

        appState.computerUseModelSettings.saveAPIKey("computer-key")

        XCTAssertTrue(appState.computerUseCoordinator.isModelConfigured)
        XCTAssertEqual(appState.computerUseCoordinator.modelID, "computer-model")
    }

    func testMagicFormatAndComputerUseShareOneOpenRouterCredential() throws {
        let sharedCredentials = TestKeychainService(value: nil)
        let appState = makeTestAppState(
            llmSettingsStore: TestLLMSettingsStore(),
            computerUseModelSettingsStore: TestComputerUseModelSettingsStore(
                value: ComputerUseModelSettings(provider: .openRouter, modelID: "computer-model")
            ),
            computerUseCredentialStore: TestComputerUseCredentialStore(),
            keychainService: sharedCredentials
        )
        XCTAssertFalse(appState.computerUseCoordinator.isModelConfigured)

        appState.saveLLMAPIKey("shared-openrouter-key")

        XCTAssertTrue(appState.computerUseCoordinator.isModelConfigured)
        XCTAssertTrue(appState.computerUseModelSettings.hasAPIKey)

        appState.clearLLMAPIKey()

        XCTAssertFalse(appState.computerUseCoordinator.isModelConfigured)
        XCTAssertFalse(appState.computerUseModelSettings.hasAPIKey)

        appState.computerUseModelSettings.saveAPIKey("saved-from-computer-use")

        XCTAssertEqual(try sharedCredentials.getLLMKey(), "saved-from-computer-use")
        XCTAssertTrue(appState.hasLLMAPIKey)
        XCTAssertTrue(appState.computerUseCoordinator.isModelConfigured)

        appState.computerUseModelSettings.clearAPIKey()

        XCTAssertNil(try sharedCredentials.getLLMKey())
        XCTAssertFalse(appState.hasLLMAPIKey)
        XCTAssertFalse(appState.computerUseCoordinator.isModelConfigured)
    }
}
