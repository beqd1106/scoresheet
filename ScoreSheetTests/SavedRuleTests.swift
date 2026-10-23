import XCTest
import SwiftData
@testable import ScoreSheet

/// 保存したルール：上書き・壊れたデータへの耐性・バックアップでの持ち運びを固定する。
final class SavedRuleTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "SavedRuleTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func sample(_ name: String, uma: [Int] = [30, 10, -10, -30]) -> SavedRule {
        var rule = GameRule.standard(for: .yonma)
        rule.uma = uma
        rule.yakitoriEnabled = true
        return SavedRule(name: name, gameType: .yonma, inputMode: .rawScore, rule: rule,
                         pointCoefficientPer1000: 100, chipPointCoefficient: 200)
    }

    func testRoundTripKeepsEverything() {
        let original = [sample("いつもの雀荘"), sample("会社", uma: [10, 5, -5, -10])]
        SavedRuleStore.save(original, defaults)
        let loaded = SavedRuleStore.load(defaults)
        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded[0].rule.uma, [30, 10, -10, -30])
        XCTAssertEqual(loaded[0].chipPointCoefficient, 200)
    }

    func testUpsertReplacesSameNameAndKeepsID() {
        let first = sample("いつもの")
        var list = SavedRuleStore.upsert(first, into: []).rules
        let changed = sample("  いつもの  ", uma: [20, 10, -10, -20])   // 前後の空白は無視
        let result = SavedRuleStore.upsert(changed, into: list)
        list = result.rules

        XCTAssertTrue(result.replaced)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, first.id)
        XCTAssertEqual(list[0].rule.uma, [20, 10, -10, -20])
    }

    func testBrokenItemDoesNotDropOthers() {
        let good = SavedRuleStore.encode([sample("A")])
        // 2件目は型が壊れている（rule が数値）。1件目は残ること。
        let json = good.dropLast() + #",{"name":"B","rule":123}]"#
        let loaded = SavedRuleStore.decode(String(json))
        XCTAssertEqual(loaded.map(\.name), ["A"])
        XCTAssertEqual(SavedRuleStore.decode("not json"), [])
        XCTAssertEqual(SavedRuleStore.decode(""), [])
    }

    func testMissingKeysFallBackToDefaults() {
        // 将来の項目が無い古いデータでも読める。
        let loaded = SavedRuleStore.decode(#"[{"name":"古い"}]"#)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].gameType, .yonma)
        XCTAssertEqual(loaded[0].inputMode, .point)
        XCTAssertEqual(loaded[0].pointCoefficientPer1000, AppDefaults.pointCoefficientPer1000)
    }

    func testMatchesIgnoresRuleInPointMode() {
        var saved = sample("P")
        saved.inputModeRaw = InputMode.point.rawValue
        XCTAssertTrue(saved.matches(gameType: .yonma, inputMode: .point, rule: GameRule(),
                                    pointCoefficientPer1000: 100, chipPointCoefficient: 200))
        XCTAssertFalse(saved.matches(gameType: .sanma, inputMode: .point, rule: GameRule(),
                                     pointCoefficientPer1000: 100, chipPointCoefficient: 200))
    }

    func testSuggestedNameSkipsUsed() {
        let list = [sample("マイルール2")]
        XCTAssertEqual(SavedRuleStore.suggestedName(existing: list), "マイルール3")
        XCTAssertEqual(SavedRuleStore.suggestedName(existing: []), "マイルール1")
    }

    func testApplyToSetupViewModel() {
        var sanmaRule = GameRule.standard(for: .sanma)
        sanmaRule.kubiEnabled = true
        let saved = SavedRule(name: "三麻", gameType: .sanma, inputMode: .rawScore, rule: sanmaRule,
                              pointCoefficientPer1000: 150, chipPointCoefficient: 300)
        let vm = TableSetupViewModel()
        vm.selectedPlayerIDs = [UUID(), UUID(), UUID(), UUID()]
        vm.apply(saved)

        XCTAssertEqual(vm.gameType, .sanma)
        XCTAssertEqual(vm.inputMode, .rawScore)
        XCTAssertEqual(vm.rule, sanmaRule)
        XCTAssertEqual(vm.pointCoefficientPer1000, 150)
        XCTAssertEqual(vm.selectedPlayerIDs.count, 3)   // 人数超過分は外す
        XCTAssertTrue(vm.isCurrent(saved))
    }

    func testBackupCarriesRulesAndMergesWithoutDuplicates() throws {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)

        let rules = [sample("A"), sample("B")]
        let file = try BackupService.decode(BackupService.encode(
            BackupService.makeBackup(players: [], sessions: [], savedRules: rules)))
        XCTAssertEqual(file.savedRules, rules)

        // 端末側に同名の A だけある → B だけ追加。
        SavedRuleStore.save([sample("A")], defaults)
        let summary = try BackupService.restore(file, into: context, defaults: defaults)
        XCTAssertEqual(summary.addedRules, 1)
        XCTAssertEqual(SavedRuleStore.load(defaults).map(\.name), ["A", "B"])
    }

    func testOldBackupWithoutRulesStillDecodes() throws {
        let json = #"{"version":1,"exportedAt":"2026-01-01T00:00:00Z","players":[],"sessions":[]}"#
        let file = try BackupService.decode(Data(json.utf8))
        XCTAssertNil(file.savedRules)
    }

    // MARK: タグ

    func testTagsRoundTripAndOldDataHasNoTags() {
        var r = sample("金曜")
        r.tags = ["金曜会"]
        SavedRuleStore.save([r], defaults)
        XCTAssertEqual(SavedRuleStore.load(defaults).first?.tags, ["金曜会"])
        XCTAssertEqual(SavedRuleStore.decode(#"[{"name":"古い"}]"#).first?.tags, [])
        XCTAssertEqual(SavedRuleStore.normalizedTags([" 金曜会 ", "", "金曜会", "旅行"]), ["金曜会", "旅行"])
    }

    func testApplyAddsRuleTagsAndSwitchingKeepsManualTags() {
        var friday = sample("金曜")
        friday.tags = ["金曜会", "雀荘A"]
        var trip = sample("旅行")
        trip.tags = ["旅行"]

        let vm = TableSetupViewModel()
        vm.tags = ["手で付けた", "雀荘A"]
        vm.apply(friday)
        XCTAssertEqual(vm.tags, ["手で付けた", "雀荘A", "金曜会"])   // 重複は足さない

        vm.apply(trip)
        // ルールから付いた「金曜会」だけ外れ、手で付けたタグは残る。
        XCTAssertEqual(vm.tags, ["手で付けた", "雀荘A", "旅行"])
        XCTAssertTrue(vm.isCurrent(trip))                              // タグは「選択中」判定に使わない
        XCTAssertEqual(vm.makeSavedRule(name: "今").tags, ["手で付けた", "雀荘A", "旅行"])
    }
}
