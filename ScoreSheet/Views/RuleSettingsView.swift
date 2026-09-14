import SwiftUI
import SwiftData

// MARK: - ルール編集本体（新規作成時とゲーム設定の両方で使う）

struct RuleEditor: View {
    @Binding var rule: GameRule
    let gameType: GameType

    private var n: Int { gameType.playerCount }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            presetSection
            basicSection
            umaSection
            penaltySection
            previewSection
        }
    }

    // MARK: プリセット

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "プリセット")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.sm) {
                    ForEach(RulePreset.all) { preset in
                        Button {
                            rule = preset.make(gameType)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(AppFont.body(14, weight: .semibold))
                                    .foregroundStyle(isActive(preset) ? Color.white : Theme.ink)
                                Text(preset.detail)
                                    .font(AppFont.body(11))
                                    .foregroundStyle(isActive(preset) ? Color.white.opacity(0.85) : Theme.inkFaint)
                            }
                            .padding(.horizontal, Space.md)
                            .padding(.vertical, Space.sm)
                            .frame(minWidth: 132, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .fill(isActive(preset) ? Theme.accent : Theme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .stroke(isActive(preset) ? Color.clear : Theme.rule, lineWidth: Theme.hairline)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func isActive(_ preset: RulePreset) -> Bool { preset.make(gameType) == rule }

    // MARK: 基本

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "基本")
            NoteCard {
                VStack(spacing: Space.lg) {
                    stepperRow(title: "配給原点", value: $rule.startingPoints,
                               range: 10000...100000, step: 1000, unit: "点")
                    HairlineRule()
                    stepperRow(title: "返し点", value: $rule.returnPoints,
                               range: 10000...100000, step: 1000, unit: "点")
                    HairlineRule()
                    HStack {
                        Text("オカ").font(AppFont.body(15)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(okaLabel)
                            .font(AppFont.number(15, weight: .semibold))
                            .foregroundStyle(rule.okaPoint(playerCount: n) == 0 ? Theme.inkFaint : Theme.accent)
                    }
                    HairlineRule()
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HStack {
                            Text("1000点未満の端数").font(AppFont.body(15)).foregroundStyle(Theme.ink)
                            Spacer()
                        }
                        Picker("端数", selection: $rule.rounding) {
                            ForEach(RoundingMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            Text("返し点が配給原点より大きいと、その差の合計（オカ）がトップに加算されます。")
                .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
        }
    }

    private var okaLabel: String {
        let oka = rule.okaPoint(playerCount: n)
        return oka == 0 ? "なし" : "トップ \(oka.signedPointString)pt"
    }

    // MARK: ウマ

    private var umaSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "ウマ（順位点）")
            NoteCard {
                VStack(spacing: Space.lg) {
                    ForEach(Array(0..<n), id: \.self) { i in
                        if i > 0 { HairlineRule() }
                        HStack {
                            RankBadge(rank: i + 1, size: 24)
                            Text("\(i + 1)位").font(AppFont.body(15)).foregroundStyle(Theme.ink)
                            Spacer()
                            Stepper("", value: umaBinding(i), in: -100...100, step: 5).labelsHidden()
                            Text(umaBinding(i).wrappedValue.signedPointString)
                                .font(AppFont.number(16, weight: .semibold))
                                .foregroundStyle(Theme.pointColor(umaBinding(i).wrappedValue))
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
            if umaSum != 0 {
                Text("ウマの合計が \(umaSum.signedPointString)pt です。通常は 0 になるように設定します。")
                    .font(AppFont.body(12)).foregroundStyle(Theme.accentYellow)
            }
        }
    }

    private var umaSum: Int { rule.normalizedUma(playerCount: n).reduce(0, +) }

    private func umaBinding(_ i: Int) -> Binding<Int> {
        Binding(
            get: {
                let u = rule.normalizedUma(playerCount: n)
                return i < u.count ? u[i] : 0
            },
            set: { newValue in
                var u = rule.normalizedUma(playerCount: n)
                guard i < u.count else { return }
                u[i] = newValue
                rule.uma = u
            }
        )
    }

    // MARK: 罰符

    private var penaltySection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "罰符")

            penaltyCard(
                title: "トビ（ハコ）",
                note: "持ち点がマイナスになった人が支払います。",
                isOn: $rule.tobiEnabled,
                amount: $rule.tobiPenalty,
                payee: $rule.tobiPayee,
                payeeOptions: PenaltyPayee.tobiCases,
                unit: $rule.tobiUnit
            ) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("0点ちょうどの扱い").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                    Picker("0点ちょうど", selection: $rule.tobiIncludesZero) {
                        Text("トビにしない").tag(false)
                        Text("トビにする").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }

            penaltyCard(
                title: "ヤキトリ",
                note: "その回戦で1度も和了できなかった人が支払います。対象は回戦ごとに指定します。",
                isOn: $rule.yakitoriEnabled,
                amount: $rule.yakitoriPenalty,
                payee: $rule.yakitoriPayee,
                unit: $rule.yakitoriUnit
            ) { EmptyView() }

            penaltyCard(
                title: "クビ",
                note: "基準点に届かなかった人が支払います（条件は最下位にも変えられます）。",
                isOn: $rule.kubiEnabled,
                amount: $rule.kubiPenalty,
                payee: $rule.kubiPayee,
                unit: $rule.kubiUnit
            ) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("条件").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                    Picker("条件", selection: $rule.kubiCondition) {
                        ForEach(KubiCondition.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if rule.kubiCondition == .belowThreshold {
                        stepperRow(title: "基準点", value: $rule.kubiThreshold,
                                   range: 0...60000, step: 1000, unit: "点")
                        Text("\(rule.kubiThreshold)点に届かなかった人が \(rule.kubiPenalty)pt を払います（複数人いれば全員）。")
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    }
                }
            }
        }
    }

    private func penaltyCard<Extra: View>(title: String,
                                          note: String,
                                          isOn: Binding<Bool>,
                                          amount: Binding<Int>,
                                          payee: Binding<PenaltyPayee>,
                                          payeeOptions: [PenaltyPayee] = PenaltyPayee.standardCases,
                                          unit: Binding<PenaltyUnit>,
                                          @ViewBuilder extra: () -> Extra) -> some View {
        NoteCard {
            VStack(alignment: .leading, spacing: Space.md) {
                Toggle(isOn: isOn) {
                    Text(title).font(AppFont.body(15, weight: .semibold)).foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)

                Text(note).font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)

                if isOn.wrappedValue {
                    HairlineRule()
                    stepperRow(title: "罰符", value: amount, range: 0...200, step: 5, unit: "pt")
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("受け取り").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                        Picker("受け取り", selection: payee) {
                            ForEach(payeeOptions) { Text($0.shortLabel).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(payee.wrappedValue == .buster
                             ? "飛ばした人が受け取ります。誰が飛ばしたかは、各回戦で回戦番号をタップして名前で指定します（未指定のあいだはトップが受け取ります）。"
                             : payee.wrappedValue.displayName + "。")
                            .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    }

                    // 受け取る人が複数いるときだけ、払い方で金額が変わる。
                    if payee.wrappedValue == .others {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("払い方").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                            Picker("払い方", selection: unit) {
                                ForEach(PenaltyUnit.allCases) { Text($0.displayName).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text(unit.wrappedValue.detail(amount: amount.wrappedValue, receivers: n - 1))
                                .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                        }
                    }
                    extra()
                }
            }
        }
    }

    // MARK: プレビュー

    private var previewSection: some View {
        let scores = GameRulePreview.sampleScores(for: gameType, rule: rule)
        let ids = (0..<n).map { _ in UUID() }
        let settlements = ScoreCalculator.settle(participantIDs: ids,
                                                 rawScores: scores,
                                                 yakitoriFlags: Array(repeating: false, count: n),
                                                 rule: rule)
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "この設定での計算例")
            NoteCard {
                VStack(spacing: Space.sm) {
                    ForEach(Array(settlements.enumerated()), id: \.offset) { idx, s in
                        if idx > 0 { HairlineRule() }
                        HStack(spacing: Space.md) {
                            RankBadge(rank: s.rank, size: 22)
                            Text("\(scores[idx]) 点")
                                .font(AppFont.number(14))
                                .foregroundStyle(Theme.inkSecond)
                            Spacer()
                            Text(s.total.signedPointString)
                                .font(AppFont.number(17, weight: .bold))
                                .foregroundStyle(Theme.pointColor(s.total))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: 部品

    private func stepperRow(title: String, value: Binding<Int>,
                            range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack {
            Text(title).font(AppFont.body(15)).foregroundStyle(Theme.ink)
            Spacer()
            Stepper("", value: value, in: range, step: step).labelsHidden()
            Text("\(value.wrappedValue)\(unit)")
                .font(AppFont.number(16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 82, alignment: .trailing)
        }
    }
}

/// プレビュー用のサンプル持ち点。
enum GameRulePreview {
    static func sampleScores(for gameType: GameType, rule: GameRule) -> [Int] {
        let n = gameType.playerCount
        let total = rule.expectedTotalScore(playerCount: n)
        // 見本として差のついた配点をつくり、最後の1人で合計を帳尻合わせする。
        let spread = n == 3 ? [15000, 0, -12000] : [13000, 3000, -6000, -10000]
        var scores = (0..<n).map { rule.startingPoints + spread[$0] }
        let diff = total - scores.reduce(0, +)
        scores[n - 1] += diff
        return scores
    }
}

// MARK: - ゲーム設定からルールを開くシート

struct RuleSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var session: TableSession

    @State private var draft = GameRule()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                RuleEditor(rule: $draft, gameType: session.gameType)
                    .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle("対局ルール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        session.rule = draft
                        session.updatedAt = Date()
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                draft = session.rule
                loaded = true
            }
        }
    }
}
