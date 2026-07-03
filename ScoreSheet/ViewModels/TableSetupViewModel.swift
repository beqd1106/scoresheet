import Foundation
import Observation

/// 新規卓作成の入力状態。
@Observable
final class TableSetupViewModel {
    var gameType: GameType
    var selectedPlayerIDs: [UUID] = []       // 並び順 = 席順の初期値
    var pointCoefficientPer1000: Double
    var chipPointCoefficient: Double
    var memo: String = ""

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
                            memo: memo)
    }
}
