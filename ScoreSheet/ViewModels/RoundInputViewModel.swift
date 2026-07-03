import Foundation
import Observation

/// 回戦入力の状態。順位並び替え → 2着以下ポイント入力 → トップ自動計算 の流れを管理。
@Observable
final class RoundInputViewModel {
    let gameType: GameType
    let participants: [Participant]
    let roundNumber: Int
    let editingRoundID: UUID?

    /// rank(1...n) の席に入れたプレイヤー。index = rank-1。
    var rankedIDs: [UUID?]
    /// 2着以下のポイント入力（rank をキーに文字列で保持）。
    var pointsText: [Int: String] = [:]
    var memo: String = ""

    init(gameType: GameType,
         participants: [Participant],
         roundNumber: Int,
         previousOrder: [UUID]? = nil,
         editing round: RoundResult? = nil) {
        self.gameType = gameType
        self.participants = participants
        self.roundNumber = round?.roundNumber ?? roundNumber
        self.editingRoundID = round?.id
        self.rankedIDs = Array(repeating: nil, count: gameType.playerCount)

        if let round {
            // 編集：既存の順位・ポイントを復元。
            for p in round.points where p.rank >= 1 && p.rank <= gameType.playerCount {
                rankedIDs[p.rank - 1] = p.participantID
                if p.rank >= 2 { pointsText[p.rank] = "\(p.point)" }
            }
            memo = round.memo
        } else if let previousOrder, previousOrder.count == gameType.playerCount {
            // 前回の並びをコピー（ポイントは空）。
            for (i, id) in previousOrder.enumerated() { rankedIDs[i] = id }
        }
    }

    var playerCount: Int { gameType.playerCount }
    var ranks: [Int] { Array(1...playerCount) }
    var lowerRanks: [Int] { Array(2...playerCount) }   // 2着以下

    // MARK: 順位割り当て

    func participant(atRank rank: Int) -> Participant? {
        guard let id = rankedIDs[rank - 1] else { return nil }
        return participants.first { $0.id == id }
    }

    /// あるプレイヤーを指定順位に割り当てる。既に他の順位にいれば入れ替える。
    func assign(_ id: UUID, toRank rank: Int) {
        if let existing = rankedIDs.firstIndex(of: id) {
            // 入れ替え：割り当て先に今いる人を、元の席へ移す。
            let target = rankedIDs[rank - 1]
            rankedIDs[existing] = target
            rankedIDs[rank - 1] = id
        } else {
            rankedIDs[rank - 1] = id
        }
    }

    /// まだどの順位にも割り当てられていないプレイヤー。
    var unassigned: [Participant] {
        participants.filter { p in !rankedIDs.contains(p.id) }
    }

    // MARK: ポイント

    func point(atRank rank: Int) -> Int {
        Int(pointsText[rank]?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
    }

    func setPoint(_ value: Int, atRank rank: Int) {
        pointsText[rank] = "\(value)"
    }

    func adjustPoint(byQuick delta: Int, atRank rank: Int) {
        setPoint(point(atRank: rank) + delta, atRank: rank)
    }

    func flipSign(atRank rank: Int) {
        setPoint(-point(atRank: rank), atRank: rank)
    }

    /// トップ（1着）ポイント = 2着以下の合計 × -1。
    var topPoint: Int {
        ScoreCalculator.autoTopPoint(others: lowerRanks.map { point(atRank: $0) })
    }

    /// 全員合計（常に 0 になる想定。検証用に表示）。
    var totalCheck: Int {
        topPoint + lowerRanks.reduce(0) { $0 + point(atRank: $1) }
    }

    var isBalanced: Bool { totalCheck == 0 }

    // MARK: 検証

    var allSeatsFilled: Bool { !rankedIDs.contains(nil) }
    var allLowerPointsEntered: Bool {
        lowerRanks.allSatisfy { rank in
            let t = (pointsText[rank] ?? "").trimmingCharacters(in: .whitespaces)
            return Int(t) != nil
        }
    }

    var validationMessage: String? {
        if !allSeatsFilled { return "全ての順位にプレイヤーを割り当ててください" }
        if !allLowerPointsEntered { return "2着以下のポイントを入力してください" }
        return nil
    }

    var canSave: Bool { validationMessage == nil }

    /// 現在の並び（rank順のID）。次回コピー用。
    var currentOrder: [UUID] { rankedIDs.compactMap { $0 } }

    /// 保存用の PlayerRoundPoint 配列を構築。
    func buildPoints() -> [PlayerRoundPoint]? {
        guard canSave else { return nil }
        var result: [PlayerRoundPoint] = []
        for rank in ranks {
            guard let id = rankedIDs[rank - 1] else { return nil }
            let pt = rank == 1 ? topPoint : point(atRank: rank)
            result.append(PlayerRoundPoint(participantID: id, rank: rank, point: pt, isAutoCalculated: rank == 1))
        }
        return result
    }
}
