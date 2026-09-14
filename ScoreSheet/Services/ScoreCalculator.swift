import Foundation

/// スコア計算ロジック（View から分離した純粋関数群）。
enum ScoreCalculator {

    // MARK: - 回戦

    /// トップ以外のポイント合計 × -1 でトップポイントを算出。
    /// 例) 四麻 2着+5,3着-15,4着-30 → トップ = -(5-15-30) = +40
    static func autoTopPoint(others: [Int]) -> Int {
        -others.reduce(0, +)
    }

    /// 全員のポイント合計が 0 か検証。
    static func isRoundBalanced(_ points: [Int]) -> Bool {
        points.reduce(0, +) == 0
    }

    // MARK: - チップ

    /// チップポイント = 枚数 × 1枚あたり係数（四捨五入で整数化）。
    static func chipPoint(count: Int, coefficient: Double) -> Int {
        Int((Double(count) * coefficient).rounded())
    }

    // MARK: - 1000点係数（補助機能）

    /// 持ち点差からポイントを算出したい場合の補助。
    /// scoreDiffFromOrigin: 原点（例 25000）との差分。
    /// per1000: 1000点あたりのポイント係数。
    static func pointFromScore(scoreDiffFromOrigin: Int, per1000: Double) -> Int {
        Int((Double(scoreDiffFromOrigin) / 1000.0 * per1000).rounded())
    }

    // MARK: - 素点から自動計算

    /// 素点（終局時の持ち点）からその回戦のポイントを算出する。
    /// 返り値は入力と同じ並び順。合計は必ず 0（オカ・端数はトップで調整）。
    ///
    /// 計算順：
    ///   1) 順位を決める（点数の高い順・同点は席順が上の人が上位）
    ///   2) (持ち点 − 返し点) ÷ 1000 を端数処理
    ///   3) 順位点（ウマ）を加算
    ///   4) トビ・ヤキトリ・クビの罰符を授受
    ///   5) 合計が 0 になるよう残り（＝オカ＋端数）をトップに寄せる
    static func settle(participantIDs: [UUID],
                       rawScores: [Int],
                       yakitoriFlags: [Bool],
                       rule: GameRule) -> [RoundSettlement] {
        let n = participantIDs.count
        guard n > 0, rawScores.count == n else { return [] }
        let yakitori = yakitoriFlags.count == n ? yakitoriFlags : Array(repeating: false, count: n)

        // 1) 順位（同点は席順＝配列の前にいる人を上位とする）
        let order = (0..<n).sorted { a, b in
            rawScores[a] == rawScores[b] ? a < b : rawScores[a] > rawScores[b]
        }
        var rankOf = Array(repeating: 0, count: n)
        for (pos, idx) in order.enumerated() { rankOf[idx] = pos + 1 }
        let topIndex = order[0]

        // 2) 素点差
        let base = (0..<n).map { i in
            rule.rounding.apply(Double(rawScores[i] - rule.returnPoints) / 1000.0)
        }

        // 3) ウマ
        let uma = rule.normalizedUma(playerCount: n)
        let umaPt = (0..<n).map { uma[rankOf[$0] - 1] }

        // 4) 罰符
        var penalty = Array(repeating: 0, count: n)
        let isTobi = (0..<n).map { i in
            guard rule.tobiEnabled else { return false }
            return rawScores[i] < 0 || (rule.tobiIncludesZero && rawScores[i] == 0)
        }
        applyPenalty(&penalty, payers: (0..<n).filter { isTobi[$0] },
                     amount: rule.tobiPenalty, payee: rule.tobiPayee, topIndex: topIndex, count: n)

        let isYakitori = (0..<n).map { rule.yakitoriEnabled && yakitori[$0] }
        applyPenalty(&penalty, payers: (0..<n).filter { isYakitori[$0] },
                     amount: rule.yakitoriPenalty, payee: rule.yakitoriPayee, topIndex: topIndex, count: n)

        if rule.kubiEnabled {
            applyPenalty(&penalty, payers: (0..<n).filter { rankOf[$0] == n },
                         amount: rule.kubiPenalty, payee: rule.kubiPayee, topIndex: topIndex, count: n)
        }

        // 5) オカ＋端数をトップへ
        let subtotal = (0..<n).map { base[$0] + umaPt[$0] + penalty[$0] }
        let residue = -subtotal.reduce(0, +)

        return (0..<n).map { i in
            RoundSettlement(participantID: participantIDs[i],
                            rank: rankOf[i],
                            basePoint: base[i],
                            umaPoint: umaPt[i],
                            penaltyPoint: penalty[i],
                            okaPoint: i == topIndex ? residue : 0,
                            isTobi: isTobi[i],
                            isYakitori: isYakitori[i])
        }
    }

