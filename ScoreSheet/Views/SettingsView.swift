import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(AppSettingsKey.defaultGameType) private var defaultGameTypeRaw = GameType.yonma.rawValue
    @AppStorage(AppSettingsKey.pointCoefficientPer1000) private var per1000 = AppDefaults.pointCoefficientPer1000
    @AppStorage(AppSettingsKey.chipPointCoefficient) private var chipCoeff = AppDefaults.chipPointCoefficient
    @AppStorage(AppSettingsKey.quickPoints) private var quickPointsRaw = "50,100,150,200,300"
    @AppStorage(AppSettingsKey.appearance) private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(AppSettingsKey.defaultInputMode) private var defaultInputModeRaw = InputMode.point.rawValue

    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var players: [Player]
    @Query(sort: \TableSession.date) private var sessions: [TableSession]

    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showImporter = false
    @State private var backupMessage: String?
    @State private var backupFailed = false

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

                // デフォルト入力方式
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "デフォルトの入力方式")
                    Picker("入力方式", selection: $defaultInputModeRaw) {
                        ForEach(InputMode.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text((InputMode(rawValue: defaultInputModeRaw) ?? .point).summary)
                        .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                }

                // 係数
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "ポイント係数")
                    NoteCard {
                        VStack(spacing: Space.lg) {
                            coeffRow("チップ 1枚あたり", $chipCoeff, AppDefaults.chipStep, AppDefaults.chipMax)
                            HairlineRule()
                            coeffRow("1000点あたり", $per1000, AppDefaults.per1000Step, AppDefaults.per1000Max)
                        }
                    }
                }

                // よく使うポイント
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionLabel(text: "よく使うポイント（カンマ区切り）")
                    TextField("50,100,150,200,300", text: $quickPointsRaw)
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

                // データ（バックアップ）
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "データ")
                    VStack(spacing: 0) {
                        dataRow(icon: "square.and.arrow.up", title: "バックアップを書き出す",
                                detail: "ゲーム\(sessions.count)件・プレイヤー\(players.count)人") {
                            exportBackup()
                        }
                        HairlineRule().padding(.leading, 44)
                        dataRow(icon: "square.and.arrow.down", title: "バックアップから復元",
                                detail: "同じゲームは重複せず、足りない分だけ追加します") {
                            showImporter = true
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Theme.rule, lineWidth: Theme.hairline))

                    if let backupMessage {
                        Text(backupMessage)
                            .font(AppFont.body(12))
                            .foregroundStyle(backupFailed ? Theme.accentRed : Theme.accent)
                    }
                    Text("入力は自動保存されますが、端末の故障や機種変更に備えて時々書き出しておくと安心です。")
                        .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
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
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    // MARK: データ操作

    private func dataRow(icon: String, title: String, detail: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.mutedBlue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.body(16)).foregroundStyle(Theme.ink)
                    Text(detail).font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(Space.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func exportBackup() {
        guard let url = BackupService.writeTempFile(players: players, sessions: sessions) else {
            backupFailed = true
            backupMessage = "書き出しに失敗しました。空き容量を確認してください。"
            return
        }
        backupFailed = false
        backupMessage = nil
        shareItems = [url]
        showShare = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            // 他アプリ（ファイル）から渡された URL は明示的にアクセス権を取る。
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let backup = try BackupService.decode(data)
            let summary = try BackupService.restore(backup, into: context)
            backupFailed = false
            backupMessage = "復元しました：ゲーム\(summary.addedSessions)件・プレイヤー\(summary.addedPlayers)人を追加"
                + (summary.skippedSessions > 0 ? "（重複\(summary.skippedSessions)件はそのまま）" : "")
        } catch {
            backupFailed = true
            backupMessage = "復元できませんでした。スコアシートで書き出したファイルか確認してください。"
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
}
