import Foundation
import Observation

/// 最終結果のソートと出力用テキストを提供。
@Observable
final class FinalResultViewModel {
    enum SortKey: String, CaseIterable, Identifiable {
        case grandTotal = "総合ポイント"
        case roundTotal = "対局ポイント"
        case topCount = "トップ回数"
        case averageRank = "平均順位"
        var id: String { rawValue }
    }

    let session: TableSession
    var sortKey: SortKey = .grandTotal

    init(session: TableSession) { self.session = session }

    var results: [FinalResult] {
        let base = ScoreCalculator.finalResults(for: session)   // 総合順で rank 付与済み
        switch sortKey {
        case .grandTotal:  return base
        case .roundTotal:  return base.sorted { $0.roundPointTotal > $1.roundPointTotal }
        case .topCount:    return base.sorted { $0.topCount > $1.topCount }
        case .averageRank: return base.sorted { $0.averageRank < $1.averageRank }
        }
    }

    func chipCount(for id: UUID) -> Int { session.chipCount(for: id) }

    /// コピー用テキスト（プレーン）。
    var shareText: String {
        var lines: [String] = ["【\(session.gameType.displayName) 結果】"]
        for r in ScoreCalculator.finalResults(for: session) {
            lines.append("\(r.rank)位 \(r.name)  総合\(r.grandTotal.signedPointString)（対局\(r.roundPointTotal.signedPointString) / チップ\(r.chipPointTotal.signedPointString)）")
        }
        return lines.joined(separator: "\n")
    }
}
