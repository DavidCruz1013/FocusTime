import Foundation
import XCTest
@testable import FocusData

final class FocusDataTests: XCTestCase {
    private func instant(_ value: String) -> Date {
        DateCodec.date(value)!
    }

    func testDefaultsRequireNotificationOptIn() throws {
        let repo = try FocusRepository.open(path: ":memory:")
        XCTAssertFalse(try repo.settings().notifications)
        XCTAssertFalse(Settings().notifications)
    }

    func testSessionAndBreakCannotOverlap() throws {
        let repo = try FocusRepository.open(path: ":memory:")
        let start = instant("2026-10-01T12:00:00Z")
        try repo.startSession(seconds: 60, at: start)
        XCTAssertThrowsError(try repo.startSession(seconds: 60, at: start))
        XCTAssertThrowsError(try repo.startBreak(seconds: 60, at: start))
        try repo.finish(try XCTUnwrap(repo.activeSession()), at: start.addingTimeInterval(20), completed: false)
        try repo.startBreak(seconds: 60, at: start.addingTimeInterval(20))
        XCTAssertThrowsError(try repo.startSession(seconds: 60, at: start.addingTimeInterval(21)))
        XCTAssertThrowsError(try repo.startBreak(seconds: 60, at: start.addingTimeInterval(21)))
    }

