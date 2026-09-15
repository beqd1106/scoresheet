import SwiftUI
import SwiftData

/// ホーム配下の遷移先。
enum HomeRoute: Hashable {
    case history
    case players
    case settings
    case tags
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var path = NavigationPath()

    /// 起動時点の「続きから開くゲーム」。
    /// ホーム画面が表示されると記録が消えるため、body より前のこの時点で読み取っておく。
    @State private var resumeID: String? =
        UserDefaults.standard.string(forKey: AppSettingsKey.resumeSessionID)

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: TableSession.self) { session in
                    TableScoreView(session: session, path: $path)
                }
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .history:  HistoryView(path: $path)
                    case .players:  PlayerListView()
                    case .settings: SettingsView()
                    case .tags:     TagListView(path: $path)
                    }
                }
        }
        .task {
            SampleDataService.seedIfNeeded(context)
            resumeIfNeeded()
        }
    }

    /// 入力途中で閉じたゲームがあれば、そのまま開いて続きから入力できるようにする。
    private func resumeIfNeeded() {
        guard let raw = resumeID, let target = UUID(uuidString: raw) else { return }
        resumeID = nil
        let sessions = (try? context.fetch(FetchDescriptor<TableSession>())) ?? []
        guard let session = sessions.first(where: { $0.id == target }) else { return }
        path.append(session)
    }
}
