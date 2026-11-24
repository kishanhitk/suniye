import AppKit
import AVFoundation
import XCTest
@testable import Suniye

/// The app as a user runs it, on throwaway storage. Only the outside world is
/// stubbed: the microphone, the hotkey taps, the speaker, the focused app
/// (accessibility and key events), the network, the Keychain, Sparkle, the
/// on-device Apple model and the permission prompts.
@MainActor
final class FlowApp {
    enum Speech {
        /// The scripted engine in `stubEngine`, for flows that are not about recognition.
        case stub
        /// The real router, speech detector and Parakeet v3, read from the installed model.
        case parakeet
    }

    struct SetupError: LocalizedError {
        let errorDescription: String?
    }

    static let issueReportEndpoint = URL(string: "https://reports.suniye.test/v1/reports")!

    let root: URL
    let defaults: UserDefaults
    let microphone = StubAudioCaptureService()
    let hotkeys = StubHotkeyService()
    let focusedApp = FocusedApp()
    let apiKeyItem = MemorySecretItem()
    let updates = StubAppUpdateController()
    let analytics = SpyAnalytics()
    let stubEngine = StubTranscriptionService()
    let network = URLSession(configuration: StubURLProtocol.sessionConfiguration())

    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var frontmostBundleID: String?
    var accessibilityTrusted = true
    private(set) var accessibilityPromptCount = 0
    var micStatus: AVAuthorizationStatus = .authorized
    var micRequest: () async -> Bool = { true }

    private(set) var appState: AppState!
    private let appSupport: URL
    private let speech: Speech