    func testPauseResumeExcludesTimeWithScreenOffAndRelaunch() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let start = instant("2026-10-01T12:00:00Z")
        do {
            let repo = try FocusRepository.open(path: path)
            try repo.startSession(seconds: 120, at: start)
            let active = try XCTUnwrap(repo.activeSession())
            try repo.pause(active, at: start.addingTimeInterval(30))
            XCTAssertEqual(try repo.activeSession()?.remainingSeconds(at: start.addingTimeInterval(3600)), 90)
        }
        let reopened = try FocusRepository.open(path: path)
        try reopened.resume(try XCTUnwrap(reopened.activeSession()), at: start.addingTimeInterval(3600))
        let resumed = try XCTUnwrap(reopened.activeSession())
        XCTAssertEqual(resumed.deadline, start.addingTimeInterval(3690))
        try reopened.finish(resumed, at: start.addingTimeInterval(7200), completed: true)
        XCTAssertNil(try reopened.activeSession())
        let inspection = try Database(path: path)
        let recordedEnd = try inspection.rows("SELECT fin FROM sesion_concentracion").first?.string(0)
        XCTAssertEqual(DateCodec.date(recordedEnd), start.addingTimeInterval(3690))
        let stats = try reopened.dayStat(on: DateCodec.dayKey(start))
        XCTAssertEqual(stats.sessions, 1)
        XCTAssertEqual(stats.focusMinutes, 2)
    }

    func testCannotAwardSessionOrBreakCompletionEarly() throws {
        let repo = try FocusRepository.open(path: ":memory:")
        let start = instant("2026-10-01T12:00:00Z")
        try repo.startSession(seconds: 60, at: start)
        let active = try XCTUnwrap(repo.activeSession())
        XCTAssertThrowsError(try repo.finish(active, at: start.addingTimeInterval(30), completed: true))
        XCTAssertNotNil(try repo.activeSession())
        try repo.finish(active, at: start.addingTimeInterval(60), completed: true)
        try repo.startBreak(seconds: 60, at: start.addingTimeInterval(60))
        XCTAssertThrowsError(try repo.finishBreak(try XCTUnwrap(repo.activeBreak()), at: start.addingTimeInterval(90), completed: true))
    }

    func testDailyMinutesSplitAtMidnightAndUseActualDeadline() throws {
        let repo = try FocusRepository.open(path: ":memory:")
        var cal = Calendar.current
        cal.timeZone = .current
        let midnight = cal.startOfDay(for: instant("2026-10-10T12:00:00Z"))
        let start = midnight.addingTimeInterval(-60)
        try repo.startSession(seconds: 120, at: start)
        try repo.finish(try XCTUnwrap(repo.activeSession()), at: midnight.addingTimeInterval(100_000), completed: true)
        let before = try repo.dayStat(on: DateCodec.dayKey(start))
        let after = try repo.dayStat(on: DateCodec.dayKey(midnight))
        XCTAssertEqual(before.focusMinutes, 1)
        XCTAssertEqual(before.sessions, 0)
        XCTAssertEqual(after.focusMinutes, 1)
        XCTAssertEqual(after.sessions, 1)
        XCTAssertEqual(try repo.dayStat(on: DateCodec.dayKey(midnight.addingTimeInterval(100_000))).sessions, 0)
    }

    func testStaleSessionCannotDoubleCountSegments() throws {
        let repo = try FocusRepository.open(path: ":memory:")
        let start = instant("2026-10-01T12:00:00Z")
        try repo.startSession(seconds: 120, at: start)
        let stale = try XCTUnwrap(repo.activeSession())
        try repo.pause(stale, at: start.addingTimeInterval(30))
        try repo.pause(stale, at: start.addingTimeInterval(40))
        try repo.finish(stale, at: start.addingTimeInterval(80), completed: false)
        try repo.finish(stale, at: start.addingTimeInterval(90), completed: false)
        XCTAssertEqual(try repo.dayStat(on: DateCodec.dayKey(start)).focusMinutes, 0)
    }

    func testClearCompletedHistoryPreservesGoalsAndActiveSession() throws {
        let repo = try FocusRepository.open(path: ":memory:")
        let start = instant("2026-10-01T12:00:00Z")
        let day = DateCodec.dayKey(start)
        try repo.saveGoal(.sesiones, target: 2, day: day)
        try repo.startSession(seconds: 60, at: start)
        try repo.finish(try XCTUnwrap(repo.activeSession()), at: start.addingTimeInterval(60), completed: true)
        try repo.startSession(seconds: 60, at: start.addingTimeInterval(100))
        let activeID = try repo.activeSession()?.id
        try repo.clearHistory()
        XCTAssertEqual(try repo.activeSession()?.id, activeID)
        XCTAssertEqual(try repo.goals(on: day).first?.target, 2)
        XCTAssertEqual(try repo.dayStat(on: day).sessions, 0)
        XCTAssertEqual(try repo.dayStat(on: day).focusMinutes, 0)
    }

    func testSQLiteQueryFailuresPropagateAndTransactionsRollback() throws {
        let db = try Database(path: ":memory:")
        try db.run("CREATE TABLE sample (value INTEGER NOT NULL UNIQUE)")
        XCTAssertThrowsError(try db.rows("SELECT * FROM nonexistent"))
        // Preparation succeeds; SQLite fails while stepping the result.
        XCTAssertThrowsError(try db.rows("SELECT abs(-9223372036854775808)"))
        XCTAssertThrowsError(try db.run("INSERT INTO sample VALUES (?)"))
        XCTAssertThrowsError(try db.transaction {
            try db.run("INSERT INTO sample VALUES (?)", [.int(1)])
            try db.run("INSERT INTO sample VALUES (?)", [.int(1)])
        })
        XCTAssertEqual(try db.rows("SELECT COUNT(*) FROM sample").first?.int(0), 0)
    }


    func testBreakLinksCompletedSessionAndUsesItsOwnDeadline() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let repo = try FocusRepository.open(path: path)
        let start = instant("2026-10-01T12:00:00Z")
        try repo.startSession(seconds: 60, at: start)
        let session = try XCTUnwrap(repo.activeSession())
        try repo.finish(session, at: start.addingTimeInterval(60), completed: true)
        try repo.startBreak(seconds: 60, at: start.addingTimeInterval(90))
        let active = try XCTUnwrap(repo.activeBreak())
        try repo.finishBreak(active, at: start.addingTimeInterval(7200), completed: true)
        XCTAssertNil(try repo.activeBreak())
        let inspection = try Database(path: path)
        let saved = try XCTUnwrap(inspection.rows("SELECT id_sesion, fin, tiempo_efectivo_seg FROM descanso").first)
        XCTAssertEqual(saved.int(0), session.id)
        XCTAssertEqual(DateCodec.date(saved.string(1)), start.addingTimeInterval(150))
        XCTAssertEqual(saved.int(2), 60)
    }

    func testLegacyDatabaseMigrationPreservesAccumulatedTimeAndResolvesOverlap() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let start = instant("2026-10-01T12:00:00Z")
        do {
            let db = try Database(path: path)
            for sql in Schema.statements { try db.run(sql) }
            try db.run("INSERT INTO perfil VALUES (1, NULL, ?)", [.text(DateCodec.string(start))])
            try db.run("""
                INSERT INTO sesion_concentracion
                (id_perfil, inicio, fecha_local, duracion_objetivo_seg, tiempo_efectivo_seg, estado)
                VALUES (1, ?, ?, 120, 60, 'pausada')
                """, [.text(DateCodec.string(start)), .text(DateCodec.dayKey(start))])
            for _ in 0..<2 {
                try db.run("""
                    INSERT INTO descanso
                    (id_perfil, inicio, fecha_local, duracion_objetivo_seg, estado)
                    VALUES (1, ?, ?, 60, 'activo')
                    """, [.text(DateCodec.string(start)), .text(DateCodec.dayKey(start))])
            }
        }
        let migrated = try FocusRepository.open(path: path)
        XCTAssertNil(try migrated.activeBreak())
        try migrated.finish(try XCTUnwrap(migrated.activeSession()), at: start.addingTimeInterval(80), completed: false)
        XCTAssertEqual(try migrated.dayStat(on: DateCodec.dayKey(start)).focusMinutes, 1)
        _ = try FocusRepository.open(path: path)
        XCTAssertEqual(try migrated.dayStat(on: DateCodec.dayKey(start)).focusMinutes, 1)
    }
}
