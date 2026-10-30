import XCTest
import SwiftData
@testable import ScoreSheet

/// 三麻の四人回し（1回戦ごとに1人が抜け番）のテスト。
/// 抜け番の人はその回戦の記録に入れず、順位・ゼロサム・集計は打った3人だけで行う。
final class SanmaRotationTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeSession(_ context: ModelContext, mode: InputMode = .rawScore) -> TableSession {
        let participants = (0..<4).map { i in
            Participant(name: "P\(i)", colorHex: Theme.playerPalette[i])
        }
        let session = TableSession(gameType: .sanma,
                                   participants: participants,
                                   inputMode: mode,
                                   rule: GameRule.standard(for: .sanma))
        context.insert(session)
        return session
    }

    // MARK: 判定

    func testRotationIsDetectedFromParticipantCount() throws {
        let context = try makeContext()
        let session = makeSession(context)
        XCTAssertTrue(session.isRotation)
        XCTAssertEqual(session.seatCount, 3)
        XCTAssertEqual(session.displayTitle, "三麻・4人回し")
        XCTAssertEqual(session.expectedTotalScore, 105000)   // 35000持ち×3人（4人分ではない）

        let normal = TableSession(gameType: .sanma,
                                  participants: Array(session.participants.prefix(3)))
        XCTAssertFalse(normal.isRotation)
        XCTAssertEqual(normal.displayTitle, "三麻")
    }

    // MARK: 抜け番の初期値

    func testDefaultSitOutStartsFromLastSeatAndRotates() throws {
        let context = try makeContext()
        let session = makeSession(context)
        let ids = session.participants.map(\.id)

        var input = RoundPersistence.load(from: session)
        XCTAssertEqual(input.sitOut, [ids[3]])

        input.rows += [Array(repeating: "", count: 4), Array(repeating: "", count: 4)]
        input.sitOut += [nil, nil]
        input.fillDefaultSitOut(participants: session.participants)
        XCTAssertEqual(input.sitOut, [ids[3], ids[0], ids[1]])
    }

    // MARK: 素点モード

    func testRawRoundStoresOnlySeatedPlayers() throws {
        let context = try makeContext()
        let session = makeSession(context)
        let ids = session.participants.map(\.id)

        var input = RoundPersistence.load(from: session)
        input.sitOut = [ids[1]]
        // 抜け番の P1 の欄に何か残っていても使わない。
        input.rows = [["50000", "99999", "35000", "20000"]]
        XCTAssertTrue(RoundPersistence.save(input, to: session, context: context))

        let round = try XCTUnwrap(session.sortedRounds.first)
        XCTAssertEqual(round.points.count, 3)
        XCTAssertNil(round.rank(for: ids[1]))
        XCTAssertEqual(round.rank(for: ids[0]), 1)
        XCTAssertEqual(round.rank(for: ids[2]), 2)
        XCTAssertEqual(round.rank(for: ids[3]), 3)
        XCTAssertEqual(round.pointSum, 0)
        XCTAssertTrue(round.points.allSatisfy(\.isAutoCalculated))
        XCTAssertEqual(session.sitOutID(in: round), ids[1])

        let reloaded = RoundPersistence.load(from: session)
        XCTAssertEqual(reloaded.sitOut, [ids[1]])
        XCTAssertEqual(reloaded.rows, [["50000", "", "35000", "20000"]])
    }

    func testBusterWhoSatOutIsIgnored() throws {
        let context = try makeContext()
        let session = makeSession(context)
        var rule = session.rule
        rule.tobiEnabled = true
        rule.tobiPayee = .buster
        session.rule = rule
        let ids = session.participants.map(\.id)

        let settled = try XCTUnwrap(RoundPersistence.settlement(
            row: ["80000", "", "30000", "-5000"],
            yakitori: [false, false, false, false],
            busters: [nil, nil, nil, ids[1]],   // 抜け番の人を「飛ばした人」に指定
            sitOut: ids[1],
            session: session))
        XCTAssertEqual(settled.count, 3)
        XCTAssertFalse(settled.contains { $0.participantID == ids[1] })
        XCTAssertEqual(settled.reduce(0) { $0 + $1.total }, 0)
        // 指定が無効なのでトップ（P0）が受け取る扱いになる。
        let tobi = try XCTUnwrap(settled.first { $0.participantID == ids[3] })
        XCTAssertTrue(tobi.isTobi)
    }

    // MARK: ポイントモードと集計

    func testPointModeRanksAndFinalResults() throws {
        let context = try makeContext()
        let session = makeSession(context, mode: .point)
        let ids = session.participants.map(\.id)

        var input = RoundPersistence.load(from: session)
        input.rows = [
            ["30", "-10", "-20", ""],   // P3 抜け
            ["", "25", "-5", "-20"],    // P0 抜け
        ]
        input.sitOut = [ids[3], ids[0]]
        XCTAssertTrue(RoundPersistence.save(input, to: session, context: context))

        XCTAssertEqual(ScoreCalculator.countedRounds(session).count, 2)

        let results = Dictionary(uniqueKeysWithValues:
            ScoreCalculator.finalResults(for: session).map { ($0.participantID, $0) })
        XCTAssertEqual(results[ids[0]]?.averageRank, 1.0)   // 打ったのは1回だけ
        XCTAssertEqual(results[ids[1]]?.averageRank, 1.5)   // 2着・1着
        XCTAssertEqual(results[ids[1]]?.roundPointTotal, 15)
        XCTAssertEqual(results[ids[3]]?.roundPointTotal, -20)

        let stats = Dictionary(uniqueKeysWithValues:
            PlayerStatsCalculator.aggregate(games: [StatsGame(session: session)]).map { ($0.id, $0) })
        XCTAssertEqual(stats[ids[0]]?.rounds, 1)
        XCTAssertEqual(stats[ids[1]]?.rounds, 2)
        // 三麻の3着はラスとして数える（参加者4人でも卓は3人）。
        XCTAssertEqual(stats[ids[2]]?.lastCount, 1)
        XCTAssertEqual(stats[ids[3]]?.lastCount, 1)
    }

    // MARK: 新規ゲーム画面

    func testSetupRequiresFourPlayersOnlyForSanmaRotation() {
        let vm = TableSetupViewModel(defaultGameType: .sanma)
        XCTAssertTrue(vm.canRotate)
        XCTAssertEqual(vm.requiredCount, 3)
        vm.isRotation = true
        XCTAssertEqual(vm.requiredCount, 4)

        vm.gameType = .yonma
        vm.normalizeSelection()
        XCTAssertFalse(vm.canRotate)
        XCTAssertFalse(vm.isRotation)
        XCTAssertEqual(vm.requiredCount, 4)
    }
}