    init(
        _ testCase: XCTestCase,
        speech: Speech = .stub,
        general: GeneralSettings = GeneralSettings(onboardingProgress: .finished),
        llm: LLMSettings = LLMSettings()
    ) throws {
        let suiteName = "suniye-flow-\(UUID().uuidString)"
        root = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        self.speech = speech
        testCase.addTeardownBlock { [root] in
            UserDefaults().removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        try installParakeet(linkingTheRealModel: speech == .parakeet)
        GeneralSettingsStore(userDefaults: defaults).save(general)
        LLMSettingsStore(userDefaults: defaults).save(llm)
        focusedApp.accessibilityTrusted = { [unowned self] in accessibilityTrusted }
    }

    /// Starts the app the way a launch does and waits until it can dictate.
    func launch(file: StaticString = #filePath, line: UInt = #line) async {
        let engine: TranscriptionServiceProtocol = speech == .parakeet ? RoutingTranscriptionService() : stubEngine
        let llmRoot = appSupport.appendingPathComponent("llm", isDirectory: true)
        appState = AppState(
            modelManager: ModelManager(applicationSupportDirectory: appSupport, urlSessionConfiguration: StubURLProtocol.sessionConfiguration()),
            transcriptionService: engine,
            audioCaptureService: microphone,
            textInsertionService: focusedApp.insertionService,
            editModeSelectionProvider: focusedApp.selectionService,
            hotkeyService: hotkeys,
            soundFeedbackService: SilentSpeaker(),
            llmPostProcessor: OpenRouterPostProcessor(session: network),
            appleMagicFormatPostProcessor: AppleFoundationModelsPostProcessor(client: UnavailableAppleModel()),
            localLLMModelManager: LocalLLMModelManager(rootDirectoryProvider: { llmRoot }),
            llmSettingsStore: LLMSettingsStore(userDefaults: defaults),
            magicFormatPromptFileStore: MagicFormatPromptFileStore(promptsDirectoryURL: root.appendingPathComponent("prompts", isDirectory: true)),
            generalSettingsStore: GeneralSettingsStore(userDefaults: defaults),
            historyStore: HistoryStore(userDefaults: defaults),
            statsStore: DictationStatsStore(fileURL: root.appendingPathComponent("stats.json")),
            keychainService: KeychainService(item: apiKeyItem),
            chatGPTCredentialStore: KeychainChatGPTCredentialStore(item: MemorySecretItem()),
            appUpdateController: updates,
            launchAtLoginService: StubLaunchAtLoginService(),
            issueReportUploadService: IssueReportUploadService(session: network, endpointURL: Self.issueReportEndpoint),
            analytics: analytics,
            learningToastPresenter: HiddenWindows(),
            nowProvider: { [unowned self] in now },
            frontmostAppBundleIDProvider: { [unowned self] in frontmostBundleID },
            fileOpener: { _ in true },
            accessibilityOnboarding: HiddenWindows(),
            micAuthorizationStatusProvider: { [unowned self] in micStatus },
            micAccessRequester: { [unowned self] in await micRequest() },
            accessibilityTrustProvider: { [unowned self] in accessibilityTrusted },
            accessibilityTrustPrompter: { [unowned self] in
                accessibilityPromptCount += 1
                return accessibilityTrusted
            },
            systemGlobeKeyActionProvider: { .doNothing },
            availableDiskCapacityProvider: { 100_000_000_000 },
            issueReportDiagnosticsDestinationPicker: { [root] name in root.appendingPathComponent(name) },
            meetingCoordinator: makeTestMeetingCoordinator(engine: engine, root: root, defaults: defaults)
        )
        await waitUntil(timeout: 30, file: file, line: line) { self.appState.phase == .ready }
    }

    /// Holds the dictation shortcut while the microphone hears `samples`, then releases it.
    func dictate(_ samples: [Float], sampleRate: Int = 48_000, file: StaticString = #filePath, line: UInt = #line) async {
        microphone.stopCaptureResult = CapturedAudio(samples: samples, sampleRate: sampleRate)
        await pressShortcut(file: file, line: line)
        await releaseShortcut(file: file, line: line)
    }

    /// Presses the dictation shortcut well after any earlier press, so it never reads as a double-tap.
    func pressShortcut(file: StaticString = #filePath, line: UInt = #line) async {
        now += 5
        hotkeys.onHotkeyDown?()
        await waitUntil(file: file, line: line) { self.appState.phase == .recording }
    }

    /// Releases the shortcut one second after the press: a hold, not a tap.
    func releaseShortcut(file: StaticString = #filePath, line: UInt = #line) async {
        now += 1
        hotkeys.onHotkeyUp?()
        await waitUntil(timeout: 30, file: file, line: line) { self.appState.phase == .ready }
    }

    /// Dictates with the scripted engine, which hears `words`.
    func dictate(saying words: String, file: StaticString = #filePath, line: UInt = #line) async {
        stubEngine.transcribeResult = .success(words)
        await pressShortcut(file: file, line: line)
        await releaseShortcut(file: file, line: line)
    }

    private func installParakeet(linkingTheRealModel: Bool) throws {
        let entry = ASRModelCatalog.entry(for: .parakeetV3)
        let directory = Self.modelDirectory(entry, in: appSupport)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard linkingTheRealModel else {
            for path in entry.manifest.requiredRelativePaths {
                FileManager.default.createFile(atPath: directory.appendingPathComponent(path).path, contents: Data())
            }
            return
        }
        let userAppSupport = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let installed = Self.modelDirectory(entry, in: userAppSupport)
        for path in entry.manifest.requiredRelativePaths {
            let source = installed.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw SetupError(errorDescription: "Parakeet v3 is not installed. Run ./scripts/setup_model.sh.")
            }
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(path), withDestinationURL: source)
        }
    }

    private static func modelDirectory(_ entry: ASRModelCatalogEntry, in appSupport: URL) -> URL {
        appSupport
            .appendingPathComponent(AppSupportDirectory.name, isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(entry.directoryName, isDirectory: true)
    }
}

/// The app that has keyboard focus, as accessibility and key events see it.
@MainActor
final class FocusedApp {
    enum Focus {
        /// An editable text field that accessibility can read and write.
        case textField
        /// A control that is not text, for example a button.
        case notText
        /// A browser that keeps its accessibility tree off and answers no focus query.
        case coldBrowser
    }

