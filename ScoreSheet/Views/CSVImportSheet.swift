import SwiftUI
import SwiftData

extension CSVImportPreview: Identifiable {
    var id: String { "\(games.count)-\(roundCount)-\(playerNames.joined(separator: ","))" }
}

/// CSV 取り込みの確認画面。読み込んだ内容を見せてから保存する（いきなり保存しない）。
struct CSVImportSheet: View {
    let preview: CSVImportPreview
    let onImport: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.createdAt) private var players: [Player]
    @State private var tag = "CSV取り込み"
    @State private var isImporting = false

    private var rosterNames: Set<String> {
        Set(players.map { $0.name.trimmingCharacters(in: .whitespaces) })
    }

    private var coefficientSummary: String {
        let per1000 = Set(preview.games.map { Int($0.pointCoefficientPer1000) }).sorted()
        let chip = Set(preview.games.map { Int($0.chipPointCoefficient) }).sorted()
        return "1000点あたり " + per1000.map { "\($0)pt" }.joined(separator: "/")
            + "・チップ1枚 " + chip.map { "\($0)pt" }.joined(separator: "/")
    }

    private var dateRangeText: String? {
        guard let range = preview.dateRange else { return nil }
        let f: Date.FormatStyle = .dateTime.year().month().day()
        return "\(range.lowerBound.formatted(f)) 〜 \(range.upperBound.formatted(f))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    summaryCard
                    playerSection
                    tagSection
                    howToSection
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .safeAreaInset(edge: .bottom) {
                Button {
                    isImporting = true
                    onImport(tag)
                } label: {
                    if isImporting {
                        ProgressView().tint(.white)
                    } else {
                        Text("\(preview.games.count)ゲームを取り込む")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !isImporting))
                .disabled(isImporting)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .background(Theme.paper.opacity(0.96))
            }
            .navigationTitle("CSVの取り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    // MARK: 主役：何件入るか

    private var summaryCard: some View {
        NoteCard {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("\(preview.games.count)ゲーム・\(preview.roundCount)回戦")
                    .font(AppFont.heading(24)).foregroundStyle(Theme.ink)
                if let dateRangeText {
                    Text(dateRangeText).font(AppFont.body(14)).foregroundStyle(Theme.inkSecond)
                }
                HairlineRule()
                HStack {
                    StatCell(title: "種別", value: preview.games.first?.gameType.displayName ?? "—")
                    StatDivider()
                    StatCell(title: "プレイヤー", value: "\(preview.playerNames.count)人")
                    StatDivider()
                    StatCell(title: "入力方式", value: InputMode.point.displayName)
                }
            }
        }
    }

    // MARK: プレイヤーの紐付け

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "プレイヤー")
            VStack(spacing: 0) {
                ForEach(Array(preview.playerNames.enumerated()), id: \.offset) { idx, name in
                    if idx > 0 { HairlineRule().padding(.leading, Space.lg) }
                    let known = rosterNames.contains(name)
                    HStack {
                        Text(name).font(AppFont.body(15)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(known ? "名簿の人に記録" : "名簿に追加")
                            .font(AppFont.body(12, weight: .semibold))
                            .foregroundStyle(known ? Theme.inkSecond : Theme.accent)
                            .padding(.horizontal, Space.sm).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: Radius.small)
                                .fill(known ? Theme.sunken : Theme.accent.opacity(0.10)))
                    }
                    .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Theme.rule, lineWidth: Theme.hairline))
            Text("名前が同じプレイヤーは同じ人として記録します。")
                .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
        }
    }

    // MARK: タグ

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "タグ（任意）")
            TextField("例：前のアプリの記録", text: $tag)
                .textFieldStyle(.plain).padding(Space.md)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
            Text("取り込んだゲームにまとめて付けます。タグ別成績で絞り込めます。")
                .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
        }
    }

    // MARK: 取り込み方

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(text: "取り込み方")
            note("各回戦の「スコア」をポイント、「点数」を素点として記録します。")
            note("係数は元の記録から読み取りました（\(coefficientSummary)）。総合ポイントが元のアプリと同じになります。")
            if preview.skippedEmptyRounds > 0 {
                note("全員0点の空の回戦\(preview.skippedEmptyRounds)件は数えません（チップは反映します）。")
            }
            if preview.roundedPointCount > 0 {
                note("小数のポイント\(preview.roundedPointCount)件は四捨五入します。")
            }
            note("すでに取り込んだゲームは重複しないよう飛ばします。")
        }
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Circle().fill(Theme.mutedBlue).frame(width: 4, height: 4).padding(.top, 8)
            Text(text).font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
