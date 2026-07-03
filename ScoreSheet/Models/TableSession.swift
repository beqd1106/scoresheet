import Foundation
import SwiftData

/// 1つの卓（対局セッション）。回戦・チップ・設定・参加者をまとめて保持。
@Model
final class TableSession {
    var id: UUID
    var date: Date
    var gameTypeRaw: String
    var participants: [Participant]
    var chips: [ChipEntry]

    // 設定（TableSettings 相当をインラインで保持）
    var pointCoefficientPer1000: Double  // 1000点あたり何ポイントか（補助機能）
    var chipPointCoefficient: Double     // チップ1枚あたりのポイント係数
    var memo: String

    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade)
    var rounds: [RoundResult]

    init(gameType: GameType,
         participants: [Participant],
         pointCoefficientPer1000: Double = AppDefaults.pointCoefficientPer1000,
         chipPointCoefficient: Double = AppDefaults.chipPointCoefficient,
         memo: String = "") {
        self.id = UUID()
        self.date = Date()
        self.gameTypeRaw = gameType.rawValue
        self.participants = participants
        self.chips = []
        self.pointCoefficientPer1000 = pointCoefficientPer1000
        self.chipPointCoefficient = chipPointCoefficient
        self.memo = memo
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rounds = []
    }

    var gameType: GameType {
        get { GameType(rawValue: gameTypeRaw) ?? .yonma }
        set { gameTypeRaw = newValue.rawValue }
    }

    /// 回戦番号順に並べた回戦一覧。
    var sortedRounds: [RoundResult] {
        rounds.sorted { $0.roundNumber < $1.roundNumber }
    }

    /// 次に追加する回戦番号。
    var nextRoundNumber: Int {
        (rounds.map(\.roundNumber).max() ?? 0) + 1
    }

    /// 指定プレイヤーの対局ポイント累計（チップ除く）。
    func roundTotal(for participantID: UUID) -> Int {
        rounds.reduce(0) { $0 + $1.point(for: participantID) }
    }

    /// 指定プレイヤーのチップ枚数。
    func chipCount(for participantID: UUID) -> Int {
        chips.first { $0.participantID == participantID }?.chipCount ?? 0
    }

    func participant(_ id: UUID) -> Participant? {
        participants.first { $0.id == id }
    }
}