    /// 罰符の授受を penalty 配列へ加算する。
    /// 山分けで割り切れない分はここでは配らず、最後のトップ調整で吸収させる。
    private static func applyPenalty(_ penalty: inout [Int],
                                     payers: [Int],
                                     amount: Int,
                                     payee: PenaltyPayee,
                                     topIndex: Int,
                                     count: Int) {
        guard !payers.isEmpty, amount != 0 else { return }
        let pot = amount * payers.count
        for i in payers { penalty[i] -= amount }

        switch payee {
        case .top:
            penalty[topIndex] += pot
        case .others:
            let receivers = (0..<count).filter { !payers.contains($0) }
            guard !receivers.isEmpty else { return }
            let each = pot / receivers.count
            for i in receivers { penalty[i] += each }
        }
    }

    /// 素点入力が全員そろっているか。
    static func isRawRoundComplete(_ scores: [Int?]) -> Bool {
        !scores.isEmpty && scores.allSatisfy { $0 != nil }
    }

    /// 素点合計が想定どおりか（＝入力ミス検知）。
    static func isRawRoundBalanced(_ scores: [Int], rule: GameRule, playerCount: Int) -> Bool {
        scores.reduce(0, +) == rule.expectedTotalScore(playerCount: playerCount)
    }

    // MARK: - 最終集計

    /// 対局ポイント（各回の入力合計）を 1000点係数で換算した pt。
    static func roundPoint(rawTotal: Int, per1000: Double) -> Int {
        Int((Double(rawTotal) * per1000).rounded())
    }

    /// セッション全体の最終集計を算出し、総合ポイント降順で順位付けして返す。
    /// 総合ポイント = 対局ポイント合計 × 1000点係数 + チップ枚数 × チップ係数。
    static func finalResults(for session: TableSession) -> [FinalResult] {
        let coeff = session.chipPointCoefficient
        let per1000 = session.pointCoefficientPer1000

        var partials: [FinalResult] = session.participants.map { p in
            let rawTotal = session.roundTotal(for: p.id)
            let roundPt = roundPoint(rawTotal: rawTotal, per1000: per1000)
            let chipCount = session.chipCount(for: p.id)
            let chipTotal = chipPoint(count: chipCount, coefficient: coeff)

            let ranks: [Int] = session.rounds.compactMap { $0.rank(for: p.id) }
            let topCount = ranks.filter { $0 == 1 }.count
            let avgRank = ranks.isEmpty ? 0 : Double(ranks.reduce(0, +)) / Double(ranks.count)

            return FinalResult(
                participantID: p.id,
                name: p.name,
                colorHex: p.colorHex,
                roundPointTotal: rawTotal,   // 各回入力の生合計（合計行に表示）
                chipPointTotal: chipTotal,
                grandTotal: roundPt + chipTotal,
                topCount: topCount,
                averageRank: avgRank,
                rank: 0
            )
        }

        // 総合降順。同点は 対局ポイント → トップ回数 → 平均順位(昇順) で決定。
        partials.sort { a, b in
            if a.grandTotal != b.grandTotal { return a.grandTotal > b.grandTotal }
            if a.roundPointTotal != b.roundPointTotal { return a.roundPointTotal > b.roundPointTotal }
            if a.topCount != b.topCount { return a.topCount > b.topCount }
            return a.averageRank < b.averageRank
        }

        for i in partials.indices { partials[i].rank = i + 1 }
        return partials
    }

    // MARK: - 推移グラフ用

    /// 回戦ごとの累計ポイント（対局のみ・チップ除く）を各プレイヤー分。
    /// roundNumber 0 = 開始点(0)。以降は各回終了時点の累計。
    static func cumulativeSeries(for session: TableSession) -> [CumulativePoint] {
        let rounds = session.sortedRounds
        var out: [CumulativePoint] = []
        for p in session.participants {
            var running = 0
            out.append(CumulativePoint(participantID: p.id, name: p.name, colorHex: p.colorHex,
                                       roundNumber: 0, cumulative: 0))
            for r in rounds {
                running += r.point(for: p.id)
                out.append(CumulativePoint(participantID: p.id, name: p.name, colorHex: p.colorHex,
                                           roundNumber: r.roundNumber, cumulative: running))
            }
        }
        return out
    }

    /// 各プレイヤーの順位分布（rank -> 回数）。
    static func rankDistribution(for session: TableSession) -> [UUID: [Int: Int]] {
        var dist: [UUID: [Int: Int]] = [:]
        for p in session.participants {
            var counts: [Int: Int] = [:]
            for r in session.rounds {
                if let rank = r.rank(for: p.id) { counts[rank, default: 0] += 1 }
            }
            dist[p.id] = counts
        }
        return dist
    }
}

/// 累計推移グラフの1点。
struct CumulativePoint: Identifiable {
    let id = UUID()
    let participantID: UUID
    let name: String
    let colorHex: String
    let roundNumber: Int
    let cumulative: Int
}
