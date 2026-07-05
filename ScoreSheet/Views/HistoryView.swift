import SwiftUI
import SwiftData

struct HistoryView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]

    @State private var toDelete: TableSession? = nil
    @State private var tagTarget: TableSession? = nil
    private let vm = HistoryViewModel()

    var body: some View {
        Group {
            if sessions.isEmpty {
                ScrollView {
                    EmptyNote(title: "履歴がありません",
                              message: "ゲームをはじめると、ここに記録が残ります。",
                              systemImage: "clock")
                    .padding(.top, Space.xxxl)
                }
            } else {
                List {
                    ForEach(sessions) { session in
                        Button { path.append(session) } label: { row(session) }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.lg,
                                                      bottom: Space.xs, trailing: Space.lg))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { toDelete = session } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { tagTarget = session } label: {
                                    Label("タグ", systemImage: "tag")
                                }.tint(Theme.accent)
                            }
                            .contextMenu {
                                Button { tagTarget = session } label: { Label("タグを編集", systemImage: "tag") }
                                Button(role: .destructive) { toDelete = session } label: { Label("削除", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(NotePageBackground())
        .navigationTitle("過去のゲーム")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tagTarget) { TagEditSheet(session: $0) }
        .confirmationDialog("このゲームを削除しますか？", isPresented: Binding(
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
                if !session.tags.isEmpty {
                    FlowLayout(spacing: Space.xs) {
                        ForEach(session.tags, id: \.self) { TagChip(text: $0) }
                    }
                }
            }
        }
    }
}
