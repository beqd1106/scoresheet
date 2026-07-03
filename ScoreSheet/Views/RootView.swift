import SwiftUI
import SwiftData

/// ホーム配下の遷移先。
enum HomeRoute: Hashable {
    case history
    case players
    case settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var path = NavigationPath()

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
                    }
                }
        }
        .task {
            SampleDataService.seedIfNeeded(context)
        }
    }
}
