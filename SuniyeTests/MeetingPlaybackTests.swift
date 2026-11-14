import XCTest
@testable import Suniye

/// The playback of a meeting's kept audio, with a player whose time moves
/// only when a test moves it.
@MainActor
final class MeetingPlaybackTests: XCTestCase {
    private var root: URL!
    private var store: MeetingStore!
    private var playback: MeetingPlayback!
    private var players: [FakeMeetingAudioPlayer] = []
    private var openedFiles: [Set<URL>] = []
    private var opens = true
    private let meeting = UUID()

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingPlaybackTests-\(UUID().uuidString)", isDirectory: true)
        store = MeetingStore(rootDirectory: root)
        playback = MeetingPlayback(store: store, makePlayer: { [unowned self] files in
            guard opens else { throw CocoaError(.fileReadCorruptFile) }
            openedFiles.append(Set(files))
            let player = FakeMeetingAudioPlayer(duration: 60)
            players.append(player)
            return player
        }, tickInterval: .milliseconds(5))
    }

    override func tearDown() async throws {
        playback.close()
        try? FileManager.default.removeItem(at: root)
    }

    private func writeAudio(_ tracks: MeetingTrack..., of id: UUID? = nil) throws {
        let id = id ?? meeting
        try FileManager.default.createDirectory(at: store.folder(for: id), withIntermediateDirectories: true)
        for track in tracks {
            let writer = try MeetingAudioFileWriter(url: store.audioURL(track, for: id))
            try writer.append([Float](repeating: 0, count: 1_600))
            try writer.close()
        }
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    func testPlayOpensBothTracksAndThePositionFollowsThePlayer() async throws {
        try writeAudio(.you, .them)
        playback.open(meeting)
        playback.play()

        players[0].currentTime = 12
        let followed = await waitUntil { playback.position == 12 }

        XCTAssertEqual(openedFiles, [[store.audioURL(.you, for: meeting), store.audioURL(.them, for: meeting)]])
        XCTAssertEqual(players[0].starts, [0])
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(followed)
    }

    func testPlayGoesOnFromThePauseAndFromTheStartAfterTheEnd() throws {
        try writeAudio(.you)
        playback.open(meeting)
        playback.play()
        players[0].currentTime = 30

        playback.pause()
        let paused = playback.position
        playback.play()
        players[0].playToEnd()
        let ended = playback.position
        playback.play()

        XCTAssertEqual(paused, 30)
        XCTAssertEqual(ended, 60, "the player goes back to 0; the bar stays at the end")
        XCTAssertEqual(players[0].starts, [0, 30, 0])
    }

    func testAnEndThatArrivesAfterANewStartIsIgnored() throws {
        try writeAudio(.you)
        playback.open(meeting)
        playback.play()
        let end = players[0].onEnd

        playback.seek(to: 45)
        end()

        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.position, 45)
    }

    func testSeekPlaysFromThereWhilePlayingAndOnlyMovesWhilePaused() throws {
        try writeAudio(.you)
        playback.open(meeting)
        playback.play()

        playback.seek(to: 40)
        playback.pause()
        playback.seek(to: 10)

        XCTAssertEqual(players[0].starts, [0, 40])
        XCTAssertEqual(playback.position, 10)
        XCTAssertFalse(playback.isPlaying)
    }

    func testOutputThatStopsBeforeTheEndPausesWhereItWas() async throws {
        try writeAudio(.you)
        playback.open(meeting)
        playback.play()
        players[0].currentTime = 20
        _ = await waitUntil { playback.position == 20 }

        players[0].isPlaying = false
        let stopped = await waitUntil { !playback.isPlaying }

        XCTAssertTrue(stopped)
        XCTAssertEqual(playback.position, 20)
    }

    func testAudioThatDoesNotOpenShowsAFailureAndDoesNotPlay() throws {
        try writeAudio(.you)
        opens = false

        playback.open(meeting)
        playback.play()

        XCTAssertTrue(playback.failed)
        XCTAssertFalse(playback.isPlaying)
    }

    func testAnotherMeetingClosesTheAudioOfTheFirst() throws {
        let other = UUID()
        try writeAudio(.you)
        try writeAudio(.you, of: other)
        playback.open(meeting)
        playback.play()

        playback.open(other)

        XCTAssertFalse(players[0].isPlaying)
        XCTAssertEqual(playback.meetingID, other)
        XCTAssertEqual(playback.position, 0)
        XCTAssertFalse(playback.isPlaying)
    }

    func testTheTrackPlayersTakeThePositionFromTheLongestTrack() throws {
        try writeAudio(.you)
        let longer = store.audioURL(.them, for: meeting)
        let writer = try MeetingAudioFileWriter(url: longer)
        try writer.append([Float](repeating: 0, count: 16_000))
        try writer.close()

        let players = try MeetingTrackPlayers(urls: [store.audioURL(.you, for: meeting), longer])

        XCTAssertEqual(players.duration, 1, accuracy: 0.01)
        XCTAssertThrowsError(try MeetingTrackPlayers(urls: []))
    }
}
