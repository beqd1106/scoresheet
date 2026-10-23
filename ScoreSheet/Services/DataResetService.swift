import Foundation
import SwiftData

/// 記録の削除（プレイヤーごと・一括）。
/// 消す前に必ず自動バックアップを1世代取り、設定の「自動バックアップ」から戻せるようにする。
enum DataResetService {

    /// プレイヤー1人分の消し方。
    enum PlayerScope {
        /// 名簿から外すだけ（過去のゲームはそのまま残る）。
        case rosterOnly
        /// その人が入ったゲームを消す。名簿には残す。
        case gamesOnly
        /// その人が入ったゲームも名簿も消す。
        case gamesAndRoster
    }

    /// 一括リセットの範囲。
    enum AllScope {
        /// ゲームの記録だけ消す（プレイヤー・保存したルールは残す）。
        case gamesOnly
        /// ゲーム・プレイヤー・保存したルールをすべて消して最初の状態に戻す。
        case everything
    }

    struct Summary: Equatable {
        var deletedSessions = 0
        var deletedPlayers = 0
        var deletedRules = 0
    }

    /// そのプレイヤーが入っているゲーム。
    static func sessions(involving playerID: UUID, in sessions: [TableSession]) -> [TableSession] {
        sessions.filter { s in s.participants.contains { $0.id == playerID } }
    }

    @discardableResult
    static func deletePlayer(_ player: Player,
                             scope: PlayerScope,
                             context: ModelContext,
                             backupDirectory: URL? = nil) throws -> Summary {
        let allSessions = try context.fetch(FetchDescriptor<TableSession>())
        let allPlayers = try context.fetch(FetchDescriptor<Player>())
        backUp(players: allPlayers, sessions: allSessions, directory: backupDirectory)

        var summary = Summary()
        if scope != .rosterOnly {
            for s in sessions(involving: player.id, in: allSessions) {
                context.delete(s)
                summary.deletedSessions += 1
            }
        }
        if scope != .gamesOnly {
            context.delete(player)
            summary.deletedPlayers = 1
        }
        try context.save()
        return summary
    }

    @discardableResult
    static func resetAll(scope: AllScope,
                         context: ModelContext,
                         defaults: UserDefaults = .standard,
                         backupDirectory: URL? = nil) throws -> Summary {
        let allSessions = try context.fetch(FetchDescriptor<TableSession>())
        let allPlayers = try context.fetch(FetchDescriptor<Player>())
        backUp(players: allPlayers, sessions: allSessions,
               savedRules: SavedRuleStore.load(defaults), directory: backupDirectory)

        var summary = Summary()
        // 一括削除（delete(model:)）は関連の連鎖削除が確実でないので、1件ずつ消す。
        for s in allSessions { context.delete(s) }
        summary.deletedSessions = allSessions.count

        if scope == .everything {
            for p in allPlayers { context.delete(p) }
            summary.deletedPlayers = allPlayers.count
            summary.deletedRules = SavedRuleStore.load(defaults).count
            defaults.removeObject(forKey: AppSettingsKey.savedRules)
            defaults.removeObject(forKey: AppSettingsKey.defaultSavedRuleID)
        }
        defaults.removeObject(forKey: AppSettingsKey.resumeSessionID)
        try context.save()
        return summary
    }

    /// 消す直前の状態を自動バックアップに残す。中身が最新の世代と同じなら新しくは作らない（既にある）。
    private static func backUp(players: [Player], sessions: [TableSession],
                               savedRules: [SavedRule]? = nil, directory: URL?) {
        guard !players.isEmpty || !sessions.isEmpty else { return }
        AutoBackupService.snapshotIfNeeded(players: players, sessions: sessions,
                                           savedRules: savedRules, in: directory)
    }
}
