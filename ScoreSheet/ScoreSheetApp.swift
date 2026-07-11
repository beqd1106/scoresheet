import SwiftUI
import SwiftData

@main
struct ScoreSheetApp: App {
    // SwiftData + CloudKit（iCloud 自動同期）。
    // 端末を消しても、同じ Apple ID で再インストールすれば iCloud から自動復元される。
    // cloudKitDatabase: .automatic は entitlements の iCloud コンテナを使用。
    // ※ CloudKit の初期化に失敗した場合はローカルのみにフォールバックし、
    //   少なくともデータが失われない・アプリが起動しないことを防ぐ。
    let container: ModelContainer

    init() {
        let schema = Schema([Player.self, TableSession.self, RoundResult.self])
        do {
            let config = ModelConfiguration(schema: schema,
                                            isStoredInMemoryOnly: false,
                                            cloudKitDatabase: .automatic)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // iCloud が使えない環境（未ログイン等）でも起動できるようローカルへフォールバック。
            do {
                let local = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: false,
                                               cloudKitDatabase: .none)
                container = try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("ModelContainer の初期化に失敗: \(error)")
            }
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
