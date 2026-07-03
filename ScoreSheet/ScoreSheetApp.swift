import SwiftUI
import SwiftData

@main
struct ScoreSheetApp: App {
    // ローカル保存（SwiftData）。クラウドは将来拡張。MVPは端末内完結。
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
