import XCTest
import CoreAudio
@testable import Suniye

@MainActor
final class AppStateHistoryStatsTests: XCTestCase {
    func testAddHistoryEntryUpdatesStatsAndCapsTo500() {
        let historyStore = InMemoryHistoryStore()
        let statsStore = InMemoryStatsStore()
        let appState = makeAppState(historyStore: historyStore, statsStore: statsStore)

        for index in 0..<501 {
            appState.addHistoryEntry(
                text: "entry \(index)",
                durationSeconds: 1,
                wordCount: 2,
                submitted: false
            )
        }

        XCTAssertEqual(appState.historyEntries.count, 500)
        XCTAssertEqual(appState.sessionCount, 500)
        XCTAssertEqual(appState.wordsTranscribed, 1000)
        XCTAssertEqual(appState.totalDictationSeconds, 500)
        XCTAssertEqual(historyStore.savedEntries.count, 500)
        XCTAssertEqual(statsStore.savedSnapshot?.sessionCount, 500)
    }

    func testDeleteAndClearKeepStatsInSync() {
        let historyStore = InMemoryHistoryStore()
        let statsStore = InMemoryStatsStore()
        let appState = makeAppState(historyStore: historyStore, statsStore: statsStore)

        appState.addHistoryEntry(text: "one", durationSeconds: 2, wordCount: 4, submitted: false)
        appState.addHistoryEntry(text: "two", durationSeconds: 3, wordCount: 5, submitted: true)

        let firstId = appState.historyEntries[0].id
        appState.deleteHistoryEntry(id: firstId)

        XCTAssertEqual(appState.historyEntries.count, 1)
        XCTAssertEqual(appState.sessionCount, 1)
        XCTAssertEqual(appState.wordsTranscribed, 4)
        XCTAssertEqual(appState.totalDictationSeconds, 2)

        appState.clearHistory()

        XCTAssertEqual(appState.historyEntries.count, 0)
        XCTAssertEqual(appState.sessionCount, 0)
        XCTAssertEqual(appState.wordsTranscribed, 0)
        XCTAssertEqual(appState.totalDictationSeconds, 0)
    }

    private func makeAppState(historyStore: InMemoryHistoryStore, statsStore: InMemoryStatsStore) -> AppState {
        AppState(
            historyStore: historyStore,
            statsStore: statsStore,
            appPreferencesStore: InMemoryPreferencesStore(),
            audioDeviceService: FakeAudioDeviceService(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            startServices: false,
            llmE2EMode: .none
        )
    }
}

private final class InMemoryHistoryStore: HistoryStoreProtocol {
    var savedEntries: [HistoryEntry] = []

    func load() -> [HistoryEntry] {
        savedEntries
    }

    func save(_ entries: [HistoryEntry]) {
        savedEntries = entries
    }
}

private final class InMemoryStatsStore: StatsStoreProtocol {
    var savedSnapshot: StatsSnapshot?

    func load() -> StatsSnapshot {
        savedSnapshot ?? .zero
    }

    func save(_ snapshot: StatsSnapshot) {
        savedSnapshot = snapshot
    }
}

private final class InMemoryPreferencesStore: AppPreferencesStoreProtocol {
    var preferences = AppPreferences()

    func load() -> AppPreferences {
        preferences
    }

    func save(_ preferences: AppPreferences) {
        self.preferences = preferences
    }
}

private final class FakeAudioDeviceService: AudioDeviceServiceProtocol {
    func availableInputDevices() -> [AudioInputDevice] {
        [AudioInputDevice(uid: "default-mic", name: "Default Mic", isDefault: true)]
    }

    func defaultInputDeviceUID() -> String? {
        "default-mic"
    }

    func resolveSelectedInputDeviceUID(_ preferredUID: String?) -> String? {
        if preferredUID == "default-mic" {
            return preferredUID
        }
        return "default-mic"
    }

    func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        nil
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServiceProtocol {
    private var enabled = false

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
    }
}
