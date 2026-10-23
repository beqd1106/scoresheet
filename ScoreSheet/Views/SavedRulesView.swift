import SwiftUI
import SwiftData

// MARK: - 保存したルールの一覧（設定から開く）

struct SavedRulesView: View {
    @AppStorage(AppSettingsKey.savedRules) private var savedRulesJSON = ""
    @AppStorage(AppSettingsKey.defaultSavedRuleID) private var defaultSavedRuleID = ""

    @State private var editing: SavedRule?
    @State private var creating = false
    @State private var pendingDelete: SavedRule?

    private var rules: [SavedRule] { SavedRuleStore.decode(savedRulesJSON) }

    var body: some View {
        let list = rules
        Group {
            if list.isEmpty {
                ScrollView {
                    NoteCard {
                        EmptyNote(title: "保存したルールはありません",
                                  message: "新規ゲーム画面の「今の設定を保存」か、右上の＋から作れます。",
                                  systemImage: "bookmark")
                    }
                    .padding(Space.lg)
                }
            } else {
                List {
                    Section {
                        ForEach(list) { saved in
                            Button { editing = saved } label: { row(saved) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { pendingDelete = saved } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { toggleDefault(saved) } label: {
                                        Label("いつもの", systemImage: "star")
                                    }
                                    .tint(Theme.accentYellow)
                                }
                                .contextMenu {
                                    Button { toggleDefault(saved) } label: {
                                        Label(isDefault(saved) ? "「いつもの」を解除" : "「いつもの」にする",
                                              systemImage: isDefault(saved) ? "star.slash" : "star")
                                    }
                                    Button { editing = saved } label: { Label("編集", systemImage: "pencil") }
                                    Button(role: .destructive) { pendingDelete = saved } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove(perform: move)
                    } footer: {
                        Text("「いつもの」にしたルールは、新規ゲームを開いたとき最初から選ばれます。ルールにタグを付けておくと、呼び出したゲームにそのタグが自動で付き、タグ別成績でまとめて見られます。左へスワイプで削除、右へスワイプで「いつもの」の切り替え。")
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(NotePageBackground())
        .navigationTitle("保存したルール")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !list.isEmpty { EditButton() }
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("ルールを追加")
            }
        }
        .sheet(item: $editing) { saved in
            SavedRuleEditSheet(original: saved, existing: list) { updated in replace(updated) }
        }
        .sheet(isPresented: $creating) {
            SavedRuleEditSheet(original: nil, existing: list) { created in
                save(SavedRuleStore.upsert(created, into: rules).rules)
            }
        }
        .confirmationDialog("「\(pendingDelete?.name ?? "")」を削除しますか？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let target = pendingDelete { delete(target) }
                pendingDelete = nil
            }
        } message: {
            Text("これまでのゲームの記録には影響しません。")
        }
    }

    private func row(_ saved: SavedRule) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: isDefault(saved) ? "star.fill" : "bookmark")
                .font(.system(size: 14))
                .foregroundStyle(isDefault(saved) ? Theme.accentYellow : Theme.mutedBlue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.sm) {
                    Text(saved.name).font(AppFont.body(16, weight: .semibold)).foregroundStyle(Theme.ink)
                    if isDefault(saved) {
                        Text("いつもの")
                            .font(AppFont.body(10, weight: .semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentYellow.opacity(0.35)))
                    }
                }
                Text(saved.summary)
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                    .lineLimit(2)
                if !saved.tags.isEmpty {
                    FlowLayout(spacing: Space.xs) {
                        ForEach(saved.tags, id: \.self) { TagChip(text: $0) }
                    }
                }
            }
            Spacer(minLength: Space.sm)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
    }

    // MARK: 操作

    private func isDefault(_ saved: SavedRule) -> Bool { saved.id.uuidString == defaultSavedRuleID }

    private func toggleDefault(_ saved: SavedRule) {
        defaultSavedRuleID = isDefault(saved) ? "" : saved.id.uuidString
    }

    private func save(_ list: [SavedRule]) { savedRulesJSON = SavedRuleStore.encode(list) }

    private func replace(_ updated: SavedRule) {
        var list = rules
        guard let idx = list.firstIndex(where: { $0.id == updated.id }) else { return }
        list[idx] = updated
        save(list)
    }

    private func delete(_ target: SavedRule) {
        save(rules.filter { $0.id != target.id })
        if isDefault(target) { defaultSavedRuleID = "" }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = rules
        list.move(fromOffsets: source, toOffset: destination)
        save(list)
    }
}

// MARK: - 保存ルールの作成・編集

