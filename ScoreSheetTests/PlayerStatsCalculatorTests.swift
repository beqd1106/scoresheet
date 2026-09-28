import XCTest
@testable import ScoreSheet

/// プレイヤー別の通算成績。率・絞り込み・名前の扱いを固定する。
final class PlayerStatsCalculatorTests: XCTestCase {

    private let a = Participant(name: "A", colorHex: "111111")
    private let b = Participant(name: "B", colorHex: "222222")
    private let c = Participant(name: "C", colorHex: "333333")
    private let d = Participant(name: "D", colorHex: "444444")

    private func date(_ y: Int, _ m: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: 12))!
    }

    /// ranks・points は participants と同じ並び。raw を渡すと素点つき。
    private func round(_ ps: [Participant], ranks: [Int], points: [Int], raw: [Int]? = nil) -> [PlayerRoundPoint] {
        ps.indices.map { i in
            PlayerRoundPoint(participantID: ps[i].id, rank: ranks[i], point: points[i],
                             isAutoCalculated: false, rawScore: raw?[i])
        }
    }

    private func game(_ ps: [Participant], _ type: GameType, _ when: Date,
                      rounds: [[PlayerRoundPoint]], grand: [Int]) -> StatsGame {
        let order = ps.indices.sorted { grand[$0] > grand[$1] }
        var rank: [UUID: Int] = [:]
        for (pos, i) in order.enumerated() { rank[ps[i].id] = pos + 1 }
        return StatsGame(id: UUID(), date: when, gameType: type, participants: ps, rounds: rounds,
                         grandTotals: Dictionary(uniqueKeysWithValues: zip(ps.map(\.id), grand)),
                         gameRanks: rank,
                         roundPointTotals: [:], chipCounts: [:])
    }

    private var yonmaGame: StatsGame {
        game([a, b, c, d], .yonma, date(2026, 1, 10), rounds: [
            round([a, b, c, d], ranks: [1, 2, 3, 4], points: [50, 10, -20, -40], raw: [45000, 30000, 20000, 5000]),
            round([a, b, c, d], ranks: [4, 1, 2, 3], points: [-45, 45, 15, -15], raw: [-3000, 50000, 35000, 18000]),
        ], grand: [250, 2750, -250, -2750])
    }

    private var sanmaGame: StatsGame {
        game([a, b, c], .sanma, date(2025, 6, 1), rounds: [
            round([a, b, c], ranks: [1, 2, 3], points: [40, 0, -40]),
        ], grand: [2000, 0, -2000])
    }

    func testRatesAcrossTypes() {
        let stats = PlayerStatsCalculator.aggregate(games: [yonmaGame, sanmaGame])
        let sa = try! XCTUnwrap(stats.first { $0.id == a.id })

        XCTAssertEqual(sa.games, 2)
        XCTAssertEqual(sa.rounds, 3)
        XCTAssertEqual(sa.rankCounts, [1: 2, 4: 1])
        XCTAssertEqual(sa.averageRank, 2.0, accuracy: 0.0001)
        XCTAssertEqual(sa.topRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(sa.lastRate, 1.0 / 3.0, accuracy: 0.0001)   // 四麻の4着のみ
        XCTAssertEqual(sa.grandTotal, 2250)
        XCTAssertEqual(sa.gameTops, 1)                               // 三麻ゲームで総合1位
        XCTAssertEqual(sa.bestRoundPoint, 50)
        XCTAssertEqual(sa.worstRoundPoint, -45)
    }

    func testLastPlaceDependsOnPlayerCount() {
        // 三麻の3着はラス、四麻の3着はラスではない。
        let stats = PlayerStatsCalculator.aggregate(games: [yonmaGame, sanmaGame])
        let sc = try! XCTUnwrap(stats.first { $0.id == c.id })
        XCTAssertEqual(sc.rankCounts[3], 2)
        XCTAssertEqual(sc.lastCount, 1)
    }

    func testTobiAndRawOnlyCountRoundsWithRawScore() {
        let stats = PlayerStatsCalculator.aggregate(games: [yonmaGame, sanmaGame])
        let sa = try! XCTUnwrap(stats.first { $0.id == a.id })
        XCTAssertEqual(sa.rawRounds, 2)
        XCTAssertEqual(sa.tobiCount, 1)
        XCTAssertEqual(sa.tobiRate ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(sa.averageRawScore, 21000)

        let sanmaOnly = PlayerStatsCalculator.aggregate(games: [sanmaGame])
        XCTAssertNil(sanmaOnly.first { $0.id == a.id }?.tobiRate)
    }

    func testFilterByTypeAndYear() {
        let games = [yonmaGame, sanmaGame]
        let yonma = PlayerStatsCalculator.aggregate(games: games, filter: StatsFilter(gameType: .yonma))
        XCTAssertEqual(yonma.count, 4)
        XCTAssertEqual(yonma.first { $0.id == a.id }?.games, 1)

        let y2025 = PlayerStatsCalculator.aggregate(games: games, filter: StatsFilter(year: 2025))
        XCTAssertEqual(y2025.count, 3)
        XCTAssertNil(y2025.first { $0.id == d.id })

        XCTAssertEqual(PlayerStatsCalculator.availableYears(games), [2026, 2025])
    }

    func testSortedByGrandTotalAndCumulativeHistory() {
        let stats = PlayerStatsCalculator.aggregate(games: [yonmaGame, sanmaGame])
        XCTAssertEqual(stats.first?.id, b.id)   // 2750
        let sa = try! XCTUnwrap(stats.first { $0.id == a.id })
        // 日付の古い順に累計（三麻2025 → 四麻2026）。
        XCTAssertEqual(sa.history.map(\.cumulative), [2000, 2250])
        XCTAssertEqual(sa.bestGame?.grandTotal, 2000)
        XCTAssertEqual(sa.worstGame?.grandTotal, 250)
    }

    func testRosterNameOverridesSnapshot() {
        let stats = PlayerStatsCalculator.aggregate(games: [sanmaGame],
                                                    roster: [a.id: (name: "Aさん", colorHex: "ABCDEF")])
        let sa = try! XCTUnwrap(stats.first { $0.id == a.id })
        XCTAssertEqual(sa.name, "Aさん")
        XCTAssertEqual(sa.colorHex, "ABCDEF")
        XCTAssertEqual(sa.history.first?.opponents, ["B", "C"])
    }

    func testGamesWithoutCountedRoundsAreIgnored() {
        let empty = game([a, b, c], .sanma, date(2026, 2, 1), rounds: [], grand: [0, 0, 0])
        let stats = PlayerStatsCalculator.aggregate(games: [empty])
        XCTAssertTrue(stats.isEmpty)
    }

    // MARK: 空行を順位集計に混ぜない

    func testEmptyTrailingRowIsNotCountedInFinalResults() {
        let session = TableSession(gameType: .sanma, participants: [a, b, c])
        session.rounds.append(RoundResult(roundNumber: 1, points: round([a, b, c], ranks: [1, 2, 3], points: [30, 0, -30])))
        // 表の末尾の未入力行（全員0点）はポイント入力でも順位が振られて保存される。
        session.rounds.append(RoundResult(roundNumber: 2, points: round([a, b, c], ranks: [1, 2, 3], points: [0, 0, 0])))

        let results = ScoreCalculator.finalResults(for: session)
        let ra = try! XCTUnwrap(results.first { $0.participantID == a.id })
        XCTAssertEqual(ra.topCount, 1)
        XCTAssertEqual(ra.averageRank, 1.0, accuracy: 0.0001)
        XCTAssertEqual(StatsGame(session: session).rounds.count, 1)
    }
}
