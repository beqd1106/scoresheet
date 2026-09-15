import XCTest
import SwiftData
@testable import ScoreSheet

/// 自動バックアップ（端末内に数世代残す仕組み）のテスト。
/// 保存先はテスト用の一時フォルダを渡して、実機のデータに触れないようにしている。
final class AutoBackupServiceTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoBackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeSession(rounds: Int) -> TableSession {
        let participants = (0..<4).map { i in
            Participant(name: "P\(i)", colorHex: Theme.playerPalette[i])
        }
        let session = TableSession(gameType: .yonma, participants: participants, inputMode: .rawScore)
        for r in 0..<rounds {
            let points = participants.enumerated().map { idx, p in
                PlayerRoundPoint(participantID: p.id, rank: idx + 1, point: [50, 10, -20, -40][idx],
                                 isAutoCalculated: true, rawScore: [40000, 30000, 20000, 10000][idx])
            }
            let round = RoundResult(roundNumber: r + 1, points: points)
            round.session = session
            session.rounds.append(round)
        }
        return session
    }

    // MARK: 書き出し

    func testSnapshotCreatesFile() {
        let snap = AutoBackupService.snapshotIfNeeded(players: [Player(name: "たろう")],
                                                      sessions: [makeSession(rounds: 1)],
                                                      in: dir)
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.sessionCount, 1)
        XCTAssertEqual(snap?.playerCount, 1)
        XCTAssertEqual(AutoBackupService.list(in: dir).count, 1)
    }

    func testSameContentIsNotSavedTwice() {
        let players = [Player(name: "たろう")]
        let sessions = [makeSession(rounds: 1)]
        let first = AutoBackupService.snapshotIfNeeded(players: players, sessions: sessions, in: dir,
                                                       now: Date(timeIntervalSince1970: 1_000_000))
        let second = AutoBackupService.snapshotIfNeeded(players: players, sessions: sessions, in: dir,
                                                        now: Date(timeIntervalSince1970: 1_000_100))
        XCTAssertNotNil(first)
        XCTAssertNil(second, "内容が同じなら世代を増やさない")
        XCTAssertEqual(AutoBackupService.list(in: dir).count, 1)
    }

    func testChangedContentAddsGeneration() {
        let players = [Player(name: "たろう")]
        _ = AutoBackupService.snapshotIfNeeded(players: players, sessions: [makeSession(rounds: 1)],
                                               in: dir, now: Date(timeIntervalSince1970: 1_000_000))
        _ = AutoBackupService.snapshotIfNeeded(players: players, sessions: [makeSession(rounds: 2)],
                                               in: dir, now: Date(timeIntervalSince1970: 1_000_100))
        XCTAssertEqual(AutoBackupService.list(in: dir).count, 2)
    }

    func testEmptyDataIsNotSaved() {
        XCTAssertNil(AutoBackupService.snapshotIfNeeded(players: [], sessions: [], in: dir))
        XCTAssertTrue(AutoBackupService.list(in: dir).isEmpty)
    }

    // MARK: 世代の上限

    func testOldGenerationsArePruned() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<(AutoBackupService.maxGenerations + 3) {
            _ = AutoBackupService.snapshotIfNeeded(players: [Player(name: "P\(i)")],
                                                   sessions: [makeSession(rounds: i + 1)],
                                                   in: dir,
                                                   now: base.addingTimeInterval(Double(i) * 60))
        }
        let list = AutoBackupService.list(in: dir)
        XCTAssertEqual(list.count, AutoBackupService.maxGenerations)
        // 新しい順に並び、いちばん新しいものが残っている
        XCTAssertEqual(list.first?.date, base.addingTimeInterval(Double(AutoBackupService.maxGenerations + 2) * 60))
        XCTAssertEqual(list, list.sorted { $0.date > $1.date })
    }

    // MARK: 復元

    func testRestoreFromSnapshot() throws {
        let session = makeSession(rounds: 2)
        let snap = try XCTUnwrap(AutoBackupService.snapshotIfNeeded(players: [Player(name: "たろう")],
                                                                    sessions: [session],
                                                                    in: dir))
        let context = try makeContext()
        let summary = try AutoBackupService.restore(snap, into: context)
        XCTAssertEqual(summary.addedSessions, 1)
        XCTAssertEqual(summary.addedPlayers, 1)

        let restored = try XCTUnwrap(try context.fetch(FetchDescriptor<TableSession>()).first)
        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.rounds.count, 2)
        XCTAssertEqual(restored.sortedRounds.first?.points.map(\.rawScore),
                       [40000, 30000, 20000, 10000])
    }

    func testRestoreDoesNotDuplicateExistingGames() throws {
        let snap = try XCTUnwrap(AutoBackupService.snapshotIfNeeded(players: [],
                                                                    sessions: [makeSession(rounds: 1)],
                                                                    in: dir))
        let context = try makeContext()
        _ = try AutoBackupService.restore(snap, into: context)
        let second = try AutoBackupService.restore(snap, into: context)
        XCTAssertEqual(second.addedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TableSession>()).count, 1)
    }
}
