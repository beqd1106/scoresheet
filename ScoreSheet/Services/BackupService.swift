import Foundation
import SwiftData

// MARK: - バックアップの入れ物（保存形式）

/// 書き出しファイルの中身。将来フォーマットを変えても読めるよう version を持たせる。
struct BackupFile: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var players: [PlayerBackup] = []
    var sessions: [SessionBackup] = []
}

struct PlayerBackup: Codable {
    var id: UUID
    var name: String
    var colorHex: String
    var iconName: String
    var createdAt: Date
}

struct SessionBackup: Codable {
    var id: UUID
    var date: Date
    var gameTypeRaw: String
    var participants: [Participant]
    var chips: [ChipEntry]
    var pointCoefficientPer1000: Double
    var chipPointCoefficient: Double
    var tags: [String]
    var memo: String
    var createdAt: Date
    var updatedAt: Date
    var inputModeRaw: String
    var ruleJSON: String
    var rounds: [RoundBackup]
}

struct RoundBackup: Codable {
    var id: UUID
    var roundNumber: Int
    var points: [PlayerRoundPoint]
    var memo: String
    var createdAt: Date
}

// MARK: - 書き出し・読み込み

/// 端末内のデータをファイルに書き出し／読み戻しする。
/// 端末の故障・機種変更に備えた手動バックアップ用。
enum BackupService {

    static func makeBackup(players: [Player], sessions: [TableSession]) -> BackupFile {
        BackupFile(
            version: 1,
            exportedAt: Date(),
            players: players.map {
                PlayerBackup(id: $0.id, name: $0.name, colorHex: $0.colorHex,
                             iconName: $0.iconName, createdAt: $0.createdAt)
            },
            sessions: sessions.map { s in
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
        )
    }

    static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// 共有シートに渡す一時ファイルを作る。
    static func writeTempFile(players: [Player], sessions: [TableSession]) -> URL? {
        guard let data = try? encode(makeBackup(players: players, sessions: sessions)) else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scoresheet_backup_\(df.string(from: Date())).json")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 復元結果（追加した件数）。
    struct RestoreSummary {
        var addedPlayers = 0
        var addedSessions = 0
        var skippedSessions = 0
    }

    /// バックアップを取り込む。既にある ID はそのまま残し、足りないものだけ追加する（上書きしない）。
    @discardableResult
    static func restore(_ backup: BackupFile, into context: ModelContext) throws -> RestoreSummary {
        var summary = RestoreSummary()

        let existingPlayerIDs = Set((try? context.fetch(FetchDescriptor<Player>()))?.map(\.id) ?? [])
        for p in backup.players where !existingPlayerIDs.contains(p.id) {
            let player = Player(name: p.name, colorHex: p.colorHex, iconName: p.iconName)
            player.id = p.id
            player.createdAt = p.createdAt
            context.insert(player)
            summary.addedPlayers += 1
        }

        let existingSessionIDs = Set((try? context.fetch(FetchDescriptor<TableSession>()))?.map(\.id) ?? [])
        for s in backup.sessions {
            guard !existingSessionIDs.contains(s.id) else {
                summary.skippedSessions += 1
                continue
            }
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
            summary.addedSessions += 1
        }

        try context.save()
        return summary
    }
}
