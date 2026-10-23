import SwiftUI
import SwiftData

struct PlayerListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var players: [Player]
    @Query private var sessions: [TableSession]

    @State private var newName = ""
    @State private var editingPlayer: Player? = nil
    @State private var toDelete: Player? = nil
    @State private var deleteMessage: String?
    @State private var deleteFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {

                // 追加
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionLabel(text: "プレイヤーを追加")
                    HStack(spacing: Space.sm) {
                        TextField("名前", text: $newName)
                            .textFieldStyle(.plain)
                            .padding(Space.md)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                        Button { addPlayer() } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48).foregroundStyle(.white)
                                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.accent))
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // 一覧
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "プレイヤー（\(players.count)人）")
                    if let deleteMessage {
                        Text(deleteMessage)
                            .font(AppFont.body(12))
                            .foregroundStyle(deleteFailed ? Theme.accentRed : Theme.accent)
                    }
                    if players.isEmpty {
                        Text("まだプレイヤーがいません。").font(AppFont.body(14)).foregroundStyle(Theme.inkSecond)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(players.enumerated()), id: \.element.id) { idx, player in
                            if idx > 0 { HairlineRule().padding(.leading, Space.lg) }
                            playerRow(player)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Theme.rule, lineWidth: Theme.hairline))
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle("プレイヤー")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPlayer) { p in PlayerEditSheet(player: p) }
        .confirmationDialog(deleteTitle, isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        ), titleVisibility: .visible) {
            if let p = toDelete {
                let count = gameCount(p)
                Button("名簿から外す（記録は残す）", role: .destructive) { delete(p, .rosterOnly) }
                if count > 0 {
                    Button("記録だけ消す（\(count)ゲーム）", role: .destructive) { delete(p, .gamesOnly) }
                    Button("名簿も記録も消す（\(count)ゲーム）", role: .destructive) { delete(p, .gamesAndRoster) }
                }
            }
            Button("キャンセル", role: .cancel) { toDelete = nil }
        } message: {
            if let p = toDelete, gameCount(p) > 0 {
                Text("記録を消すと、\(p.name)さんが入ったゲームが丸ごと消え、同じゲームにいた人の記録からもなくなります。消す前の状態は設定の「自動バックアップ」から戻せます。")
            } else {
                Text("名簿から外しても、過去のゲームの記録は残ります。")
            }
        }
    }

    private var deleteTitle: String { "\(toDelete?.name ?? "")さんを削除" }

    private func gameCount(_ player: Player) -> Int {
        DataResetService.sessions(involving: player.id, in: sessions).count
    }

    private func delete(_ player: Player, _ scope: DataResetService.PlayerScope) {
        let name = player.name
        do {
            let summary = try DataResetService.deletePlayer(player, scope: scope, context: context)
            deleteFailed = false
            switch scope {
            case .rosterOnly:     deleteMessage = "\(name)さんを名簿から外しました。"
            case .gamesOnly:      deleteMessage = "\(name)さんが入ったゲーム\(summary.deletedSessions)件を消しました。"
            case .gamesAndRoster: deleteMessage = "\(name)さんと、入っていたゲーム\(summary.deletedSessions)件を消しました。"
            }
        } catch {
            deleteFailed = true
            deleteMessage = "削除できませんでした。もう一度お試しください。"
        }
        toDelete = nil
    }

    private func playerRow(_ player: Player) -> some View {
        HStack(spacing: Space.md) {
            Circle().fill(Color(hex: player.colorHex)).frame(width: 26, height: 26)
                .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(.white))
            Text(player.name).font(AppFont.body(16)).foregroundStyle(Theme.ink)
            Spacer()
            NavigationLink {
                PlayerStatsDetailView(playerID: player.id, initialFilter: StatsFilter())
            } label: {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(Theme.mutedBlue)
            }
            .accessibilityLabel("\(player.name)の成績")
            Button { editingPlayer = player } label: {
                Image(systemName: "pencil").foregroundStyle(Theme.mutedBlue)
            }
            Button { toDelete = player } label: {
                Image(systemName: "trash").foregroundStyle(Theme.negative)
            }
            .accessibilityLabel("\(player.name)を削除")
        }
        .padding(Space.lg)
    }

    private func addPlayer() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let color = Theme.playerPalette[players.count % Theme.playerPalette.count]
        context.insert(Player(name: name, colorHex: color))
        try? context.save()
        newName = ""
    }
}

/// 名前・色の編集シート。
struct PlayerEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var player: Player

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionLabel(text: "名前")
                        TextField("名前", text: $player.name)
                            .textFieldStyle(.plain)
                            .padding(Space.md)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                    }
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionLabel(text: "色")
                        HStack(spacing: Space.md) {
                            ForEach(Theme.playerPalette, id: \.self) { hex in
                                Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Theme.ink, lineWidth: player.colorHex == hex ? 2 : 0))
                                    .onTapGesture { player.colorHex = hex }
                            }
                        }
                    }
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle("プレイヤー編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { try? context.save(); dismiss() }
                }
            }
        }
    }
}
