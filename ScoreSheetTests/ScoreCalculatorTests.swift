import XCTest
@testable import ScoreSheet

/// コア計算ロジックの回帰テスト。トップ自動計算・チップ換算・最終集計を実測で保証する。
final class ScoreCalculatorTests: XCTestCase {

    // MARK: トップ自動計算

    func testAutoTopYonma() {
        // 2着+5, 3着-15, 4着-30 → トップ+40
        XCTAssertEqual(ScoreCalculator.autoTopPoint(others: [5, -15, -30]), 40)
    }

    func testAutoTopSanma() {
        // 2着-5, 3着-25 → トップ+30
        XCTAssertEqual(ScoreCalculator.autoTopPoint(others: [-5, -25]), 30)
    }

    func testAutoTopMakesRoundBalanced() {
        let others = [8, -3, -25]
        let top = ScoreCalculator.autoTopPoint(others: others)
        XCTAssertTrue(ScoreCalculator.isRoundBalanced([top] + others))
        XCTAssertEqual(top + others.reduce(0, +), 0)
    }

    // MARK: チップ

    func testChipPointBasic() {
        XCTAssertEqual(ScoreCalculator.chipPoint(count: 3, coefficient: 5), 15)
        XCTAssertEqual(ScoreCalculator.chipPoint(count: -2, coefficient: 5), -10)
        XCTAssertEqual(ScoreCalculator.chipPoint(count: 0, coefficient: 5), 0)
    }

    func testChipPointRoundsToNearestInt() {
        // 3枚 × 2.5 = 7.5 → 8（四捨五入）
        XCTAssertEqual(ScoreCalculator.chipPoint(count: 3, coefficient: 2.5), 8)
    }

    // MARK: 1000点係数（補助）

    func testPointFromScore() {
        // 原点から +12000点, 1000点=2pt → +24pt
        XCTAssertEqual(ScoreCalculator.pointFromScore(scoreDiffFromOrigin: 12000, per1000: 2), 24)
        XCTAssertEqual(ScoreCalculator.pointFromScore(scoreDiffFromOrigin: -3000, per1000: 1), -3)
    }

    // MARK: 最終集計（四麻サンプル）

    func testFinalResultsYonmaSample() {
        let a = Player(name: "A"), b = Player(name: "B"), c = Player(name: "C"), d = Player(name: "D")
        let session = SampleDataService.makeYonmaSample(a, b, c, d)
        let results = ScoreCalculator.finalResults(for: session)

        // 総合の合計は 0（ゼロサム）
        XCTAssertEqual(results.reduce(0) { $0 + $1.grandTotal }, 0)

        // 順位: B(+58) > A(-8) > D(-15) > C(-35)
        XCTAssertEqual(results.map(\.name), ["B", "A", "D", "C"])
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0) })
        XCTAssertEqual(byName["B"]?.grandTotal, 58)
        XCTAssertEqual(byName["A"]?.grandTotal, -8)
        XCTAssertEqual(byName["D"]?.grandTotal, -15)
        XCTAssertEqual(byName["C"]?.grandTotal, -35)

        // 対局ポイント（チップ除く）も合計0
        XCTAssertEqual(results.reduce(0) { $0 + $1.roundPointTotal }, 0)
        XCTAssertEqual(byName["B"]?.roundPointTotal, 43)
        XCTAssertEqual(byName["D"]?.roundPointTotal, 0)

        // トップ回数・順位番号
        XCTAssertEqual(byName["B"]?.topCount, 1)
        XCTAssertEqual(byName["B"]?.rank, 1)
        XCTAssertEqual(byName["C"]?.rank, 4)
    }

    // MARK: 最終集計（三麻サンプル）

    func testFinalResultsSanmaSample() {
        let x = Player(name: "X"), y = Player(name: "Y"), z = Player(name: "Z")
        let session = SampleDataService.makeSanmaSample(x, y, z)
        let results = ScoreCalculator.finalResults(for: session)

        XCTAssertEqual(results.reduce(0) { $0 + $1.grandTotal }, 0)
        // 順位: X(+15) > Z(-5) > Y(-10)
        XCTAssertEqual(results.map(\.name), ["X", "Z", "Y"])
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.name, $0) })
        XCTAssertEqual(byName["X"]?.grandTotal, 15)
        XCTAssertEqual(byName["Z"]?.grandTotal, -5)
        XCTAssertEqual(byName["Y"]?.grandTotal, -10)
        // 全員トップ1回・平均順位2.0
        XCTAssertEqual(byName["X"]?.topCount, 1)
        XCTAssertEqual(byName["Y"]?.averageRank ?? 0, 2.0, accuracy: 0.001)
    }

    // MARK: タイブレーク

    func testTieBreakByRoundPointWhenGrandTotalEqual() {
        // 総合同点 → 対局ポイントが大きい方が上位
        let p1 = Participant(name: "同点高対局", colorHex: "000000")
        let p2 = Participant(name: "同点低対局", colorHex: "111111")
        let session = TableSession(gameType: .sanma, participants: [p1, p2, Participant(name: "調整", colorHex: "222222")], chipPointCoefficient: 1)
        // p1: 対局+10 / チップ-10, p2: 対局-10 / チップ+10, 3人目で釣り合わせ
        let third = session.participants[2]
        let r = RoundResult(roundNumber: 1, points: [
            PlayerRoundPoint(participantID: p1.id, rank: 1, point: 10, isAutoCalculated: true),
            PlayerRoundPoint(participantID: p2.id, rank: 2, point: -10, isAutoCalculated: false),
            PlayerRoundPoint(participantID: third.id, rank: 3, point: 0, isAutoCalculated: false),
        ])
        session.rounds.append(r)
        session.chips = [
            ChipEntry(participantID: p1.id, chipCount: -10),
            ChipEntry(participantID: p2.id, chipCount: 10),
        ]
        let results = ScoreCalculator.finalResults(for: session)
        let p1r = results.first { $0.participantID == p1.id }!
        let p2r = results.first { $0.participantID == p2.id }!
        // 総合は両者0で同点、対局ポイントで p1(+10) が上位
        XCTAssertEqual(p1r.grandTotal, 0)
        XCTAssertEqual(p2r.grandTotal, 0)
        XCTAssertLessThan(p1r.rank, p2r.rank)
    }
}
