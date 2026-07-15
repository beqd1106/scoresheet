import SwiftUI
import SwiftData

@main
struct ScoreSheetApp: App {
    // ローカル保存（SwiftData・端末内完結）。v1 は端末内保存のみ。
    // ※ iCloud 同期は将来対応（実機での動作検証が取れ次第 v1.1 で追加予定）。
    //   モデルは CloudKit 対応時の制約（全プロパティ既定値・to-many 空配列既定）を維持している。
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([Player.self, TableSession.self, RoundResult.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer の初期化に失敗: \(error)")
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
