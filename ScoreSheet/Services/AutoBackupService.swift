import Foundation
import CryptoKit
import SwiftData

/// 端末内に自動保存されたバックアップ1件分。
struct AutoBackupSnapshot: Identifiable, Equatable {
    var id: URL { url }
    var url: URL
    var date: Date
    var sessionCount: Int
    var playerCount: Int
}

/// アプリを閉じるたびに、端末内へ静かにバックアップを取っておく仕組み。
/// 手動の書き出しを忘れていても直前の状態に戻せるようにするのが目的。
/// 保存先はアプリ内の Application Support で、古いものから消して数世代だけ残す。
enum AutoBackupService {

    /// 残す世代数。
    static let maxGenerations = 5

    private static let folderName = "AutoBackups"
    private static let filePrefix = "auto-"

    // MARK: 保存先

    static func defaultDirectory() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: 一覧

    /// 新しい順に並べて返す。
    static func list(in directory: URL? = nil) -> [AutoBackupSnapshot] {
        guard let dir = directory ?? defaultDirectory() else { return [] }
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(filePrefix) && $0.pathExtension == "json" } ?? []

        return urls.compactMap { url -> AutoBackupSnapshot? in
            guard let data = try? Data(contentsOf: url),
                  let file = try? BackupService.decode(data) else { return nil }
            return AutoBackupSnapshot(url: url,
                                      date: file.exportedAt,
                                      sessionCount: file.sessions.count,
                                      playerCount: file.players.count)
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: 保存

    /// 変化があれば1世代ぶん書き出す。内容が最新の世代と同じなら何もしない。
    @discardableResult
    static func snapshotIfNeeded(players: [Player],
                                 sessions: [TableSession],
                                 in directory: URL? = nil,
                                 now: Date = Date()) -> AutoBackupSnapshot? {
        guard let dir = directory ?? defaultDirectory() else { return nil }
        guard !sessions.isEmpty || !players.isEmpty else { return nil }

        var backup = BackupService.makeBackup(players: players, sessions: sessions)
        backup.exportedAt = now
        let hash = payloadHash(backup)

        // 直近の世代と中身が同じならスキップ（閉じるたびに増えないように）。
        if let latest = list(in: dir).first,
           let data = try? Data(contentsOf: latest.url),
           let file = try? BackupService.decode(data),
           payloadHash(file) == hash {
            return nil
        }

        guard let data = try? BackupService.encode(backup) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("\(filePrefix)\(df.string(from: now)).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }

        prune(in: dir)
        return AutoBackupSnapshot(url: url, date: now,
                                  sessionCount: backup.sessions.count,
                                  playerCount: backup.players.count)
    }

    /// 世代数を超えた古いものを削除する。
    private static func prune(in directory: URL) {
        let all = list(in: directory)
        guard all.count > maxGenerations else { return }
        for old in all.dropFirst(maxGenerations) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    // MARK: 復元

    /// 選んだ世代を取り込む。既存のゲームは上書きせず、足りないものだけ追加する。
    @discardableResult
    static func restore(_ snapshot: AutoBackupSnapshot,
                        into context: ModelContext) throws -> BackupService.RestoreSummary {
        let data = try Data(contentsOf: snapshot.url)
        let file = try BackupService.decode(data)
        return try BackupService.restore(file, into: context)
    }

    // MARK: 中身の比較

    /// 書き出し日時を除いた中身のハッシュ。同じ内容の世代を増やさないために使う。
    private static func payloadHash(_ backup: BackupFile) -> String {
        var copy = backup
        copy.exportedAt = Date(timeIntervalSince1970: 0)
        guard let data = try? BackupService.encode(copy) else { return UUID().uuidString }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
