import XCTest
@testable import ScoreSheet

/// ヤキトリ罰符の授受だけを取り出して確認するテスト。
/// 素点差・ウマ・オカを含まない `penaltyPoint` を見ることで、罰符のやり取りだけを検証する。
final class YakitoriPaymentTests: XCTestCase {

    private let players = (0..<3).map { _ in UUID() }

    /// 三麻・全員同点（35000×3）。これで素点差とウマ以外の差が出ない状態にする。
    private func penalties(flags: [Bool], unit: PenaltyUnit, amount: Int = 20) -> [Int] {
        var rule = GameRule.standard(for: .sanma)
        rule.yakitoriEnabled = true
        rule.yakitoriPenalty = amount
        rule.yakitoriPayee = .others
        rule.yakitoriUnit = unit
        let s = ScoreCalculator.settle(participantIDs: players,
                                       rawScores: [35000, 35000, 35000],
                                       yakitoriFlags: flags,
                                       rule: rule)
        return s.map(\.penaltyPoint)
    }

    // MARK: 「人に払う」＝受け取る人それぞれに満額

    func testTwoYakitoriOneSafe_perPerson() {
        // A・Bがヤキトリ、Cが回避 → A-20 / B-20 / C+40
        XCTAssertEqual(penalties(flags: [true, true, false], unit: .perPerson), [-20, -20, 40])
    }

    func testOneYakitoriTwoSafe_perPerson() {
        // Aだけヤキトリ → Aは2人に20ptずつ払う → A-40 / B+20 / C+20
        XCTAssertEqual(penalties(flags: [true, false, false], unit: .perPerson), [-40, 20, 20])
    }

    func testAllYakitori_perPerson() {
        // 全員ヤキトリ＝受け取る人がいないので何も起きない
        XCTAssertEqual(penalties(flags: [true, true, true], unit: .perPerson), [0, 0, 0])
    }

    func testNoYakitori_perPerson() {
        // 全員回避＝支払う人がいないので何も起きない
        XCTAssertEqual(penalties(flags: [false, false, false], unit: .perPerson), [0, 0, 0])
    }

    // MARK: 「場に払う」＝罰符の総額を受け取る人で分ける

    func testTwoYakitoriOneSafe_pot() {
        // 受け取りが1人なので「人に払う」と同じ結果になる
        XCTAssertEqual(penalties(flags: [true, true, false], unit: .pot), [-20, -20, 40])
    }

    func testOneYakitoriTwoSafe_pot() {
        // Aが出すのは20ptだけ。それを2人で分けるので +10 ずつ
        XCTAssertEqual(penalties(flags: [true, false, false], unit: .pot), [-20, 10, 10])
    }

    func testAllYakitoriAndNoYakitori_pot() {
        XCTAssertEqual(penalties(flags: [true, true, true], unit: .pot), [0, 0, 0])
        XCTAssertEqual(penalties(flags: [false, false, false], unit: .pot), [0, 0, 0])
    }

    // MARK: 四麻でも同じ考え方

    func testYonmaPerPersonPaysEveryoneElse() {
        var rule = GameRule.standard(for: .yonma)
        rule.yakitoriEnabled = true
        rule.yakitoriPenalty = 20
        rule.yakitoriPayee = .others
        rule.yakitoriUnit = .perPerson
        let ids = (0..<4).map { _ in UUID() }
        let s = ScoreCalculator.settle(participantIDs: ids,
                                       rawScores: [25000, 25000, 25000, 25000],
                                       yakitoriFlags: [true, false, false, false],
                                       rule: rule)
        XCTAssertEqual(s.map(\.penaltyPoint), [-60, 20, 20, 20])   // 3人に20ptずつ
    }
}
