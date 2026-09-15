import Foundation
import SwiftData

/// スコア表の入力内容（画面の @State に対応する値）。
struct ScoreTableInput: Equatable {
    var rows: [[String]] = []        // rows[回戦][プレイヤー] = 入力テキスト
    var yakitori: [[Bool]] = []      // ヤキトリ該当
    var busters: [[UUID?]] = []      // その人を飛ばした人
    var chips: [String] = []         // チップ枚数

    /// 回戦数に対して補助配列が足りなければ埋める（人数変更・旧データ対策）。
    mutating func normalize(playerCount n: Int) {
        if rows.isEmpty { rows = [Array(repeating: "", count: n)] }
        for i in rows.indices where rows[i].count != n {
            var row = rows[i]
            row = Array(row.prefix(n))
            while row.count < n { row.append("") }
            rows[i] = row
        }
        while yakitori.count < rows.count { yakitori.append(Array(repeating: false, count: n)) }
        while busters.count < rows.count { busters.append(Array(repeating: nil, count: n)) }
        yakitori = Array(yakitori.prefix(rows.count))
        busters = Array(busters.prefix(rows.count))
        for i in yakitori.indices where yakitori[i].count != n {
            yakitori[i] = Array(repeating: false, count: n)
        }
        for i in busters.indices where busters[i].count != n {
            busters[i] = Array(repeating: nil, count: n)
        }
        if chips.count != n { chips = Array(repeating: "", count: n) }
    }
}

/// スコア表の読み込み・保存・その回戦の計算をまとめた置き場。
/// 画面に書いていると自動テストで守れないため、ここへ切り出している。
enum RoundPersistence {

    // MARK: 読み込み

    /// セッションから画面用の入力内容を組み立てる。
    static func load(from session: TableSession) -> ScoreTableInput {
        let participants = session.participants
        let n = participants.count
        let isRaw = session.inputMode == .rawScore
        let sorted = session.sortedRounds

        var input = ScoreTableInput()
        input.rows = sorted.map { round in
            participants.map { p in
                guard let entry = round.points.first(where: { $0.participantID == p.id }) else { return "" }
                if isRaw {
                    guard let raw = entry.rawScore else { return "" }
                    return "\(raw)"
                }
                return "\(entry.point)"
            }
        }
        input.yakitori = sorted.map { round in
            participants.map { p in
                round.points.first { $0.participantID == p.id }?.isYakitori ?? false
            }
        }
        input.busters = sorted.map { round in
            participants.map { p in
                round.points.first { $0.participantID == p.id }?.busterID
            }
        }
        input.chips = participants.map { p in
            let c = session.chipCount(for: p.id)
            return session.chips.contains { $0.participantID == p.id } && c != 0 ? "\(c)" : ""
        }
        input.normalize(playerCount: n)
        return input
    }

    // MARK: 計算

    /// その回戦の精算結果。素点がそろっていて合計が合うときだけ返す。
    static func settlement(row: [String],
                           yakitori: [Bool],
                           busters: [UUID?],
                           session: TableSession) -> [RoundSettlement]? {
        guard session.inputMode == .rawScore else { return nil }
        let participants = session.participants
        let n = participants.count
        let values = row.map { Int($0) }
        guard values.count == n, ScoreCalculator.isRawRoundComplete(values) else { return nil }
        let scores = values.compactMap { $0 }
        guard scores.count == n else { return nil }
        let rule = session.rule
        guard ScoreCalculator.isRawRoundBalanced(scores, rule: rule, playerCount: n) else { return nil }
        return ScoreCalculator.settle(participantIDs: participants.map(\.id),
                                      rawScores: scores,
                                      yakitoriFlags: yakitori,
                                      busterIDs: busters,
                                      rule: rule)
    }

    /// 1回戦ぶんの保存用データを作る。
    /// 素点モードは算出ポイントと素点の両方を、ポイントモードは入力値をそのまま保存する。
    static func points(row: [String],
                       yakitori: [Bool],
                       busters: [UUID?],
                       session: TableSession) -> [PlayerRoundPoint] {
        let participants = session.participants
        let n = participants.count

        if session.inputMode == .rawScore {
            let settled = settlement(row: row, yakitori: yakitori, busters: busters, session: session)
            return participants.indices.map { i in
                let raw = i < row.count ? Int(row[i]) : nil
                let s = settled?[safe: i]
                return PlayerRoundPoint(participantID: participants[i].id,
                                        rank: s?.rank ?? 0,
                                        point: s?.total ?? 0,
                                        isAutoCalculated: s != nil,
                                        rawScore: raw,
                                        isYakitori: i < yakitori.count ? yakitori[i] : false,
                                        busterID: i < busters.count ? busters[i] : nil)
            }
        }

        let vals = (0..<n).map { c -> Int in c < row.count ? (Int(row[c]) ?? 0) : 0 }
        let order = vals.indices.sorted { vals[$0] > vals[$1] }
        var rankOf = Array(repeating: 0, count: n)
        for (pos, idx) in order.enumerated() { rankOf[idx] = pos + 1 }
        return participants.indices.map { i in
            PlayerRoundPoint(participantID: participants[i].id,
                             rank: rankOf[i], point: vals[i], isAutoCalculated: false)
        }
    }

    // MARK: 保存

    /// 入力内容をセッションへ反映して保存する。
    /// 回戦は作り直さず既存レコードを更新する（入力のたびに削除・再作成しない）。
    /// 保存できたら true。
    @discardableResult
    static func save(_ input: ScoreTableInput,
                     to session: TableSession,
                     context: ModelContext) -> Bool {
        var input = input
        input.normalize(playerCount: session.participants.count)

        let existing = session.sortedRounds
        for (i, row) in input.rows.enumerated() {
            let pts = points(row: row,
                             yakitori: input.yakitori[i],
                             busters: input.busters[i],
                             session: session)
            if i < existing.count {
                let round = existing[i]
                if round.roundNumber != i + 1 { round.roundNumber = i + 1 }
                if round.points != pts { round.points = pts }
            } else {
                let rr = RoundResult(roundNumber: i + 1, points: pts)
                rr.session = session
                session.rounds.append(rr)
                context.insert(rr)
            }
        }

        // 行が減った分は削除する。
        if existing.count > input.rows.count {
            for extra in existing[input.rows.count...] {
                session.rounds.removeAll { $0.id == extra.id }
                context.delete(extra)
            }
        }

        session.chips = session.participants.enumerated().map { idx, p in
            let count = idx < input.chips.count ? (Int(input.chips[idx]) ?? 0) : 0
            return ChipEntry(participantID: p.id, chipCount: count)
        }
        session.updatedAt = Date()

        do {
            try context.save()
            return true
        } catch {
            return false
        }
    }
}
