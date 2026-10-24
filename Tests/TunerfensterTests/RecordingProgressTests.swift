import XCTest
@testable import Tunerfenster

final class RecordingProgressTests: XCTestCase {
    func testServerFieldsDecodeAndDistinguishUnwatchedPartialAndWatched() throws {
        let data = Data(#"{"uuid":"a","playposition":123,"playcount":0,"watched":0}"#.utf8)
        let recording = try JSONDecoder().decode(SavedRecording.self, from: data)
        XCTAssertEqual(recording.progress.position, 123)
        XCTAssertFalse(recording.progress.seen)
        XCTAssertEqual(recording.progress.symbol, "circle.lefthalf.filled")
        XCTAssertEqual(RecordingProgress().symbol, "circle")
        XCTAssertTrue(RecordingProgress(playcount: 2).seen)
        XCTAssertTrue(RecordingProgress(watched: 1_700_000_000).seen)
        XCTAssertFalse(RecordingProgress(playcount: 0, watched: 1_700_000_000).seen, "An explicit unwatched mark wins over an old timestamp")
        XCTAssertEqual(RecordingProgress(playposition: 40, playcount: 1).symbol, "eye.fill")
        for position in [-1.0, .nan, .infinity, Double(UInt32.max) + 1] {
            XCTAssertEqual(RecordingProgress(playposition: position).position, 0)
        }
        XCTAssertFalse(RecordingProgress(watched: .nan).seen)
        XCTAssertEqual(RecordingProgress.time(3672), "1:01:12")
    }

    func testCheckpointsThrottleAndForcePauseSwitchAndExitWithoutRepeatingIdenticalWrites() {
        var session = RecordingProgressSession(uuid: "one", running: false)
        let start = Date(timeIntervalSince1970: 1000)
        func sample(_ seconds: Double) -> RecordingPlaybackSample { .init(position: seconds, duration: 1000, playing: true) }
        XCTAssertEqual(session.checkpoint(sample(10), force: false, now: start), .init(position: 10, seen: false))
        XCTAssertNil(session.checkpoint(sample(15), force: false, now: start.addingTimeInterval(5)))
        XCTAssertEqual(session.checkpoint(sample(16), force: true, now: start.addingTimeInterval(6)), .init(position: 16, seen: false))
        XCTAssertNil(session.checkpoint(sample(16), force: true, now: start.addingTimeInterval(7)))
        XCTAssertEqual(session.checkpoint(sample(26), force: false, now: start.addingTimeInterval(16)), .init(position: 26, seen: false))
    }

    func testStartupFailedPlaybackAndPendingResumeNeverReplaceSavedPositionWithZero() {
        var session = RecordingProgressSession(uuid: "one", running: false)
        for sample in [RecordingPlaybackSample(position: 0, duration: 1000),
                       .init(position: 0, duration: 1000, playing: true),
                       .init(position: 1, duration: 1000, playing: true, restoring: true),
                       .init(position: 999, duration: 1000, playing: true, restoring: true),
                       .init(position: 100, duration: 1000, playing: true, failed: true),
                       .init(position: .nan, duration: 1000, playing: true)] {
            XCTAssertNil(session.checkpoint(sample, force: true))
        }
        XCTAssertEqual(session.checkpoint(.init(position: 120, duration: 1000, paused: true), force: true), .init(position: 120, seen: false))
        var fromStart = RecordingProgressSession(uuid: "one", running: false, fromBeginning: true)
        XCTAssertEqual(fromStart.checkpoint(.init(position: 0, duration: 1000, playing: true), force: true), .init(position: 0, seen: false))
    }

    func testCompletionAtNinetyPercentOrEndClearsResumeButRunningRecordingsStayPartial() {
        var session = RecordingProgressSession(uuid: "one", running: false)
        XCTAssertEqual(session.checkpoint(.init(position: 899, duration: 1000, playing: true), force: true), .init(position: 899, seen: false))
        XCTAssertEqual(session.checkpoint(.init(position: 900, duration: 1000, playing: true), force: true), .init(position: 0, seen: true))
        XCTAssertNil(session.checkpoint(.init(position: 901, duration: 1000, playing: true), force: true))
        XCTAssertEqual(session.checkpoint(.init(position: 100, duration: 1000, playing: true), force: true), .init(position: 100, seen: false))
        var ended = RecordingProgressSession(uuid: "one", running: false)
        XCTAssertEqual(ended.checkpoint(.init(position: 0, duration: 0, ended: true), force: true), .init(position: 0, seen: true))
        var running = RecordingProgressSession(uuid: "one", running: true)
        XCTAssertEqual(running.checkpoint(.init(position: 999, duration: 1000, playing: true), force: true), .init(position: 999, seen: false))
    }

    func testPendingProgressPersistsByServerAccountAndCompletionDoesNotClearExistingCount() throws {
        let suite = "Tunerfenster.ProgressTests.\(UUID())", id = String(repeating: "a", count: 32)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let outbox = RecordingProgressOutbox(defaults: defaults)
        let checkpoint = RecordingCheckpoint(position: 120, seen: true)
        let legacy = try JSONDecoder().decode(RecordingCheckpoint.self, from: Data(#"{"position":120,"seen":true}"#.utf8))
        XCTAssertEqual(legacy, checkpoint)
        outbox.save([id: checkpoint], scope: "server-a\nviewer")
        XCTAssertEqual(RecordingProgressOutbox(defaults: defaults).load(scope: "server-a\nviewer"), [id: checkpoint])
        XCTAssertTrue(outbox.load(scope: "server-b\nviewer").isEmpty)
        XCTAssertTrue(outbox.load(scope: "server-a\nother-user").isEmpty)
        XCTAssertEqual(checkpoint.applying(to: .init(playcount: 7)).playcount, 7)
        XCTAssertEqual(checkpoint.applying(to: .init(playcount: 0)).playcount, 1)
        let unseen = RecordingCheckpoint(position: 0, seen: false, seenOverride: false)
        let reset = unseen.applying(to: .init(playposition: 120, playcount: 7, watched: 1_700_000_000))
        XCTAssertFalse(reset.seen)
        XCTAssertEqual(reset.position, 0)
        outbox.save([id: unseen], scope: "server-a\nviewer")
        XCTAssertEqual(outbox.load(scope: "server-a\nviewer")[id]?.seenOverride, false)
        outbox.save([:], scope: "server-a\nviewer")
        XCTAssertTrue(outbox.load(scope: "server-a\nviewer").isEmpty)
    }

    func testManualMarksReplaceOlderPendingIntentAndCarryForwardUntilSent() {
        let watched = RecordingCheckpoint(position: 0, seen: true, seenOverride: true)
        let unwatched = RecordingCheckpoint(position: 0, seen: false, seenOverride: false)
        let position = RecordingCheckpoint(position: 60, seen: false)
        XCTAssertEqual(unwatched.superseding(watched), unwatched)
        XCTAssertEqual(watched.superseding(unwatched), watched)
        XCTAssertEqual(position.superseding(unwatched).seenOverride, false)
        XCTAssertEqual(position.superseding(watched).seenOverride, true)
        XCTAssertEqual(RecordingCheckpoint(position: 0, seen: true).superseding(unwatched).seenOverride, true,
                       "Finishing a later playback session may mark the recording watched again")
    }

    func testPausedOrEndedPlaybackCannotImmediatelyUndoAManualMark() {
        let now = Date(timeIntervalSince1970: 1000)
        var session = RecordingProgressSession(uuid: "one", running: false)
        session.markManually(seen: false, at: 950, now: now)
        for offset in [0.0, 0.4, 0.9] {
            XCTAssertNil(session.checkpoint(.init(position: 950 + offset, duration: 1000, paused: true), force: true, now: now.addingTimeInterval(20)))
        }
        let continued = session.checkpoint(.init(position: 970, duration: 1000, playing: true), force: true, now: now.addingTimeInterval(21))
        XCTAssertEqual(continued, .init(position: 970, seen: false), "The current session must respect an explicit unwatched mark")
        var ended = RecordingProgressSession(uuid: "one", running: false)
        ended.markManually(seen: false, at: 0, now: now)
        XCTAssertNil(ended.checkpoint(.init(position: 0, duration: 0, ended: true), force: true, now: now.addingTimeInterval(20)))
        var seen = RecordingProgressSession(uuid: "one", running: false)
        seen.markManually(seen: true, at: 200, now: now)
        XCTAssertNil(seen.checkpoint(.init(position: 200, duration: 1000, paused: true), force: true, now: now.addingTimeInterval(20)))
    }
}
