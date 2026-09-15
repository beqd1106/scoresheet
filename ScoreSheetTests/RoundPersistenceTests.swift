import XCTest
import SwiftData
@testable import ScoreSheet

/// 「入力 → 保存 → 開き直して同じ値」を保証するテスト。
/// データが消えないことを守る中心の経路なので、素点・ポイント両モードで確認する。
final class RoundPersistenceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeSession(_ context: ModelContext,
                             mode: InputMode = .rawScore,
                             rule: GameRule? = nil) -> TableSession {
        let participants = (0..<4).map { i in
            Participant(name: "P\(i)", colorHex: Theme.playerPalette[i])
        }
        let session = TableSession(gameType: .yonma,
                                   participants: participants,
                                   inputMode: mode,
                                   rule: rule ?? GameRule.standard(for: .yonma))
        context.insert(session)
        return session
    }

    // MARK: 素点モード

    func testRawScoresSurviveSaveAndReload() throws {
        let context = try makeContext()
        let session = makeSession(context)

        var input = RoundPersistence.load(from: session)
        input.rows = [["40000", "30000", "20000", "10000"]]
        input.yakitori = [[false, false, false, true]]
        input.busters = [[nil, nil, nil, nil]]
        input.chips = ["2", "0", "-1", "-1"]
        XCTAssertTrue(RoundPersistence.save(input, to: session, context: context))

        let reloaded = RoundPersistence.load(from: session)
        XCTAssertEqual(reloaded.rows, [["40000", "30000", "20000", "10000"]])
        XCTAssertEqual(reloaded.yakitori, [[false, false, false, true]])
        XCTAssertEqual(reloaded.chips, ["2", "", "-1", "-1"])   // 0 は空欄として表示する
        XCTAssertEqual(session.rounds.count, 1)
    }

    func testCalculatedPointsAreStored() throws {
        let context = try makeContext()
        let session = makeSession(context)

        var input = RoundPersistence.load(from: session)
        input.rows = [["40000", "30000", "20000", "10000"]]
        RoundPersistence.save(input, to: session, context: context)

        let round = try XCTUnwrap(session.sortedRounds.first)
        XCTAssertEqual(round.points.map(\.point), [50, 10, -20, -40])
        XCTAssertEqual(round.points.map(\.rank), [1, 2, 3, 4])
        XCTAssertEqual(round.pointSum, 0)
    }

    func testPartialInputIsKept() throws {
        let context = try makeContext()
        let session = makeSession(context)

        var input = RoundPersistence.load(from: session)
        input.rows = [["40000", "", "20000", ""]]   // 入力途中
        RoundPersistence.save(input, to: session, context: context)

        let reloaded = RoundPersistence.load(from: session)
        XCTAssertEqual(reloaded.rows, [["40000", "", "20000", ""]])
        // 計算は確定していないのでポイントは 0 のまま
        XCTAssertEqual(session.sortedRounds.first?.points.map(\.point), [0, 0, 0, 0])
    }

    func testBusterSelectionSurvives() throws {
        let context = try makeContext()
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.tobiPayee = .buster
        let session = makeSession(context, rule: rule)

        var input = RoundPersistence.load(from: session)
        input.rows = [["61000", "30000", "10000", "-1000"]]
        input.busters = [[nil, nil, nil, session.participants[1].id]]
        RoundPersistence.save(input, to: session, context: context)

        let reloaded = RoundPersistence.load(from: session)
        XCTAssertEqual(reloaded.busters[0][3], session.participants[1].id)
        XCTAssertEqual(session.sortedRounds.first?.points.map(\.point), [71, 30, -30, -71])
    }

    // MARK: 回戦の増減

    func testAddingAndRemovingRounds() throws {
        let context = try makeContext()
        let session = makeSession(context)

        var input = RoundPersistence.load(from: session)
        input.rows = [["40000", "30000", "20000", "10000"],
                      ["25000", "25000", "25000", "25000"],
                      ["30000", "30000", "20000", "20000"]]
        input.normalize(playerCount: 4)
        RoundPersistence.save(input, to: session, context: context)
        XCTAssertEqual(session.rounds.count, 3)
        XCTAssertEqual(session.sortedRounds.map(\.roundNumber), [1, 2, 3])

        // 2回戦を削除
        input.rows.remove(at: 1)
        input.yakitori.remove(at: 1)
        input.busters.remove(at: 1)
        RoundPersistence.save(input, to: session, context: context)

        XCTAssertEqual(session.rounds.count, 2)
        XCTAssertEqual(session.sortedRounds.map(\.roundNumber), [1, 2])
        let reloaded = RoundPersistence.load(from: session)
        XCTAssertEqual(reloaded.rows, [["40000", "30000", "20000", "10000"],
                                       ["30000", "30000", "20000", "20000"]])
    }

    func testRepeatedSavesDoNotDuplicateRounds() throws {
        let context = try makeContext()
        let session = makeSession(context)

        var input = RoundPersistence.load(from: session)
        input.rows = [["40000", "30000", "20000", "10000"]]
        for _ in 0..<5 {
            RoundPersistence.save(input, to: session, context: context)
        }
        XCTAssertEqual(session.rounds.count, 1)
    }

    // MARK: ポイント入力モード

    func testPointModeKeepsEnteredValues() throws {
        let context = try makeContext()
        let session = makeSession(context, mode: .point)

        var input = RoundPersistence.load(from: session)
        input.rows = [["40", "5", "-15", "-30"]]
        RoundPersistence.save(input, to: session, context: context)

        let reloaded = RoundPersistence.load(from: session)
        XCTAssertEqual(reloaded.rows, [["40", "5", "-15", "-30"]])
        let round = try XCTUnwrap(session.sortedRounds.first)
        XCTAssertEqual(round.points.map(\.point), [40, 5, -15, -30])
        XCTAssertEqual(round.points.map(\.rank), [1, 2, 3, 4])
    }

    // MARK: 配列の長さが合わない入力でも壊れない

    func testNormalizeFillsMissingHelpers() {
        var input = ScoreTableInput(rows: [["1", "2", "3", "4"], ["5", "6", "7", "8"]],
                                    yakitori: [], busters: [], chips: [])
        input.normalize(playerCount: 4)
        XCTAssertEqual(input.yakitori.count, 2)
        XCTAssertEqual(input.busters.count, 2)
        XCTAssertEqual(input.chips.count, 4)
        XCTAssertEqual(input.yakitori[0].count, 4)
    }

    func testSaveWithShortRowDoesNotCrash() throws {
        let context = try makeContext()
        let session = makeSession(context)
        var input = ScoreTableInput(rows: [["40000", "30000"]], yakitori: [], busters: [], chips: [])
        input.normalize(playerCount: 4)
        XCTAssertTrue(RoundPersistence.save(input, to: session, context: context))
        XCTAssertEqual(session.sortedRounds.first?.points.count, 4)
    }
}
