import XCTest
@testable import ScoreSheet

/// 素点入力モード（自動計算）の回帰テスト。
/// 期待値は「返し点との差 → ウマ → 罰符 → 余りをトップへ」の順で手計算したもの。
final class RawScoreSettlementTests: XCTestCase {

    private func ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

    private func totals(_ settlements: [RoundSettlement]) -> [Int] {
        settlements.map(\.total)
    }

    // MARK: 端数処理

    func testGosyaRokunyu() {
        XCTAssertEqual(RoundingMode.gosyaRokunyu.apply(2.5), 2)   // 500点は切り捨て
        XCTAssertEqual(RoundingMode.gosyaRokunyu.apply(2.6), 3)   // 600点は切り上げ
        XCTAssertEqual(RoundingMode.gosyaRokunyu.apply(-2.5), -2)
        XCTAssertEqual(RoundingMode.gosyaRokunyu.apply(-2.6), -3)
    }

    func testRoundHalfUpAndTruncate() {
        XCTAssertEqual(RoundingMode.roundHalfUp.apply(2.5), 3)
        XCTAssertEqual(RoundingMode.roundHalfUp.apply(-2.5), -3)
        XCTAssertEqual(RoundingMode.truncate.apply(2.9), 2)
        XCTAssertEqual(RoundingMode.truncate.apply(-2.9), -2)
    }

    // MARK: 基本（四麻・標準ルール）

    func testYonmaStandard() {
        let rule = GameRule.standard(for: .yonma)   // 25000持ち30000返し・ウマ20/10/-10/-20
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertEqual(totals(s), [50, 10, -20, -40])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
        XCTAssertEqual(s.map(\.rank), [1, 2, 3, 4])
        XCTAssertEqual(s[0].okaPoint, 20)   // オカはトップに入る
    }

    func testSanmaStandard() {
        let rule = GameRule.standard(for: .sanma)   // 35000持ち40000返し・ウマ20/0/-20
        let s = ScoreCalculator.settle(participantIDs: ids(3),
                                       rawScores: [50000, 35000, 20000],
                                       yakitoriFlags: Array(repeating: false, count: 3),
                                       rule: rule)
        XCTAssertEqual(totals(s), [45, -5, -40])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
        XCTAssertEqual(rule.okaPoint(playerCount: 3), 15)
    }

    func testOkaLessRuleHasNoTopBonus() {
        var rule = GameRule.standard(for: .yonma)
        rule.returnPoints = rule.startingPoints     // オカなし
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertEqual(totals(s), [35, 15, -15, -35])
        XCTAssertEqual(s[0].okaPoint, 0)
    }

    // MARK: 同点