    var focus = Focus.textField
    private(set) var text = ""
    /// The text selected in the field, which Edit Mode reads.
    var selection: String?
    /// What a paste typed into a field that accessibility cannot see.
    private(set) var blindPastes: [String] = []
    private(set) var returnCount = 0
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.suniye.flow-tests.\(UUID().uuidString)"))
    let insertionService = TextInsertionService()
    private(set) var selectionService: EditModeService!
    var accessibilityTrusted: () -> Bool = { true }

    private static let pasteKey: CGKeyCode = 9
    private static let returnKey: CGKeyCode = 36
    private let element = AXUIElementCreateSystemWide()

    init() {
        pasteboard.clearContents()
        let service = insertionService
        service.pasteboardProvider = { [pasteboard] in pasteboard }
        service.focusedElementRetryIntervalNanoseconds = 0
        service.clipboardRestoreDelay = 0
        service.pasteKeyCodeProvider = { Self.pasteKey }
        service.frontmostAppPIDProvider = { 4242 }
        service.manualAccessibilitySetter = { _ in }
        service.focusedElementLookupProvider = { [unowned self] in
            guard accessibilityTrusted() else { return .notTextInput }
            switch focus {
            case .textField: return .found(element)
            case .notText: return .notTextInput
            case .coldBrowser: return .unavailable
            }
        }
        service.focusedTextSnapshotProvider = { [unowned self] _ in
            (value: text, selectedText: selection, selectedRange: NSRange(location: (text as NSString).length, length: 0))
        }
        service.selectedTextSetter = { [unowned self] _, typed in
            type(typed)
            return true
        }
        service.keyPoster = { [unowned self] key, flags in
            try post(key, flags)
        }
        selectionService = EditModeService(
            accessibilityTrustProvider: { [unowned self] in accessibilityTrusted() },
            focusedElementProvider: { [unowned self] in focus == .textField ? element : nil },
            selectedTextReader: { [unowned self] _ in selection },
            pasteboardProvider: { [pasteboard] in pasteboard },
            keyPoster: { [unowned self] key, flags in try post(key, flags) }
        )
    }

    func setFieldText(_ value: String, selected: Bool) {
        text = value
        selection = selected ? value : nil
    }

    func setClipboard(_ value: String) {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    var clipboard: String? {
        pasteboard.string(forType: .string)
    }

    private func type(_ typed: String) {
        if let selection, let range = text.range(of: selection, options: .backwards) {
            text.replaceSubrange(range, with: typed)
            self.selection = nil
        } else {
            text += typed
        }
    }

    private func post(_ key: CGKeyCode, _ flags: CGEventFlags) throws {
        switch (key, flags.contains(.maskCommand)) {
        case (Self.pasteKey, true):
            let pasted = pasteboard.string(forType: .string) ?? ""
            if focus == .textField {
                type(pasted)
            } else {
                blindPastes.append(pasted)
            }
        case (Self.returnKey, false):
            returnCount += 1
        default:
            XCTFail("unexpected key \(key) with flags \(flags)")
        }
    }
}

/// A Mac without Apple Intelligence, so Automatic never picks the on-device model.
struct UnavailableAppleModel: AppleFoundationModelsClient {
    var availability: AppleFoundationModelsAvailability { .deviceNotEligible }

    func generate(instructions: String, prompt: String) async throws -> String {
        XCTFail("Apple Intelligence is not available in flow tests")
        return ""
    }
}

/// What the real engine hears: words from the system voice, or silence.
enum SpokenAudio {
    static func sentence(_ text: String, sampleRate: Int = 48_000) async throws -> [Float] {
        let samples = await SpeechTestAudio.synthesizeSpeech(text, sampleRate: Double(sampleRate))
        guard samples.count > sampleRate / 2 else {
            throw FlowApp.SetupError(errorDescription: "The system voice made no audio for \"\(text)\".")
        }
        return silence(seconds: 0.5, sampleRate: sampleRate) + samples + silence(seconds: 0.5, sampleRate: sampleRate)
    }

    static func silence(seconds: Double, sampleRate: Int = 48_000) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(sampleRate)))
    }
}
