import XCTest
import SwiftData
@testable import ScoreSheet

/// バックアップの書き出し・復元が内容を落とさないことを保証する。
final class BackupServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeSampleSession() -> (Player, TableSession) {
        let player = Player(name: "たろう", colorHex: Theme.playerPalette[0])
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.tobiIncludesZero = true
        rule.tobiPenalty = 30

        let participants = (0..<4).map { i in
            Participant(name: "P\(i)", colorHex: Theme.playerPalette[i])
        }
        let session = TableSession(gameType: .yonma,
                                   participants: participants,
                                   tags: ["定例"],
                                   inputMode: .rawScore,
                                   rule: rule)
        let points = participants.enumerated().map { idx, p in
            PlayerRoundPoint(participantID: p.id, rank: idx + 1, point: [50, 10, -20, -40][idx],
                             isAutoCalculated: true, rawScore: [40000, 30000, 20000, 10000][idx],
                             isYakitori: idx == 3)
        }
        let round = RoundResult(roundNumber: 1, points: points)
        round.session = session
        session.rounds.append(round)
        session.chips = [ChipEntry(participantID: participants[0].id, chipCount: 2)]
        return (player, session)
    }

    func testBackupRoundTripKeepsRuleAndRawScores() throws {
        let (player, session) = makeSampleSession()
        let data = try BackupService.encode(
            BackupService.makeBackup(players: [player], sessions: [session])
        )
        let restoredFile = try BackupService.decode(data)

        let context = try makeContext()
        let summary = try BackupService.restore(restoredFile, into: context)
        XCTAssertEqual(summary.addedPlayers, 1)
        XCTAssertEqual(summary.addedSessions, 1)

        let sessions = try context.fetch(FetchDescriptor<TableSession>())
        XCTAssertEqual(sessions.count, 1)
        let restored = try XCTUnwrap(sessions.first)
        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.inputMode, .rawScore)
        XCTAssertTrue(restored.rule.tobiEnabled)
        XCTAssertTrue(restored.rule.tobiIncludesZero)
        XCTAssertEqual(restored.rule.tobiPenalty, 30)
        XCTAssertEqual(restored.tags, ["定例"])
        XCTAssertEqual(restored.chipCount(for: session.participants[0].id), 2)

        let round = try XCTUnwrap(restored.sortedRounds.first)
        XCTAssertEqual(round.points.count, 4)
        XCTAssertEqual(round.points.map(\.rawScore), [40000, 30000, 20000, 10000])
        XCTAssertEqual(round.points.last?.isYakitori, true)
        XCTAssertEqual(round.point(for: session.participants[0].id), 50)
    }

    func testRestoringTwiceDoesNotDuplicate() throws {
        let (player, session) = makeSampleSession()
        let file = BackupService.makeBackup(players: [player], sessions: [session])

        let context = try makeContext()
        _ = try BackupService.restore(file, into: context)
        let second = try BackupService.restore(file, into: context)

        XCTAssertEqual(second.addedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TableSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Player>()).count, 1)
    }

    func testEmptyBackupIsHarmless() throws {
        let context = try makeContext()
        let summary = try BackupService.restore(BackupFile(), into: context)
        XCTAssertEqual(summary.addedSessions, 0)
        XCTAssertEqual(summary.addedPlayers, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TableSession>()).isEmpty)
    }
}
