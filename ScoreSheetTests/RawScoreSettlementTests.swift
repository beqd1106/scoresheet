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

    // MARK: ヤキトリの払い方（場に払う / 人に払う）

    func testYakitoriPotSplitsAmountAmongReceivers() {
        var rule = GameRule.standard(for: .sanma)
        rule.yakitoriEnabled = true
        rule.yakitoriPenalty = 20
        rule.yakitoriPayee = .others
        rule.yakitoriUnit = .pot          // 20pt を2人で分ける → 10ptずつ
        let s = ScoreCalculator.settle(participantIDs: ids(3),
                                       rawScores: [50000, 35000, 20000],
                                       yakitoriFlags: [false, false, true],
                                       rule: rule)
        XCTAssertEqual(totals(s), [55, 5, -60])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testYakitoriPerPersonPaysEachReceiverInFull() {
        var rule = GameRule.standard(for: .sanma)
        rule.yakitoriEnabled = true
        rule.yakitoriPenalty = 20
        rule.yakitoriPayee = .others
        rule.yakitoriUnit = .perPerson    // 2人に20ptずつ → 支払いは合計40pt
        let s = ScoreCalculator.settle(participantIDs: ids(3),
                                       rawScores: [50000, 35000, 20000],
                                       yakitoriFlags: [false, false, true],
                                       rule: rule)
        XCTAssertEqual(totals(s), [65, 15, -80])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testYakitoriPerPersonYonma() {
        var rule = GameRule.standard(for: .yonma)
        rule.yakitoriEnabled = true
        rule.yakitoriPenalty = 20
        rule.yakitoriPayee = .others
        rule.yakitoriUnit = .perPerson    // 3人に20ptずつ → 支払いは合計60pt
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: [false, false, false, true],
                                       rule: rule)
        XCTAssertEqual(totals(s), [70, 30, 0, -100])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testTwoYakitoriPlayersPerPerson() {
        var rule = GameRule.standard(for: .yonma)
        rule.yakitoriEnabled = true
        rule.yakitoriPenalty = 10
        rule.yakitoriPayee = .others
        rule.yakitoriUnit = .perPerson
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: [false, false, true, true],
                                       rule: rule)
        // 該当2人がそれぞれ非該当2人へ10ptずつ（各自 -20pt、受け取りは各 +20pt）
        XCTAssertEqual(totals(s), [70, 30, -40, -60])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testPayeeTopIsUnaffectedByUnit() {
        var pot = GameRule.standard(for: .yonma)
        pot.yakitoriEnabled = true
        pot.yakitoriPayee = .top
        pot.yakitoriUnit = .pot
        var perPerson = pot
        perPerson.yakitoriUnit = .perPerson
        let scores = [40000, 30000, 20000, 10000]
        let flags = [false, false, false, true]
        let a = ScoreCalculator.settle(participantIDs: ids(4), rawScores: scores,
                                       yakitoriFlags: flags, rule: pot)
        let b = ScoreCalculator.settle(participantIDs: ids(4), rawScores: scores,
                                       yakitoriFlags: flags, rule: perPerson)
        XCTAssertEqual(totals(a), totals(b))   // 受け取りが1人なら払い方で差は出ない
    }

    // MARK: 保存形式の互換（設定が増えても古いデータを壊さない）

    func testOldRuleJSONWithoutUnitKeysKeepsOtherSettings() throws {
        let oldJSON = """
        {"startingPoints":25000,"returnPoints":30000,"uma":[20,10,-10,-20],
         "rounding":"gosyaRokunyu","tobiEnabled":true,"tobiPenalty":30,
         "tobiIncludesZero":true,"tobiPayee":"top","yakitoriEnabled":true,
         "yakitoriPenalty":20,"yakitoriPayee":"others","kubiEnabled":false,
         "kubiPenalty":10,"kubiPayee":"top"}
        """
        let rule = try JSONDecoder().decode(GameRule.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(rule.tobiPenalty, 30)
        XCTAssertTrue(rule.tobiIncludesZero)
        XCTAssertTrue(rule.yakitoriEnabled)
        XCTAssertEqual(rule.yakitoriUnit, .pot)     // 無いキーは既定値で補う
        XCTAssertEqual(rule.tobiUnit, .pot)
    }

    func testEmptyRuleJSONDecodesToDefaults() throws {
        let rule = try JSONDecoder().decode(GameRule.self, from: Data("{}".utf8))
        XCTAssertEqual(rule, GameRule())
    }

    func testSessionKeepsOldRuleJSON() {
        let session = TableSession(gameType: .yonma, participants: [])
        session.ruleJSON = #"{"yakitoriEnabled":true,"yakitoriPenalty":40}"#
        XCTAssertTrue(session.rule.yakitoriEnabled)
        XCTAssertEqual(session.rule.yakitoriPenalty, 40)
        XCTAssertEqual(session.rule.startingPoints, 25000)   // 残りは既定値
    }

    // MARK: クビ（最下位罰符）

    func testKubiLastPlacePenaltyGoesToTop() {
        var rule = GameRule.standard(for: .yonma)
        rule.kubiEnabled = true
        rule.kubiCondition = .lastPlace
        rule.kubiPenalty = 10
        rule.kubiPayee = .top
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertEqual(totals(s), [60, 10, -20, -50])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testKubiBelowThresholdCatchesEveryoneUnderTheLine() {
        var rule = GameRule.standard(for: .yonma)
        rule.kubiEnabled = true
        rule.kubiCondition = .belowThreshold
        rule.kubiThreshold = 25000      // 25000点に届かなければ罰符
        rule.kubiPenalty = 10
        rule.kubiPayee = .top
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        // 20000 と 10000 の2人が該当（30000 は基準以上なので対象外）
        XCTAssertEqual(s.map(\.isKubi), [false, false, true, true])
        XCTAssertEqual(totals(s), [70, 10, -30, -50])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testKubiThresholdIsExclusive() {
        var rule = GameRule.standard(for: .yonma)
        rule.kubiEnabled = true
        rule.kubiCondition = .belowThreshold
        rule.kubiThreshold = 20000
        rule.kubiPenalty = 10
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [40000, 30000, 20000, 10000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       rule: rule)
        XCTAssertEqual(s.map(\.isKubi), [false, false, false, true])   // ちょうど20000は対象外
    }

    // MARK: トビ罰符を飛ばした人が受け取る

    func testTobiPenaltyGoesToTheNamedBuster() {
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.tobiPenalty = 20
        rule.tobiPayee = .buster
        let players = ids(4)
        let s = ScoreCalculator.settle(participantIDs: players,
                                       rawScores: [61000, 30000, 10000, -1000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       busterIDs: [nil, nil, nil, players[1]],   // 2番目の人が飛ばした
                                       rule: rule)
        XCTAssertEqual(totals(s), [71, 30, -30, -71])
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testTobiFallsBackToTopWhenBusterIsNotChosen() {
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.tobiPenalty = 20
        rule.tobiPayee = .buster
        let s = ScoreCalculator.settle(participantIDs: ids(4),
                                       rawScores: [61000, 30000, 10000, -1000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       busterIDs: [nil, nil, nil, nil],
                                       rule: rule)
        XCTAssertEqual(totals(s), [91, 10, -30, -71])   // 指定されるまではトップが受け取る
        XCTAssertEqual(totals(s).reduce(0, +), 0)
    }

    func testBusterPointingAtThemselvesIsIgnored() {
        var rule = GameRule.standard(for: .yonma)
        rule.tobiEnabled = true
        rule.tobiPenalty = 20
        rule.tobiPayee = .buster
        let players = ids(4)
        let s = ScoreCalculator.settle(participantIDs: players,
                                       rawScores: [61000, 30000, 10000, -1000],
                                       yakitoriFlags: Array(repeating: false, count: 4),
                                       busterIDs: [nil, nil, nil, players[3]],   // 自分自身
                                       rule: rule)
        XCTAssertEqual(totals(s), [91, 10, -30, -71])   // トップ受け取りに戻る
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
