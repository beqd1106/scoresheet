import Foundation
import Observation

/// チップ入力の状態。ゲーム終了後に全員分をまとめて入力。
@Observable
final class ChipInputViewModel {
    let participants: [Participant]
    let coefficient: Double
    var counts: [UUID: Int]

    init(session: TableSession) {
        self.participants = session.participants
        self.coefficient = session.chipPointCoefficient
        var initial: [UUID: Int] = [:]
        for c in session.chips { initial[c.participantID] = c.chipCount }
        self.counts = initial
    }

    func count(for id: UUID) -> Int { counts[id] ?? 0 }

    func setCount(_ v: Int, for id: UUID) { counts[id] = v }

    func adjust(_ delta: Int, for id: UUID) { counts[id] = count(for: id) + delta }

    /// チップポイント（枚数 × 係数）。
    func chipPoint(for id: UUID) -> Int {
        ScoreCalculator.chipPoint(count: count(for: id), coefficient: coefficient)
    }

    /// 全員のチップ枚数合計（0 が理想だが強制はしない。目安表示用）。
    var totalCount: Int { participants.reduce(0) { $0 + count(for: $1.id) } }

    /// セッションへ反映するためのエントリ配列。
    func buildChips() -> [ChipEntry] {
        participants.map { ChipEntry(participantID: $0.id, chipCount: count(for: $0.id)) }
    }
}
