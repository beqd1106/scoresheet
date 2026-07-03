import Foundation

/// 卓の結果を CSV 文字列に変換する。実金額表現は一切含めない。
enum CSVExporter {

    static func makeCSV(for session: TableSession) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = []
        lines.append("スコアシート エクスポート")
        lines.append("日付,\(df.string(from: session.date))")
        lines.append("種別,\(session.gameType.displayName)")
        lines.append("チップ係数,1枚=\(fmt(session.chipPointCoefficient))ポイント")
        lines.append("")

        let parts = session.participants

        // 回戦テーブル
        var header = ["回戦"]
        header += parts.map { escape($0.name) }
        header.append("合計チェック")
        lines.append(header.joined(separator: ","))

        for round in session.sortedRounds {
            var row = ["\(round.roundNumber)回戦"]
            row += parts.map { "\(round.point(for: $0.id).signedPointString)" }
            row.append("\(round.pointSum)")
            lines.append(row.joined(separator: ","))
        }
        lines.append("")

        // 最終集計テーブル
        lines.append("順位,プレイヤー,対局ポイント,チップ枚数,チップポイント,総合ポイント,トップ回数,平均順位")
        for r in ScoreCalculator.finalResults(for: session) {
            let chipCount = session.chipCount(for: r.participantID)
            let cols = [
                "\(r.rank)",
                escape(r.name),
                "\(r.roundPointTotal.signedPointString)",
                "\(chipCount.signedPointString)",
                "\(r.chipPointTotal.signedPointString)",
                "\(r.grandTotal.signedPointString)",
                "\(r.topCount)",
                String(format: "%.2f", r.averageRank)
            ]
            lines.append(cols.joined(separator: ","))
        }

        // BOM を付けて Excel で文字化けしないようにする
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }

    /// 一時ファイルへ書き出して URL を返す（共有シート用）。
    static func writeTempFile(for session: TableSession) -> URL? {
        let csv = makeCSV(for: session)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        let name = "scoresheet_\(df.string(from: session.date)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try csv.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private static func fmt(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
