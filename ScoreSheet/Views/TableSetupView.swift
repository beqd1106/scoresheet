import SwiftUI
import SwiftData

struct TableSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var roster: [Player]

    @AppStorage(AppSettingsKey.defaultGameType) private var defaultGameTypeRaw = GameType.yonma.rawValue
    @AppStorage(AppSettingsKey.pointCoefficientPer1000) private var defaultPer1000 = AppDefaults.pointCoefficientPer1000
    @AppStorage(AppSettingsKey.chipPointCoefficient) private var defaultChip = AppDefaults.chipPointCoefficient

    @State private var vm = TableSetupViewModel()
    @State private var newPlayerName = ""
    @State private var newTag = ""

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

                    // 種別
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "種別")
                        Picker("種別", selection: $vm.gameType) {
                            ForEach(GameType.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: vm.gameType) { _, _ in vm.normalizeSelection() }
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
                vm.gameType = GameType(rawValue: defaultGameTypeRaw) ?? .yonma
                vm.pointCoefficientPer1000 = defaultPer1000
                vm.chipPointCoefficient = defaultChip
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
