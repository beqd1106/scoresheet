import Foundation
import SwiftData

/// 1回戦の結果。points に全プレイヤー分（トップ含む）を格納。
@Model
final class RoundResult {
    // CloudKit 同期のため全プロパティにデフォルト値を持たせる（制約）。
    var id: UUID = UUID()
    var roundNumber: Int = 0
    var points: [PlayerRoundPoint] = []
    var memo: String = ""
    var createdAt: Date = Date()

    @Relationship(inverse: \TableSession.rounds)
    var session: TableSession?

    init(roundNumber: Int, points: [PlayerRoundPoint], memo: String = "") {
        self.id = UUID()
        self.roundNumber = roundNumber
        self.points = points
        self.memo = memo
        self.createdAt = Date()
    }

    /// 合計チェック。0 なら全員のポイントが釣り合っている。
    var pointSum: Int { points.reduce(0) { $0 + $1.point } }
    var isBalanced: Bool { pointSum == 0 }

    /// 指定プレイヤーのこの回のポイント。
    func point(for participantID: UUID) -> Int {
        points.first { $0.participantID == participantID }?.point ?? 0
    }

    /// 指定プレイヤーのこの回の順位。
    func rank(for participantID: UUID) -> Int? {
        points.first { $0.participantID == participantID }?.rank
    }
}
