import SwiftUI
import SwiftData

// MARK: - タグチップ

struct TagChip: View {
    let text: String
    var onRemove: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag").font(.system(size: 10))
            Text(text).font(AppFont.body(13, weight: .medium))
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.system(size: 13)) }
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Space.sm).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: Radius.pill).fill(Theme.accent.opacity(0.10)))
    }
}

/// 折り返しレイアウト（タグ表示用）。
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.sm
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - ゲーム設定シート（係数＋タグ。作成後の訂正用）

struct GameSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var session: TableSession
    @Query private var allSessions: [TableSession]

    @State private var newTag = ""

    private var suggestions: [String] {
        let used = Set(session.tags)
        let all = Set(allSessions.flatMap { $0.tags })
        return all.subtracting(used).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {

                    // 係数
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "ポイント係数")
                        NoteCard {
                            VStack(spacing: Space.lg) {
                                coeffRow("チップ 1枚あたり", $session.chipPointCoefficient,
                                         AppDefaults.chipStep, AppDefaults.chipMax)
                                HairlineRule()
                                coeffRow("1000点あたり", $session.pointCoefficientPer1000,
                                         AppDefaults.per1000Step, AppDefaults.per1000Max)
                            }
                        }
                        Text("総合計 = 対局ポイント×1000点係数 ＋ チップ枚数×チップ係数")
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    }

                    // タグ
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "タグ")
                        if session.tags.isEmpty {
                            Text("タグはまだありません。").font(AppFont.body(14)).foregroundStyle(Theme.inkSecond)
                        } else {
                            FlowLayout {
                                ForEach(session.tags, id: \.self) { t in
                                    TagChip(text: t) { remove(t) }
                                }
                            }
                        }
                        HStack(spacing: Space.sm) {
                            TextField("タグを追加（例：4月定例）", text: $newTag)
                                .textFieldStyle(.plain).padding(Space.md)
                                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                                .onSubmit { add(newTag) }
                            Button { add(newTag) } label: {
                                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                    .frame(width: 44, height: 44).foregroundStyle(.white)
                                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.accent))
                            }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if !suggestions.isEmpty {
                            FlowLayout {
                                ForEach(suggestions, id: \.self) { t in
                                    Button { add(t) } label: { TagChip(text: t) }
                                }
                            }
                        }
                    }
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle("ゲーム設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { session.updatedAt = Date(); try? context.save(); dismiss() }
                }
            }
        }
    }

    private func coeffRow(_ title: String, _ value: Binding<Double>, _ step: Double, _ maxV: Double) -> some View {
        HStack {
            Text(title).font(AppFont.body(15)).foregroundStyle(Theme.ink)
            Spacer()
            Stepper("", value: value, in: 0...maxV, step: step).labelsHidden()
            Text("\(Int(value.wrappedValue)) pt")
                .font(AppFont.number(16, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func add(_ t: String) {
        let v = t.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, !session.tags.contains(v) else { newTag = ""; return }
        session.tags.append(v)
        newTag = ""
    }
    private func remove(_ t: String) { session.tags.removeAll { $0 == t } }
}

// MARK: - タグ一覧

struct TagListView: View {
    @Binding var path: NavigationPath
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]

    /// タグ -> 該当ゲーム数。
    private var tagCounts: [(tag: String, count: Int)] {
        var dict: [String: Int] = [:]
        for s in sessions { for t in s.tags { dict[t, default: 0] += 1 } }
        return dict.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            if tagCounts.isEmpty {
                EmptyNote(title: "タグがありません",
                          message: "ゲームにタグを付けると、タグごとの成績をまとめて見られます。",
                          systemImage: "tag")
                .padding(.top, Space.xxxl)
            } else {
                VStack(spacing: Space.md) {
                    ForEach(tagCounts, id: \.tag) { item in
                        NavigationLink { TagSummaryView(tag: item.tag) } label: {
                            NoteCard {
                                HStack(spacing: Space.md) {
                                    Image(systemName: "tag").foregroundStyle(Theme.accent)
                                    Text(item.tag).font(AppFont.body(16, weight: .semibold)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text("\(item.count)ゲーム").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.lg)
            }
        }
        .background(NotePageBackground())
        .navigationTitle("タグ別成績")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - タグ別集計

struct TagSummaryView: View {
    let tag: String
    @Query(sort: \TableSession.date, order: .reverse) private var allSessions: [TableSession]

    // tags は Codable 配列属性のため #Predicate では検索できない。Swift 側で絞り込む。
    private var sessions: [TableSession] { allSessions.filter { $0.tags.contains(tag) } }

    init(tag: String) { self.tag = tag }

    private struct Agg: Identifiable {
        let id: UUID
        var name: String
        var colorHex: String
        var totalGrand: Int
        var sumAvgRank: Double
        var games: Int
        var topCount: Int
        var avgRank: Double { games == 0 ? 0 : sumAvgRank / Double(games) }
    }

    private var aggregates: [Agg] {
        var dict: [UUID: Agg] = [:]
        for s in sessions {
            for r in ScoreCalculator.finalResults(for: s) {
                var a = dict[r.participantID] ?? Agg(id: r.participantID, name: r.name, colorHex: r.colorHex,
                                                     totalGrand: 0, sumAvgRank: 0, games: 0, topCount: 0)
                a.name = r.name; a.colorHex = r.colorHex
                a.totalGrand += r.grandTotal
                a.sumAvgRank += r.averageRank
                a.games += 1
                a.topCount += r.topCount
                dict[r.participantID] = a
            }
        }
        return dict.values.sorted { $0.totalGrand > $1.totalGrand }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                Text("\(sessions.count)ゲームの合算").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                ForEach(Array(aggregates.enumerated()), id: \.element.id) { idx, a in
                    NoteCard {
                        VStack(spacing: Space.md) {
                            HStack(spacing: Space.md) {
                                RankBadge(rank: idx + 1, size: 30)
                                PlayerDot(colorHex: a.colorHex, size: 11)
                                Text(a.name).font(AppFont.body(17, weight: .semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(a.totalGrand.signedPointString)
                                    .font(AppFont.number(24, weight: .bold))
                                    .foregroundStyle(Theme.pointColor(a.totalGrand))
                            }
                            HairlineRule()
                            HStack {
                                cell("ゲーム数", "\(a.games)")
                                divider
                                cell("平均順位", String(format: "%.2f", a.avgRank))
                                divider
                                cell("トップ", "\(a.topCount)回")
                            }
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle(tag)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cell(_ t: String, _ v: String) -> some View {
        VStack(spacing: 3) {
            Text(t).font(AppFont.body(11)).foregroundStyle(Theme.inkFaint)
            Text(v).font(AppFont.number(15, weight: .semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
    }
    private var divider: some View {
        Rectangle().fill(Theme.rule).frame(width: Theme.hairline, height: 26)
    }
}
