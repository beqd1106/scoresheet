import Foundation
import SwiftData

// MARK: - ライブ共有で送る中身

/// 記録係のスマホから近くのスマホへ送るメッセージ。
enum LiveMessage: Codable {
    /// 卓の最新の内容（入力のたびに丸ごと送る）。
    case snapshot(LiveSnapshot)
    /// 記録係が共有をやめた。
    case ended
}

/// ある時点の卓の内容。保存形式はバックアップと共通にして、
/// 見ている側でもそのまま自分の記録として取り込めるようにしている。
struct LiveSnapshot: Codable, Equatable {
    var session: SessionBackup
    var sentAt: Date
}

enum LiveWire {
    static func encode(_ message: LiveMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(message)
    }

    static func decode(_ data: Data) throws -> LiveMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LiveMessage.self, from: data)
    }
}

// MARK: - 卓 ⇄ 保存形式の変換と取り込み

/// 卓（TableSession）と保存形式（SessionBackup）を行き来させる。
/// バックアップの復元と、ライブ共有の受信・保存で共通に使う。
enum LiveSessionStore {

    static func backup(of s: TableSession) -> SessionBackup {
        SessionBackup(
            id: s.id, date: s.date, gameTypeRaw: s.gameTypeRaw,
            participants: s.participants, chips: s.chips,
            pointCoefficientPer1000: s.pointCoefficientPer1000,
            chipPointCoefficient: s.chipPointCoefficient,
            tags: s.tags, memo: s.memo,
            createdAt: s.createdAt, updatedAt: s.updatedAt,
            inputModeRaw: s.inputModeRaw, ruleJSON: s.ruleJSON,
            rounds: s.sortedRounds.map {
                RoundBackup(id: $0.id, roundNumber: $0.roundNumber,
                            points: $0.points, memo: $0.memo, createdAt: $0.createdAt)
            }
        )
    }

    /// 保存形式から卓を作って context に入れる（保存はしない）。
    @discardableResult
    static func insert(_ s: SessionBackup, into context: ModelContext) -> TableSession {
        let session = TableSession(gameType: GameType(rawValue: s.gameTypeRaw) ?? .yonma,
                                   participants: s.participants)
        session.id = s.id
        session.date = s.date
        session.chips = s.chips
        session.pointCoefficientPer1000 = s.pointCoefficientPer1000
        session.chipPointCoefficient = s.chipPointCoefficient
        session.tags = s.tags
        session.memo = s.memo
        session.createdAt = s.createdAt
        session.updatedAt = s.updatedAt
        session.inputModeRaw = s.inputModeRaw
        session.ruleJSON = s.ruleJSON
        context.insert(session)

        for r in s.rounds {
            let round = RoundResult(roundNumber: r.roundNumber, points: r.points, memo: r.memo)
            round.id = r.id
            round.createdAt = r.createdAt
            round.session = session
            session.rounds.append(round)
            context.insert(round)
        }
        return session
    }

    /// 保存の結果。
    enum SaveOutcome: Equatable {
        case added      // 新しく過去のゲームに加えた
        case updated    // 前に保存した同じ卓を最新の内容に置き換えた
    }

    /// 共有で見ていた卓を、自分のスマホの記録として保存する。
    ///
    /// 参加者は記録係のスマホの名簿IDのままなので、自分の名簿とつなぎ直す。
    /// 1. 同じIDのプレイヤーが名簿にいればそのまま
    /// 2. 同じ名前のプレイヤーがいれば、そのプレイヤーとして記録する（プレイヤー別成績に入る）
    /// 3. どちらもいなければ名簿に追加する（IDは記録係側と同じにして、次回以降も同じ人として扱う）
    @discardableResult
    static func saveCopy(_ snapshot: SessionBackup, into context: ModelContext) throws -> SaveOutcome {
        var players = (try? context.fetch(FetchDescriptor<Player>())) ?? []
        var idMap: [UUID: UUID] = [:]

        for p in snapshot.participants {
            if players.contains(where: { $0.id == p.id }) {
                idMap[p.id] = p.id
                continue
            }
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let same = players.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == name
            }) {
                idMap[p.id] = same.id
                continue
            }
            let added = Player(name: p.name, colorHex: p.colorHex)
            added.id = p.id
            context.insert(added)
            players.append(added)
            idMap[p.id] = p.id
        }

        let remapped = remap(snapshot, with: idMap)

        // 同じ卓を前に保存していれば置き換える（何度保存しても1件のまま）。
        let targetID = snapshot.id
        let existing = (try? context.fetch(FetchDescriptor<TableSession>(
            predicate: #Predicate { $0.id == targetID }
        ))) ?? []
        for old in existing { context.delete(old) }

        insert(remapped, into: context)
        try context.save()
        return existing.isEmpty ? .added : .updated
    }

    /// 参加者IDを付け替えた保存形式を返す。名前と色は自分の名簿ではなく卓の記録のまま残す。
    static func remap(_ s: SessionBackup, with idMap: [UUID: UUID]) -> SessionBackup {
        func m(_ id: UUID) -> UUID { idMap[id] ?? id }
        var out = s
        out.participants = s.participants.map {
            Participant(id: m($0.id), name: $0.name, colorHex: $0.colorHex)
        }
        out.chips = s.chips.map {
            ChipEntry(id: $0.id, participantID: m($0.participantID), chipCount: $0.chipCount)
        }
        out.rounds = s.rounds.map { r in
            var round = r
            round.points = r.points.map { pt in
                var p = pt
                p.participantID = m(pt.participantID)
                p.busterID = pt.busterID.map(m)
                return p
            }
            return round
        }
        return out
    }
}
