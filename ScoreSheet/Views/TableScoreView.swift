import SwiftUI
import SwiftData

struct TableScoreView: View {
    @Bindable var session: TableSession
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context

    @State private var showRoundInput = false
    @State private var editingRound: RoundResult? = nil
    @State private var showChipInput = false
    @State private var roundToDelete: RoundResult? = nil

    private var vm: TableScoreViewModel { TableScoreViewModel(session: session) }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {

                // 累計（常時表示）
                cumulativeCard

                // 回戦記録
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "回戦の記録", systemImage: "list.number")
                    if session.rounds.isEmpty {
                        NoteCard {
                            EmptyNote(title: "まだ記録がありません",
                                      message: "「回戦を追加」から1回戦を記録しましょう。",
                                      systemImage: "square.and.pencil")
                        }
                    } else {
                        ForEach(session.sortedRounds) { round in
                            roundRow(round)
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle(session.gameType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showRoundInput) {
            RoundInputView(session: session,
                           editing: nil,
                           previousOrder: session.sortedRounds.last?.points.sorted { $0.rank < $1.rank }.map(\.participantID))
        }
        .sheet(item: $editingRound) { round in
            RoundInputView(session: session, editing: round, previousOrder: nil)
        }
        .sheet(isPresented: $showChipInput) {
            ChipInputView(session: session)
        }
        .confirmationDialog("この回戦を削除しますか？", isPresented: Binding(
            get: { roundToDelete != nil },
            set: { if !$0 { roundToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                if let r = roundToDelete { deleteRound(r) }
                roundToDelete = nil
            }
            Button("キャンセル", role: .cancel) { roundToDelete = nil }
        }
    }

    // MARK: 累計カード

    private var cumulativeCard: some View {
        NoteCard {
            VStack(spacing: Space.md) {
                HStack {
                    Text("現在の累計").font(AppFont.label(13)).foregroundStyle(Theme.inkSecond)
                    Spacer()
                    Text("\(session.rounds.count)回戦まで")
                        .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                }
                HairlineRule()
                VStack(spacing: Space.sm) {
                    ForEach(Array(vm.standings.enumerated()), id: \.element.participant.id) { idx, item in
                        HStack(spacing: Space.md) {
                            RankBadge(rank: idx + 1, size: 24)
                            PlayerDot(colorHex: item.participant.colorHex)
                            Text(item.participant.name).font(AppFont.body(16, weight: .medium)).foregroundStyle(Theme.ink)
                            Spacer()
                            PointText(value: item.total, size: 22, weight: .bold)
                        }
                    }
                }
            }
        }
    }

    // MARK: 回戦行

    private func roundRow(_ round: RoundResult) -> some View {
        NoteCard(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text("\(round.roundNumber)回戦")
                        .font(AppFont.label(14)).foregroundStyle(Theme.accent)
                    Spacer()
                    // 合計チェック
                    HStack(spacing: 4) {
                        Image(systemName: round.isBalanced ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(round.isBalanced ? "合計0" : "合計\(round.pointSum)")
                            .font(AppFont.body(12, weight: .medium))
                    }
                    .foregroundStyle(round.isBalanced ? Theme.deepGreen : Theme.negative)
                }
                HairlineRule()
                ForEach(round.points.sorted { $0.rank < $1.rank }) { p in
                    HStack(spacing: Space.md) {
                        RankBadge(rank: p.rank, size: 22)
                        Text(session.participant(p.participantID)?.name ?? "-")
                            .font(AppFont.body(15)).foregroundStyle(Theme.ink)
                        if p.isAutoCalculated {
                            Text("自動").font(AppFont.body(10, weight: .semibold))
                                .foregroundStyle(Theme.mutedBlue)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.sunken))
                        }
                        Spacer()
                        PointText(value: p.point, size: 17)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editingRound = round }
        }
        .contextMenu {
            Button { editingRound = round } label: { Label("編集", systemImage: "pencil") }
            Button(role: .destructive) { roundToDelete = round } label: { Label("削除", systemImage: "trash") }
        }
    }

    // MARK: 下部バー

    private var bottomBar: some View {
        HStack(spacing: Space.md) {
            Button { showChipInput = true } label: {
                Label("チップ", systemImage: "circle.grid.2x2")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button { showRoundInput = true } label: {
                Label("回戦を追加", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())

            NavigationLink {
                FinalResultView(session: session)
            } label: {
                Label("集計", systemImage: "flag.checkered")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Space.lg)
        .background(.ultraThinMaterial)
    }

    private func deleteRound(_ round: RoundResult) {
        session.rounds.removeAll { $0.id == round.id }
        context.delete(round)
        session.updatedAt = Date()
        try? context.save()
    }
}