    func testTieIsBrokenBySeatOrder() {
        let rule = GameRule.standard(for: .yonma)
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [30000, 30000, 20000, 20000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertEqual(s.map(\.rank), [1, 2, 3, 4])   // 同点は席順が上の人が上位
        XCTAssertEqual(totals(s), [40, 10, -20, -30])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    // MARK: トビ

    func testTobiIsNotAppliedToExactlyZeroByDefault() {
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.tobiPenalty = 20
        rule.tobiIncludesZero = false
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [60000, 30000, 10000, 0],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertFalse(s[3].isTobi)
        XCTAssertEqual(totals(s), [70, 10, -30, -50])
    }

    func testTobiCanIncludeExactlyZero() {
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.tobiPenalty = 20
        rule.tobiIncludesZero = true
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [60000, 30000, 10000, 0],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertTrue(s[3].isTobi)
        XCTAssertEqual(totals(s), [90, 10, -30, -70])   // 罰符20がトップへ
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testMinusScoreIsAlwaysTobiWhenEnabled() {
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [61000, 30000, 10000, -1000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertTrue(s[3].isTobi)
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testTobiDisabledByDefault() {
        let rule = GameRule.standard(for: .yonma)
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [61000, 30000, 10000, -1000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertFalse(s[3].isTobi)
    }

    // MARK: ヤキトリ

    func testYakitoriIsSharedByOthers() {
        var rule = GameRule.standard(for: .yonma)
        rule.yakitoriEnabled = true
        rule.yakitoriPenalty = 20
        rule.yakitoriPayee = .others
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: [false, false, false, true],
                                       rule: rule)
        XCTAssertTrue(s[3].isYakitori)
        // 20pt を3人で分けると1人6pt、余り2ptはトップ調整に吸収される
        XCTAssertEqual(totals(s), [58, 16, -14, -60])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testYakitoriFlagIsIgnoredWhenRuleIsOff() {
        let rule = GameRule.standard(for: .yonma)   // ヤキトリ無効
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: [false, false, false, true],
                                       rule: rule)
        XCTAssertFalse(s[3].isYakitori)
        XCTAssertEqual(totals(s), [50, 10, -20, -40])
    }

    // MARK: クビ（最下位罰符）

    func testKubiPenaltyGoesToTop() {
        var rule = GameRule.standard(for: .yonma)
        rule.kubiEnabled = true
        rule.kubiPenalty = 10
        rule.kubiPayee = .top
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertEqual(totals(s), [60, 10, -20, -50])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    // MARK: 端数が出てもゼロサムが崩れないこと

    func testAlwaysZeroSumWithOddScores() {
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.yakitoriEnabled = true
        rule.kubiEnabled = true
        let samples: [[Int]] = [
            [33400, 27300, 24800, 14500],
            [52100, 25600, 22400, -100],
            [25000, 25000, 25000, 25000],
            [48700, 31200, 11300, 8800]
        ]
        for scores in samples {
            let s = ScoreCalculator.settle(participantIDs: ids(4),
                                           rawScores: scores,
                                           yakitoriFlags: [false, true, false, false],
                                           rule: rule)
            XCTAssertEqual(totals(s).reduce(0, +), 0, "scores=\(scores) の合計が0でない")
            XCTAssertEqual(Set(s.map(\.rank)), Set(1...4))
        }
    }

    // MARK: 入力チェック

    func testRawRoundCompletionAndBalance() {
        let rule = GameRule.standard(for: .yonma)
        XCTAssertFalse(ScoreCalculator.isRawRoundComplete([25000, nil, 25000, 25000]))
        XCTAssertTrue(ScoreCalculator.isRawRoundComplete([25000, 25000, 25000, 25000]))
        XCTAssertTrue(ScoreCalculator.isRawRoundBalanced([40000, 30000, 20000, 10000],
                                                         rule: rule, playerCount: 4))
        XCTAssertFalse(ScoreCalculator.isRawRoundBalanced([40000, 30000, 20000, 11000],
                                                          rule: rule, playerCount: 4))
    }

    func testExpectedTotalScore() {
        XCTAssertEqual(GameRule.standard(for: .yonma).expectedTotalScore(playerCount: 4), 100000)
        XCTAssertEqual(GameRule.standard(for: .sanma).expectedTotalScore(playerCount: 3), 105000)
    }

    // MARK: セッションへの保存互換

    func testSessionKeepsInputModeAndRule() {
        var rule = GameRule.standard(for: .yonma)
        rule.kubiEnabled = true
        rule.kubiPenalty = 15
        let session = TableSession(gameType: .yonma,
                                   participants: [],
                                   inputMode: .rawScore,
                                   rule: rule)
        XCTAssertEqual(session.inputMode, .rawScore)
        XCTAssertTrue(session.rule.kubiEnabled)
        XCTAssertEqual(session.rule.kubiPenalty, 15)
    }

    func testSessionWithoutRuleJSONFallsBackToStandard() {
        let session = TableSession(gameType: .sanma, participants: [])
        session.ruleJSON = ""          // 旧バージョンのデータ相当
        XCTAssertEqual(session.rule, GameRule.standard(for: .sanma))
        XCTAssertEqual(session.inputMode, .point)   // 既定はポイント入力（従来どおり）
    }
}
