import Foundation
import Observation

/// 新規卓作成の入力状態。
@Observable
final class TableSetupViewModel {
    var gameType: GameType
    var selectedPlayerIDs: [UUID] = []       // 並び順 = 席順の初期値
    var pointCoefficientPer1000: Double
    var chipPointCoefficient: Double
    var tags: [String] = []
    /// 保存ルールから付いたタグ。別のルールに切り替えたら外す（手で足したタグは残す）。
    private(set) var tagsFromRule: [String] = []
    var memo: String = ""
    var inputMode: InputMode = .point
    var rule: GameRule = GameRule.standard(for: .yonma)

    init(defaultGameType: GameType = .yonma,
         pointCoefficientPer1000: Double = AppDefaults.pointCoefficientPer1000,
         chipPointCoefficient: Double = AppDefaults.chipPointCoefficient) {
        self.gameType = defaultGameType
        self.pointCoefficientPer1000 = pointCoefficientPer1000
        self.chipPointCoefficient = chipPointCoefficient
    }

    var requiredCount: Int { gameType.playerCount }

    func toggle(_ id: UUID) {
        if let idx = selectedPlayerIDs.firstIndex(of: id) {
            selectedPlayerIDs.remove(at: idx)
        } else if selectedPlayerIDs.count < requiredCount {
            selectedPlayerIDs.append(id)
        }
    }

    func isSelected(_ id: UUID) -> Bool { selectedPlayerIDs.contains(id) }

    /// 種別変更時、超過分の選択を切り詰める。
    func normalizeSelection() {
        if selectedPlayerIDs.count > requiredCount {
            selectedPlayerIDs = Array(selectedPlayerIDs.prefix(requiredCount))
        }
        applyGameTypeToRule()
    }

    /// 種別変更にルールを追従させる。
    /// 触っていない（＝もう一方の標準のままの）ときは丸ごと標準へ、
    /// 手を入れている場合はウマの人数だけ合わせて設定を残す。
    private func applyGameTypeToRule() {
        let other: GameType = gameType == .sanma ? .yonma : .sanma
        if rule == GameRule.standard(for: other) {
            rule = GameRule.standard(for: gameType)
        } else {
            rule.normalize(for: gameType)
        }
    }

    // MARK: 保存ルール

    /// 保存ルールを当てはめる（種別・入力方式・係数・ルールをまとめて）。
    func apply(_ saved: SavedRule) {
        gameType = saved.gameType
        inputMode = saved.inputMode
        pointCoefficientPer1000 = saved.pointCoefficientPer1000
        chipPointCoefficient = saved.chipPointCoefficient
        var r = saved.rule
        r.normalize(for: saved.gameType)
        rule = r
        tags.removeAll { tagsFromRule.contains($0) }
        let added = saved.tags.filter { !tags.contains($0) }
        tags.append(contentsOf: added)
        tagsFromRule = added
        if selectedPlayerIDs.count > requiredCount {
            selectedPlayerIDs = Array(selectedPlayerIDs.prefix(requiredCount))
        }
    }

    /// 今の設定を保存ルールにする。
    func makeSavedRule(name: String) -> SavedRule {
        SavedRule(name: name, gameType: gameType, inputMode: inputMode, rule: rule,
                  pointCoefficientPer1000: pointCoefficientPer1000,
                  chipPointCoefficient: chipPointCoefficient,
                  tags: tags)
    }

    func isCurrent(_ saved: SavedRule) -> Bool {
        saved.matches(gameType: gameType, inputMode: inputMode, rule: rule,
                      pointCoefficientPer1000: pointCoefficientPer1000,
                      chipPointCoefficient: chipPointCoefficient)
    }

    var canStart: Bool { selectedPlayerIDs.count == requiredCount }

    var validationMessage: String? {
        if selectedPlayerIDs.count != requiredCount {
            return "\(gameType.displayName)は\(requiredCount)人を選んでください（現在\(selectedPlayerIDs.count)人）"
        }
        return nil
    }

    /// 選択された Player 群からセッションを生成。
    func makeSession(from roster: [Player]) -> TableSession? {
        guard canStart else { return nil }
        let participants: [Participant] = selectedPlayerIDs.compactMap { id in
            roster.first { $0.id == id }?.participant
        }
        guard participants.count == requiredCount else { return nil }
        return TableSession(gameType: gameType,
                            participants: participants,
                            pointCoefficientPer1000: pointCoefficientPer1000,
                            chipPointCoefficient: chipPointCoefficient,
                            tags: tags,
                            memo: memo,
                            inputMode: inputMode,
                            rule: rule)
    }
}
