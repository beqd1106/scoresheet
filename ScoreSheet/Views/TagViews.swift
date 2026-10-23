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
    @AppStorage(AppSettingsKey.savedRules) private var savedRulesJSON = ""
    @State private var showSaveRule = false
    @State private var saveRuleName = ""
    @State private var savedNotice: String?

    private var suggestions: [String] {
        let used = Set(session.tags)
        let all = Set(allSessions.flatMap { $0.tags })
        return all.subtracting(used).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {

                    // 入力方式とルール
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "入力方式")
                        Picker("入力方式", selection: inputModeBinding) {
                            ForEach(InputMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(session.hasEnteredScores)

                        if session.hasEnteredScores {
                            Text("すでに点数が入力されているため変更できません。別の方式で記録したい場合は新しいゲームを作成してください。")
                                .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                        } else {
                            Text(session.inputMode.summary)
                                .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                        }

                        if session.inputMode == .rawScore {
                            NavigationLink { ruleEditorPage } label: {
                                NoteCard(padding: Space.md) {
                                    HStack(spacing: Space.md) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("対局ルール")
                                                .font(AppFont.body(14, weight: .semibold)).foregroundStyle(Theme.ink)
                                            Text(ruleSummaryText)
                                                .font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                                                .lineLimit(1).minimumScaleFactor(0.7)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

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

                        Button {
                            saveRuleName = SavedRuleStore.suggestedName(existing: SavedRuleStore.decode(savedRulesJSON))
                            showSaveRule = true
                        } label: {
                            Label("この設定をルールとして保存", systemImage: "bookmark")
                                .font(AppFont.body(14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .fill(Theme.accent.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        if let savedNotice {
                            Text(savedNotice).font(AppFont.body(12)).foregroundStyle(Theme.accent)
                        }
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
            .alert("この設定を保存", isPresented: $showSaveRule) {
                TextField("名前（例：いつもの雀荘）", text: $saveRuleName)
                Button("キャンセル", role: .cancel) {}
                Button("保存") { saveAsRule() }
            } message: {
                Text("次の新規ゲームから呼び出せます。このゲームのタグも一緒に保存され、呼び出したゲームに自動で付きます。同じ名前があれば上書きします。")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { session.updatedAt = Date(); try? context.save(); dismiss() }
                }
            }
        }
    }

    private var inputModeBinding: Binding<InputMode> {
        Binding(get: { session.inputMode }, set: { session.inputMode = $0 })
    }

    private var ruleBinding: Binding<GameRule> {
        Binding(get: { session.rule }, set: { session.rule = $0 })
    }

    private var ruleEditorPage: some View {
        ScrollView {
            RuleEditor(rule: ruleBinding, gameType: session.gameType)
                .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle("対局ルール")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ruleSummaryText: String {
        let rule = session.rule
        let uma = rule.normalizedUma(playerCount: session.gameType.playerCount)
        var text = "\(rule.startingPoints)持ち\(rule.returnPoints)返し・ウマ "
            + uma.map { $0.signedPointString }.joined(separator: "/")
        var penalties: [String] = []
        if rule.tobiEnabled { penalties.append("トビ") }
        if rule.yakitoriEnabled { penalties.append("ヤキトリ") }
        if rule.kubiEnabled { penalties.append("クビ") }
        if !penalties.isEmpty { text += "・" + penalties.joined(separator: "/") }
        return text
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

    private func saveAsRule() {
        let name = SavedRuleStore.normalizedName(saveRuleName)
        guard !name.isEmpty else { return }
        let item = SavedRule(name: name, gameType: session.gameType, inputMode: session.inputMode,
                             rule: session.rule,
                             pointCoefficientPer1000: session.pointCoefficientPer1000,
                             chipPointCoefficient: session.chipPointCoefficient,
                             tags: session.tags)
        let result = SavedRuleStore.upsert(item, into: SavedRuleStore.decode(savedRulesJSON))
        savedRulesJSON = SavedRuleStore.encode(result.rules)
        savedNotice = result.replaced ? "「\(name)」を上書きしました。" : "「\(name)」を保存しました。"
    }
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
                        NavigationLink {
                            PlayerStatsListView(initialFilter: StatsFilter(tag: item.tag), title: item.tag)
                        } label: {
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
