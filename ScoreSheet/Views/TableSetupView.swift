import SwiftUI
import SwiftData

struct TableSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var roster: [Player]

    @AppStorage(AppSettingsKey.defaultGameType) private var defaultGameTypeRaw = GameType.yonma.rawValue
    @AppStorage(AppSettingsKey.pointCoefficientPer1000) private var defaultPer1000 = AppDefaults.pointCoefficientPer1000
    @AppStorage(AppSettingsKey.chipPointCoefficient) private var defaultChip = AppDefaults.chipPointCoefficient
    @AppStorage(AppSettingsKey.defaultInputMode) private var defaultInputModeRaw = InputMode.point.rawValue
    @AppStorage(AppSettingsKey.savedRules) private var savedRulesJSON = ""
    @AppStorage(AppSettingsKey.defaultSavedRuleID) private var defaultSavedRuleID = ""

    @State private var vm = TableSetupViewModel()
    @State private var newPlayerName = ""
    @State private var newTag = ""
    /// 既定値の読み込みは最初の1回だけ（ルール編集から戻るたびに初期化しないため）。
    @State private var didLoadDefaults = false
    @State private var showSaveRule = false
    @State private var saveRuleName = ""
    @State private var savedNotice: String?

    let onStart: (TableSession) -> Void

    private func addTag() {
        let v = newTag.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, !vm.tags.contains(v) else { newTag = ""; return }
        vm.tags.append(v)
        newTag = ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {

                    savedRulesSection

                    // 種別
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "種別")
                        Picker("種別", selection: $vm.gameType) {
                            ForEach(GameType.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: vm.gameType) { _, _ in vm.normalizeSelection() }
                    }

                    // 入力方式
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "入力方式")
                        Picker("入力方式", selection: $vm.inputMode) {
                            ForEach(InputMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(vm.inputMode.summary)
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                        if vm.inputMode == .rawScore {
                            NavigationLink { ruleEditorPage } label: { ruleSummaryRow }
                                .buttonStyle(.plain)
                        }
                    }

                    // プレイヤー選択
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "プレイヤー（\(vm.selectedPlayerIDs.count)/\(vm.requiredCount)）")
                        if roster.isEmpty {
                            Text("プレイヤーがいません。下から追加してください。")
                                .font(AppFont.body(14)).foregroundStyle(Theme.inkSecond)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(roster.enumerated()), id: \.element.id) { idx, player in
                                if idx > 0 { HairlineRule().padding(.leading, Space.lg) }
                                playerSelectRow(player)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Theme.rule, lineWidth: Theme.hairline))

                        // クイック追加
                        HStack(spacing: Space.sm) {
                            TextField("プレイヤーを追加", text: $newPlayerName)
                                .textFieldStyle(.plain)
                                .padding(Space.md)
                                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                            Button {
                                addPlayer()
                            } label: {
                                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(.white)
                                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.mutedBlue))
                            }
                            .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    // 係数
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "ポイント係数")
                        coefficientRow(title: "チップ 1枚あたり", value: $vm.chipPointCoefficient,
                                       step: AppDefaults.chipStep, maxV: AppDefaults.chipMax)
                        HairlineRule()
                        coefficientRow(title: "1000点あたり", value: $vm.pointCoefficientPer1000,
                                       step: AppDefaults.per1000Step, maxV: AppDefaults.per1000Max)
                        Text("総合計 = 対局ポイント×1000点係数 ＋ チップ枚数×チップ係数")
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    }

                    // タグ（任意）
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "タグ（任意）")
                        if !vm.tags.isEmpty {
                            FlowLayout {
                                ForEach(vm.tags, id: \.self) { t in
                                    TagChip(text: t) { vm.tags.removeAll { $0 == t } }
                                }
                            }
                        }
                        HStack(spacing: Space.sm) {
                            TextField("例：4月定例・○○杯", text: $newTag)
                                .textFieldStyle(.plain).padding(Space.md)
                                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                                .onSubmit(addTag)
                            Button(action: addTag) {
                                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                    .frame(width: 44, height: 44).foregroundStyle(.white)
                                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.mutedBlue))
                            }
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle("新規ゲーム")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Space.sm) {
                    if let msg = vm.validationMessage {
                        Text(msg).font(AppFont.body(13)).foregroundStyle(Theme.negative)
                    }
                    Button {
                        if let session = vm.makeSession(from: roster) { onStart(session) }
                    } label: {
                        Text("この設定ではじめる")
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: vm.canStart))
                    .disabled(!vm.canStart)
                }
                .padding(Space.lg)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                guard !didLoadDefaults else { return }
                didLoadDefaults = true
                vm.gameType = GameType(rawValue: defaultGameTypeRaw) ?? .yonma
                vm.pointCoefficientPer1000 = defaultPer1000
                vm.chipPointCoefficient = defaultChip
                vm.inputMode = InputMode(rawValue: defaultInputModeRaw) ?? .point
                vm.rule = GameRule.standard(for: vm.gameType)
                if let saved = savedRules.first(where: { $0.id.uuidString == defaultSavedRuleID }) {
                    vm.apply(saved)
                }
            }
            .alert("今の設定を保存", isPresented: $showSaveRule) {
                TextField("名前（例：いつもの雀荘）", text: $saveRuleName)
                Button("キャンセル", role: .cancel) {}
                Button("保存") { saveCurrentRule() }
            } message: {
                Text("種別・入力方式・ルール・係数をまとめて保存します。同じ名前があれば上書きします。")
            }
        }
    }

    // MARK: 保存したルール

    private var savedRules: [SavedRule] { SavedRuleStore.decode(savedRulesJSON) }

    private var savedRulesSection: some View {
        let rules = savedRules
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "保存したルール")
            if rules.isEmpty {
                Text("よく使う設定を保存しておくと、次からワンタップで呼び出せます。")
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(rules) { saved in
                        savedRuleChip(saved)
                    }
                    Button {
                        saveRuleName = SavedRuleStore.suggestedName(existing: rules)
                        showSaveRule = true
                    } label: {
                        Label("今の設定を保存", systemImage: "plus")
                            .font(AppFont.body(13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, Space.md)
                            .frame(minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.5),
                                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            if let savedNotice {
                Text(savedNotice).font(AppFont.body(12)).foregroundStyle(Theme.accent)
            }
        }
    }

    private func savedRuleChip(_ saved: SavedRule) -> some View {
        let active = vm.isCurrent(saved)
        let isDefault = saved.id.uuidString == defaultSavedRuleID
        return Button {
            vm.apply(saved)
            savedNotice = nil
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isDefault {
                        Image(systemName: "star.fill").font(.system(size: 10))
                            .foregroundStyle(active ? Color.white : Theme.accentYellow)
                    }
                    Text(saved.name)
                        .font(AppFont.body(14, weight: .semibold))
                        .foregroundStyle(active ? Color.white : Theme.ink)
                        .lineLimit(1)
                }
                Text("\(saved.gameType.displayName)・\(saved.inputMode == .rawScore ? "素点" : "ポイント")")
                    .font(AppFont.body(11))
                    .foregroundStyle(active ? Color.white.opacity(0.85) : Theme.inkFaint)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(minWidth: 112, minHeight: 48, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(active ? Theme.accent : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(active ? Color.clear : Theme.rule, lineWidth: Theme.hairline)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                defaultSavedRuleID = isDefault ? "" : saved.id.uuidString
            } label: {
                Label(isDefault ? "「いつもの」を解除" : "「いつもの」にする（最初から選ぶ）",
                      systemImage: isDefault ? "star.slash" : "star")
            }
            Button {
                overwrite(saved)
            } label: {
                Label("今の設定で上書き", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func saveCurrentRule() {
        let name = SavedRuleStore.normalizedName(saveRuleName)
        guard !name.isEmpty else { return }
        let result = SavedRuleStore.upsert(vm.makeSavedRule(name: name), into: savedRules)
        savedRulesJSON = SavedRuleStore.encode(result.rules)
        savedNotice = result.replaced ? "「\(name)」を上書きしました。" : "「\(name)」を保存しました。"
    }

    private func overwrite(_ saved: SavedRule) {
        let result = SavedRuleStore.upsert(vm.makeSavedRule(name: saved.name), into: savedRules)
        savedRulesJSON = SavedRuleStore.encode(result.rules)
        savedNotice = "「\(saved.name)」を今の設定で上書きしました。"
    }

    private var ruleEditorPage: some View {
        ScrollView {
            RuleEditor(rule: $vm.rule, gameType: vm.gameType)
                .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle("対局ルール")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 現在のルールの要約（タップで編集画面へ）。
    private var ruleSummaryRow: some View {
        let uma = vm.rule.normalizedUma(playerCount: vm.requiredCount)
        var penalties: [String] = []
        if vm.rule.tobiEnabled { penalties.append("トビ") }
        if vm.rule.yakitoriEnabled { penalties.append("ヤキトリ") }
        if vm.rule.kubiEnabled { penalties.append("クビ") }
        return NoteCard(padding: Space.md) {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(vm.rule.startingPoints)点持ち / \(vm.rule.returnPoints)点返し")
                        .font(AppFont.body(14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("ウマ \(uma.map { $0.signedPointString }.joined(separator: "/"))"
                         + (penalties.isEmpty ? "" : "・罰符 " + penalties.joined(separator: "/")))
                        .font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                Text("変更")
                    .font(AppFont.body(13, weight: .semibold)).foregroundStyle(Theme.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func playerSelectRow(_ player: Player) -> some View {
        Button { vm.toggle(player.id) } label: {
            HStack(spacing: Space.md) {
                PlayerDot(colorHex: player.colorHex, size: 12)
                Text(player.name).font(AppFont.body(16)).foregroundStyle(Theme.ink)
                Spacer()
                if let order = vm.selectedPlayerIDs.firstIndex(of: player.id) {
                    Text("\(order + 1)")
                        .font(AppFont.number(13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accent))
                } else {
                    Image(systemName: "circle").foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(Space.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(!vm.isSelected(player.id) && vm.selectedPlayerIDs.count >= vm.requiredCount ? 0.4 : 1)
    }

    private func coefficientRow(title: String, value: Binding<Double>, step: Double, maxV: Double) -> some View {
        HStack {
            Text(title).font(AppFont.body(15)).foregroundStyle(Theme.ink)
            Spacer()
            Stepper("", value: value, in: 0...maxV, step: step).labelsHidden()
            Text("\(Int(value.wrappedValue)) pt")
                .font(AppFont.number(16, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func addPlayer() {
        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let color = Theme.playerPalette[roster.count % Theme.playerPalette.count]
        let p = Player(name: name, colorHex: color)
        context.insert(p)
        try? context.save()
        newPlayerName = ""
    }
}
