import SwiftUI
import SwiftData

struct PlayerListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var players: [Player]

    @State private var newName = ""
    @State private var editingPlayer: Player? = nil
    @State private var toDelete: Player? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {

                // 追加
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionLabel(text: "メンバーを追加")
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
                    SectionLabel(text: "メンバー（\(players.count)人）")
                    if players.isEmpty {
                        Text("まだメンバーがいません。").font(AppFont.body(14)).foregroundStyle(Theme.inkSecond)
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
        .navigationTitle("メンバー")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPlayer) { p in PlayerEditSheet(player: p) }
        .confirmationDialog("このメンバーを削除しますか？（過去の記録は残ります）", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        ), titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                if let p = toDelete { context.delete(p); try? context.save() }
                toDelete = nil
            }
            Button("キャンセル", role: .cancel) { toDelete = nil }
        }
    }

    private func playerRow(_ player: Player) -> some View {
        HStack(spacing: Space.md) {
            Circle().fill(Color(hex: player.colorHex)).frame(width: 26, height: 26)
                .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(.white))
            Text(player.name).font(AppFont.body(16)).foregroundStyle(Theme.ink)
            Spacer()
            Button { editingPlayer = player } label: {
                Image(systemName: "pencil").foregroundStyle(Theme.mutedBlue)
            }
            Button { toDelete = player } label: {
                Image(systemName: "trash").foregroundStyle(Theme.negative)
            }
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
            .navigationTitle("メンバー編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { try? context.save(); dismiss() }
                }
            }
        }
    }
}
