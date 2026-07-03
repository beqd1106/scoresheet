import Foundation
import SwiftData
import Observation

/// 卓スコア画面の派生値を提供（累計の即時計算）。
@Observable
final class TableScoreViewModel {
    let session: TableSession
    init(session: TableSession) { self.session = session }

    /// 参加者を現在の累計（対局のみ）降順で並べたタプル。
    var standings: [(participant: Participant, total: Int)] {
        session.participants
            .map { ($0, session.roundTotal(for: $0.id)) }
            .sorted { $0.1 > $1.1 }
    }

    var roundCount: Int { session.rounds.count }
    var hasChips: Bool { session.chips.contains { $0.chipCount != 0 } }
}

/// ホーム画面用（直近の卓の要約）。ロジックは軽量。
@Observable
final class HomeViewModel {
    func summary(for session: TableSession) -> String {
        let names = session.participants.map(\.name).joined(separator: "・")
        return "\(session.gameType.displayName)・\(session.rounds.count)回戦　\(names)"
    }
}

/// 履歴画面用の並び替え・整形。
@Observable
final class HistoryViewModel {
    func dateText(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd HH:mm"
        return df.string(from: date)
    }
    func topName(of session: TableSession) -> String? {
        ScoreCalculator.finalResults(for: session).first?.name
    }
}

/// 設定画面のよく使うポイント編集の補助。
@Observable
final class SettingsViewModel {
    func parseQuickPoints(_ raw: String) -> [Int] {
        raw.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }
    func encodeQuickPoints(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ",")
    }
}
