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

    // MARK: - 最終集計

    /// セッション全体の最終集計を算出し、総合ポイント降順で順位付けして返す。
    static func finalResults(for session: TableSession) -> [FinalResult] {
        let coeff = session.chipPointCoefficient

        var partials: [FinalResult] = session.participants.map { p in
            let roundTotal = session.roundTotal(for: p.id)
            let chipCount = session.chipCount(for: p.id)
            let chipTotal = chipPoint(count: chipCount, coefficient: coeff)

            let ranks: [Int] = session.rounds.compactMap { $0.rank(for: p.id) }
            let topCount = ranks.filter { $0 == 1 }.count
            let avgRank = ranks.isEmpty ? 0 : Double(ranks.reduce(0, +)) / Double(ranks.count)

            return FinalResult(
                participantID: p.id,
                name: p.name,
                colorHex: p.colorHex,
                roundPointTotal: roundTotal,
                chipPointTotal: chipTotal,
                grandTotal: roundTotal + chipTotal,
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
}
