import SwiftUI
import SwiftData

struct HistoryView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]

    @State private var toDelete: TableSession? = nil
    private let vm = HistoryViewModel()

    var body: some View {
        ScrollView {
            if sessions.isEmpty {
                EmptyNote(title: "履歴がありません",
                          message: "卓をはじめると、ここに記録が残ります。",
                          systemImage: "clock")
                .padding(.top, Space.xxxl)
            } else {
                VStack(spacing: Space.md) {
                    ForEach(sessions) { session in
                        Button { path.append(session) } label: { row(session) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { toDelete = session } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(Space.lg)
            }
        }
        .background(NotePageBackground())
        .navigationTitle("過去の卓")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("この卓を削除しますか？", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        ), titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                if let s = toDelete { context.delete(s); try? context.save() }
                toDelete = nil
            }
            Button("キャンセル", role: .cancel) { toDelete = nil }
        }
    }

    private func row(_ session: TableSession) -> some View {
        NoteCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text(session.gameType.displayName)
                        .font(AppFont.label(12)).foregroundStyle(Theme.mutedBlue)
                        .padding(.horizontal, Space.sm).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: Radius.small).fill(Theme.sunken))
                    Spacer()
                    Text(vm.dateText(session.date)).font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                }
                Text(session.participants.map(\.name).joined(separator: "・"))
                    .font(AppFont.body(15, weight: .medium)).foregroundStyle(Theme.ink)
                HStack(spacing: Space.md) {
                    Text("\(session.rounds.count)回戦").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                    if let top = vm.topName(of: session) {
                        HStack(spacing: 4) {
                            RankBadge(rank: 1, size: 16)
                            Text(top).font(AppFont.body(13, weight: .medium)).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
        }
    }
}
