import Foundation
import SwiftData

/// スコア表の入力内容（画面の @State に対応する値）。
struct ScoreTableInput: Equatable {
    var rows: [[String]] = []        // rows[回戦][プレイヤー] = 入力テキスト
    var yakitori: [[Bool]] = []      // ヤキトリ該当
    var busters: [[UUID?]] = []      // その人を飛ばした人
    var chips: [String] = []         // チップ枚数
    var sitOut: [UUID?] = []         // 回し打ちの抜け番（回戦ごと・回し打ちでなければ nil）

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
        while sitOut.count < rows.count { sitOut.append(nil) }
        sitOut = Array(sitOut.prefix(rows.count))
        for i in yakitori.indices where yakitori[i].count != n {
            yakitori[i] = Array(repeating: false, count: n)
        }
        for i in busters.indices where busters[i].count != n {
            busters[i] = Array(repeating: nil, count: n)
        }
        if chips.count != n { chips = Array(repeating: "", count: n) }
    }

    /// 回し打ちで抜け番が決まっていない回戦に、前の回戦の次の席の人を入れる。
    /// 最初の回戦は最後の席の人。あとから1タップで変えられる前提の初期値。
    mutating func fillDefaultSitOut(participants: [Participant]) {
        guard !participants.isEmpty else { return }
        let ids = participants.map(\.id)
        var previous: UUID?
        for i in sitOut.indices {
            if let current = sitOut[i], ids.contains(current) {
                previous = current
                continue
            }
            let next = RoundPersistence.nextSitOut(after: previous, participants: participants)
            sitOut[i] = next
            previous = next
        }
    }
}

/// スコア表の読み込み・保存・その回戦の計算をまとめた置き場。
/// 画面に書いていると自動テストで守れないため、ここへ切り出している。
enum RoundPersistence {

    // MARK: 抜け番

    /// 前の回戦の抜け番の次の席の人。前がなければ最後の席の人。
    static func nextSitOut(after previous: UUID?, participants: [Participant]) -> UUID? {
        guard let last = participants.last else { return nil }
        guard let previous, let idx = participants.firstIndex(where: { $0.id == previous }) else { return last.id }
        return participants[(idx + 1) % participants.count].id
    }

    /// その回戦で卓についた人の列番号。回し打ちでは抜け番の人を除く。
    static func activeIndices(sitOut: UUID?, session: TableSession) -> [Int] {
        let participants = session.participants
        guard session.isRotation else { return Array(participants.indices) }
        return participants.indices.filter { participants[$0].id != sitOut }
    }

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
        input.sitOut = sorted.map { session.sitOutID(in: $0) }
        input.normalize(playerCount: n)
        if session.isRotation { input.fillDefaultSitOut(participants: participants) }
        return input
    }

    // MARK: 計算

    /// その回戦の精算結果。素点がそろっていて合計が合うときだけ返す。
    /// 返り値は卓についた人だけ（回し打ちの抜け番は含まない）。参照は participantID で行う。
    static func settlement(row: [String],
                           yakitori: [Bool],
                           busters: [UUID?],
                           sitOut: UUID? = nil,
                           session: TableSession) -> [RoundSettlement]? {
        guard session.inputMode == .rawScore else { return nil }
        let participants = session.participants
        guard row.count == participants.count else { return nil }
        let active = activeIndices(sitOut: sitOut, session: session)
        guard active.count == session.seatCount else { return nil }
        let values = active.map { Int(row[$0]) }
        guard ScoreCalculator.isRawRoundComplete(values) else { return nil }
        let scores = values.compactMap { $0 }
        let rule = session.rule
        guard ScoreCalculator.isRawRoundBalanced(scores, rule: rule, playerCount: active.count) else { return nil }
        let activeIDs = Set(active.map { participants[$0].id })
        return ScoreCalculator.settle(participantIDs: active.map { participants[$0].id },
                                      rawScores: scores,
                                      yakitoriFlags: active.map { $0 < yakitori.count ? yakitori[$0] : false },
                                      busterIDs: active.map { i -> UUID? in
                                          // 抜け番の人は飛ばせないので、指定されていても無視する。
                                          guard i < busters.count, let b = busters[i], activeIDs.contains(b) else { return nil }
                                          return b
                                      },
                                      rule: rule)
    }

    /// 1回戦ぶんの保存用データを作る。
    /// 素点モードは算出ポイントと素点の両方を、ポイントモードは入力値をそのまま保存する。
    /// 回し打ちの抜け番の人は含めない（その回戦は打っていないため）。
    static func points(row: [String],
                       yakitori: [Bool],
                       busters: [UUID?],
                       sitOut: UUID? = nil,
                       session: TableSession) -> [PlayerRoundPoint] {
        let participants = session.participants
        let active = activeIndices(sitOut: sitOut, session: session)

        if session.inputMode == .rawScore {
            let settled = settlement(row: row, yakitori: yakitori, busters: busters,
                                     sitOut: sitOut, session: session)
            return active.map { i in
                let raw = i < row.count ? Int(row[i]) : nil
                let s = settled?.first { $0.participantID == participants[i].id }
                return PlayerRoundPoint(participantID: participants[i].id,
                                        rank: s?.rank ?? 0,
                                        point: s?.total ?? 0,
                                        isAutoCalculated: s != nil,
                                        rawScore: raw,
                                        isYakitori: i < yakitori.count ? yakitori[i] : false,
                                        busterID: i < busters.count ? busters[i] : nil)
            }
        }

        let vals = active.map { c -> Int in c < row.count ? (Int(row[c]) ?? 0) : 0 }
        let order = vals.indices.sorted { vals[$0] > vals[$1] }
        var rankOf = Array(repeating: 0, count: vals.count)
        for (pos, idx) in order.enumerated() { rankOf[idx] = pos + 1 }
        return active.indices.map { k in
            PlayerRoundPoint(participantID: participants[active[k]].id,
                             rank: rankOf[k], point: vals[k], isAutoCalculated: false)
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
        if session.isRotation { input.fillDefaultSitOut(participants: session.participants) }

        let existing = session.sortedRounds
        for (i, row) in input.rows.enumerated() {
            var pts = points(row: row,
                             yakitori: input.yakitori[i],
                             busters: input.busters[i],
                             sitOut: input.sitOut[i],
                             session: session)
            // ポイント入力でも、CSV取り込みなどで素点を持っている回戦がある。
            // ポイントが変わっていない人の素点は消さずに残す（トビ率などの集計に使うため）。
            if session.inputMode == .point, i < existing.count {
                let old = existing[i].points
                for k in pts.indices {
                    if let prev = old.first(where: { $0.participantID == pts[k].participantID }),
                       prev.point == pts[k].point {
                        pts[k].rawScore = prev.rawScore
                    }
                }
            }
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
