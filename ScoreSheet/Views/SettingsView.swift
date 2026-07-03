import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKey.defaultGameType) private var defaultGameTypeRaw = GameType.yonma.rawValue
    @AppStorage(AppSettingsKey.pointCoefficientPer1000) private var per1000 = AppDefaults.pointCoefficientPer1000
    @AppStorage(AppSettingsKey.chipPointCoefficient) private var chipCoeff = AppDefaults.chipPointCoefficient
    @AppStorage(AppSettingsKey.quickPoints) private var quickPointsRaw = "5,10,15,20,30"
    @AppStorage(AppSettingsKey.appearance) private var appearanceRaw = Appearance.system.rawValue

    private var defaultGameType: Binding<GameType> {
        Binding(get: { GameType(rawValue: defaultGameTypeRaw) ?? .yonma },
                set: { defaultGameTypeRaw = $0.rawValue })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {

                // デフォルト種別
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "デフォルトの種別")
                    Picker("種別", selection: defaultGameType) {
                        ForEach(GameType.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                // 係数
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "ポイント係数")
                    NoteCard {
                        VStack(spacing: Space.lg) {
                            coeffRow("チップ 1枚あたり", $chipCoeff)
                            HairlineRule()
                            coeffRow("1000点あたり（補助）", $per1000)
                        }
                    }
                }

                // よく使うポイント
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionLabel(text: "よく使うポイント（カンマ区切り）")
                    TextField("5,10,15,20,30", text: $quickPointsRaw)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.plain)
                        .padding(Space.md)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.sunken))
                    Text("回戦入力のクイックボタンに表示されます。")
                        .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                }

                // 外観
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "外観")
                    Picker("外観", selection: $appearanceRaw) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                // 表現ポリシー
                NoteCard {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("このアプリについて").font(AppFont.label(13)).foregroundStyle(Theme.inkSecond)
                        Text("スコア管理・成績記録用アプリです。ポイント係数は成績換算のための数値で、実金額や精算を表すものではありません。")
                            .font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func coeffRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(AppFont.body(15)).foregroundStyle(Theme.ink)
            Spacer()
            Stepper("", value: value, in: 0...100, step: 1).labelsHidden()
            Text("\(Int(value.wrappedValue)) pt")
                .font(AppFont.number(16, weight: .semibold)).foregroundStyle(Theme.mutedBlue)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
