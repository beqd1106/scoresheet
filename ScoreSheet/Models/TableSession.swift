import Foundation
import SwiftData

/// 1つの卓（対局セッション）。回戦・チップ・設定・参加者をまとめて保持。
@Model
final class TableSession {
    // CloudKit 同期のため全プロパティにデフォルト値を持たせる（制約）。
    var id: UUID = UUID()
    var date: Date = Date()
    var gameTypeRaw: String = GameType.yonma.rawValue
    var participants: [Participant] = []
    var chips: [ChipEntry] = []

    // 設定（TableSettings 相当をインラインで保持）
    var pointCoefficientPer1000: Double = AppDefaults.pointCoefficientPer1000  // 1000点あたり何ポイントか
    var chipPointCoefficient: Double = AppDefaults.chipPointCoefficient        // チップ1枚あたりのポイント係数
    var tags: [String] = []              // 集計グルーピング用タグ
    var memo: String = ""

    // 入力方式とルール（v1.1 追加）。
    // ルールは構造体のまま持つとスキーマ変更の影響が読みにくいため、
    // JSON 文字列（プリミティブ）で保持して軽量マイグレーションを確実にする。
    var inputModeRaw: String = InputMode.point.rawValue
    var ruleJSON: String = ""

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // CloudKit では to-many リレーションは任意（空配列デフォルト）が必須。
    @Relationship(deleteRule: .cascade)
    var rounds: [RoundResult] = []

    init(gameType: GameType,
         participants: [Participant],
         pointCoefficientPer1000: Double = AppDefaults.pointCoefficientPer1000,
         chipPointCoefficient: Double = AppDefaults.chipPointCoefficient,
         tags: [String] = [],
         memo: String = "",
         inputMode: InputMode = .point,
         rule: GameRule? = nil) {
        self.id = UUID()
        self.date = Date()
        self.gameTypeRaw = gameType.rawValue
        self.participants = participants
        self.chips = []
        self.pointCoefficientPer1000 = pointCoefficientPer1000
        self.chipPointCoefficient = chipPointCoefficient
        self.tags = tags
        self.memo = memo
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rounds = []
        self.inputModeRaw = inputMode.rawValue
        self.ruleJSON = TableSession.encodeRule(rule ?? GameRule.standard(for: gameType))
    }

    var gameType: GameType {
        get { GameType(rawValue: gameTypeRaw) ?? .yonma }
        set { gameTypeRaw = newValue.rawValue }
    }

    var inputMode: InputMode {
        get { InputMode(rawValue: inputModeRaw) ?? .point }
        set { inputModeRaw = newValue.rawValue }
    }

    /// 対局ルール。未設定（旧データ）なら種別に応じた標準ルールを返す。
    var rule: GameRule {
        get {
            guard let data = ruleJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(GameRule.self, from: data) else {
                return GameRule.standard(for: gameType)
            }
            return decoded
        }
        set { ruleJSON = TableSession.encodeRule(newValue) }
    }

    static func encodeRule(_ rule: GameRule) -> String {
        guard let data = try? JSONEncoder().encode(rule),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// すでに点数が入力されているか（入力方式の切り替え可否の判定に使う）。
    var hasEnteredScores: Bool {
        rounds.contains { round in
            round.points.contains { $0.rawScore != nil || $0.point != 0 }
        }
    }

    /// 素点入力時に全員の持ち点合計が一致すべき値。
    var expectedTotalScore: Int {
        rule.expectedTotalScore(playerCount: gameType.playerCount)
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
