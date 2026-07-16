import SwiftUI
import SwiftData

@main
struct ScoreSheetApp: App {
    // ローカル保存（SwiftData・端末内完結）。v1 は端末内保存のみ。
    // ※ iCloud 同期は将来対応（実機での動作検証が取れ次第 v1.1 で追加予定）。
    //   モデルは CloudKit 対応時の制約（全プロパティ既定値・to-many 空配列既定）を維持している。
    let container: ModelContainer

    init() {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])

        // 1) 通常のローカルストア
        if let c = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
        ) {
            container = c
            return
        }

        // 2) 既存ストアが開けない場合（旧構成からの更新・破損など）は退避して作り直す。
        //    起動不能を避けることを優先し、退避ファイルは復旧用に残す。
        Self.archiveExistingStore()
        if let c = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
        ) {
            container = c
            return
        }

        // 3) 最後の手段：メモリ内のみ（保存はされないが起動はできる）
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        } catch {
            fatalError("ModelContainer の初期化に失敗: \(error)")
        }
    }

    /// 既定のストアファイル一式を `.bak-<timestamp>` へ退避する。
    private static func archiveExistingStore() {
        let fm = FileManager.default
        guard let dir = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) else { return }

        let stamp = Int(Date().timeIntervalSince1970)
        // SwiftData は default.store と付随する -shm / -wal を作る
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            let src = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dir.appendingPathComponent("\(name).bak-\(stamp)")
            try? fm.moveItem(at: src, to: dst)
        }
    }

    @AppStorage(AppSettingsKey.appearance) private var appearance: String = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