struct SavedRuleEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [TableSession]
    @State private var newTag = ""

    let original: SavedRule?
    let existing: [SavedRule]
    let onSave: (SavedRule) -> Void

    @State private var draft: SavedRule

    init(original: SavedRule?, existing: [SavedRule], onSave: @escaping (SavedRule) -> Void) {
        self.original = original
        self.existing = existing
        self.onSave = onSave
        _draft = State(initialValue: original ?? SavedRule(
            name: SavedRuleStore.suggestedName(existing: existing),
            gameType: .yonma, inputMode: .rawScore,
            rule: GameRule.standard(for: .yonma),
            pointCoefficientPer1000: AppDefaults.pointCoefficientPer1000,
            chipPointCoefficient: AppDefaults.chipPointCoefficient))
    }

    private var trimmedName: String { SavedRuleStore.normalizedName(draft.name) }

    /// 他のルールと同じ名前は不可（新規ゲーム画面で同名は上書き扱いになるため）。
    private var nameError: String? {
        if trimmedName.isEmpty { return "名前を入力してください。" }
        if existing.contains(where: { $0.name == trimmedName && $0.id != draft.id }) {
            return "同じ名前のルールがあります。"
        }
        return nil
    }

    private var gameTypeBinding: Binding<GameType> {
        Binding(get: { draft.gameType }, set: { newValue in
            draft.gameTypeRaw = newValue.rawValue
            draft.rule.normalize(for: newValue)
        })
    }

    private var inputModeBinding: Binding<InputMode> {
        Binding(get: { draft.inputMode }, set: { draft.inputModeRaw = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionLabel(text: "名前")
                        TextField("例：いつもの雀荘", text: $draft.name)
                            .textFieldStyle(.plain)
                            .padding(Space.md)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                        if let nameError {
                            Text(nameError).font(AppFont.body(12)).foregroundStyle(Theme.negative)
                        }
                    }

                    tagSection

                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "種別")
                        Picker("種別", selection: gameTypeBinding) {
                            ForEach(GameType.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "入力方式")
                        Picker("入力方式", selection: inputModeBinding) {
                            ForEach(InputMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(draft.inputMode.summary)
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    }

                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "ポイント係数")
                        NoteCard {
                            VStack(spacing: Space.lg) {
                                coeffRow("チップ 1枚あたり", $draft.chipPointCoefficient,
                                         AppDefaults.chipStep, AppDefaults.chipMax)
                                HairlineRule()
                                coeffRow("1000点あたり", $draft.pointCoefficientPer1000,
                                         AppDefaults.per1000Step, AppDefaults.per1000Max)
                            }
                        }
                    }

                    if draft.inputMode == .rawScore {
                        RuleEditor(rule: $draft.rule, gameType: draft.gameType)
                    } else {
                        Text("ウマ・オカ・罰符などの対局ルールは、素点入力のときに使います。")
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    }
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle(original == nil ? "ルールを追加" : "ルールを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var item = draft
                        item.name = trimmedName
                        item.tags = SavedRuleStore.normalizedTags(item.tags)
                        onSave(item)
                        dismiss()
                    }
                    .disabled(nameError != nil)
                }
            }
        }
    }

    // MARK: タグ

    /// これまでのゲームで使ったタグのうち、まだ付けていないもの。
    private var tagSuggestions: [String] {
        let used = Set(draft.tags)
        return Array(Set(sessions.flatMap(\.tags)).subtracting(used)).sorted()
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "タグ（任意）")
            Text("このルールで始めたゲームに自動で付きます。タグ別成績でまとめて見られます。")
                .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
            if !draft.tags.isEmpty {
                FlowLayout {
                    ForEach(draft.tags, id: \.self) { t in
                        TagChip(text: t) { draft.tags.removeAll { $0 == t } }
                    }
                }
            }
            HStack(spacing: Space.sm) {
                TextField("例：金曜会", text: $newTag)
                    .textFieldStyle(.plain).padding(Space.md)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                    .onSubmit { addTag(newTag) }
                Button { addTag(newTag) } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44).foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.accent))
                }
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("タグを追加")
            }
            if !tagSuggestions.isEmpty {
                FlowLayout {
                    ForEach(tagSuggestions, id: \.self) { t in
                        Button { addTag(t) } label: { TagChip(text: t) }
                    }
                }
            }
        }
    }

    private func addTag(_ text: String) {
        let v = text.trimmingCharacters(in: .whitespaces)
        newTag = ""
        guard !v.isEmpty, !draft.tags.contains(v) else { return }
        draft.tags.append(v)
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
}
