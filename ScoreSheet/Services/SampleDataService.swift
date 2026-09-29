import Foundation
import SwiftData

/// サンプルデータ。以前は初回起動時に投入していたが、1.2.0 から投入をやめた。
/// 卓の生成関数はテストで使うので残している。
enum SampleDataService {

    static let legacySampleMemos: Set<String> = ["四麻サンプル", "三麻サンプル"]
    static let legacySampleNames: Set<String> = ["あきら", "ばんり", "ちひろ", "だいご"]
    static let legacyCleanupKey = "didRemoveLegacySamples"

    /// 以前のバージョンが入れたサンプルの卓と名簿を一度だけ取り除く。
    /// 回戦を足したり参加者を変えた卓、ほかの卓でも使っている名簿は利用者のデータとみなして残す。
    static func removeLegacySamplesIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: legacyCleanupKey) else { return }

        let sessions = (try? context.fetch(FetchDescriptor<TableSession>())) ?? []
        let samples = sessions.filter(isUntouchedSample)
        let sampleParticipantIDs = Set(samples.flatMap { $0.participants.map(\.id) })
        let usedElsewhere = Set(sessions.filter { s in !samples.contains { $0 === s } }
            .flatMap { $0.participants.map(\.id) })

        samples.forEach { context.delete($0) }
        let players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        for player in players
        where sampleParticipantIDs.contains(player.id) && !usedElsewhere.contains(player.id)
            && legacySampleNames.contains(player.name) {
            context.delete(player)
        }

        do {
            try context.save()
            defaults.set(true, forKey: legacyCleanupKey)
        } catch {
            // 保存できなかったときは次回起動でもう一度試す
            context.rollback()
        }
    }

    private static func isUntouchedSample(_ session: TableSession) -> Bool {
        let expectedCount = session.gameType == .yonma ? 4 : 3
        return legacySampleMemos.contains(session.memo)
            && session.rounds.count == 3
            && session.participants.count == expectedCount
            && session.participants.allSatisfy { legacySampleNames.contains($0.name) }
    }

    // MARK: 四麻サンプル（3回戦 + チップ）

    static func makeYonmaSample(_ a: Player, _ b: Player, _ c: Player, _ d: Player) -> TableSession {
        let pa = a.participant, pb = b.participant, pc = c.participant, pd = d.participant
        let session = TableSession(gameType: .yonma,
                                   participants: [pa, pb, pc, pd],
                                   chipPointCoefficient: 5)

        // R1: 1着B+40 / 2着A+5 / 3着C-15 / 4着D-30
        session.rounds.append(round(1, [
            (pb.id, 1, 40, true), (pa.id, 2, 5, false), (pc.id, 3, -15, false), (pd.id, 4, -30, false)
        ]))
        // R2: 1着C+15 / 2着D+10 / 3着B-5 / 4着A-20
        session.rounds.append(round(2, [
            (pc.id, 1, 15, true), (pd.id, 2, 10, false), (pb.id, 3, -5, false), (pa.id, 4, -20, false)
        ]))
        // R3: 1着D+20 / 2着B+8 / 3着A-3 / 4着C-25
        session.rounds.append(round(3, [
            (pd.id, 1, 20, true), (pb.id, 2, 8, false), (pa.id, 3, -3, false), (pc.id, 4, -25, false)
        ]))

        // チップ（係数5）: A+2, B+3, C-2, D-3
        session.chips = [
            ChipEntry(participantID: pa.id, chipCount: 2),
            ChipEntry(participantID: pb.id, chipCount: 3),
            ChipEntry(participantID: pc.id, chipCount: -2),
            ChipEntry(participantID: pd.id, chipCount: -3),
        ]
        session.memo = "四麻サンプル"
        return session
    }

    // MARK: 三麻サンプル（3回戦 + チップ）

    static func makeSanmaSample(_ x: Player, _ y: Player, _ z: Player) -> TableSession {
        let px = x.participant, py = y.participant, pz = z.participant
        let session = TableSession(gameType: .sanma,
                                   participants: [px, py, pz],
                                   chipPointCoefficient: 5)

        // R1: 1着X+30 / 2着Y-5 / 3着Z-25
        session.rounds.append(round(1, [
            (px.id, 1, 30, true), (py.id, 2, -5, false), (pz.id, 3, -25, false)
        ]))
        // R2: 1着Z+25 / 2着X+10 / 3着Y-35
        session.rounds.append(round(2, [
            (pz.id, 1, 25, true), (px.id, 2, 10, false), (py.id, 3, -35, false)
        ]))
        // R3: 1着Y+15 / 2着Z+5 / 3着X-20
        session.rounds.append(round(3, [
            (py.id, 1, 15, true), (pz.id, 2, 5, false), (px.id, 3, -20, false)
        ]))

        // チップ（係数5）: X-1, Y+3, Z-2
        session.chips = [
            ChipEntry(participantID: px.id, chipCount: -1),
            ChipEntry(participantID: py.id, chipCount: 3),
            ChipEntry(participantID: pz.id, chipCount: -2),
        ]
        session.memo = "三麻サンプル"
        return session
    }

    private static func round(_ n: Int, _ rows: [(UUID, Int, Int, Bool)]) -> RoundResult {
        let points = rows.map {
            PlayerRoundPoint(participantID: $0.0, rank: $0.1, point: $0.2, isAutoCalculated: $0.3)
        }
        return RoundResult(roundNumber: n, points: points)
    }
}
