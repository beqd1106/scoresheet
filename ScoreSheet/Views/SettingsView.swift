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
    @AppStorage(AppSettingsKey.savedRules) private var savedRulesJSON = ""

    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var players: [Player]
    @Query(sort: \TableSession.date) private var sessions: [TableSession]

    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showImporter = false
    /// ファイル選択の用途（1つの fileImporter を使い回す。複数付けると片方しか動かないため）。
    @State private var importKind: ImportKind = .backup
    @State private var csvPreview: CSVImportPreview?
    @State private var backupMessage: String?
    @State private var backupFailed = false
    @State private var autoBackups: [AutoBackupSnapshot] = []
    @State private var showResetChoice = false
    @State private var pendingReset: DataResetService.AllScope?
    @State private var resetMessage: String?

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

                // 保存したルール
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "保存したルール")
                    NavigationLink { SavedRulesView() } label: {
                        HStack(spacing: Space.md) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 16)).foregroundStyle(Theme.mutedBlue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("保存したルールを管理").font(AppFont.body(16)).foregroundStyle(Theme.ink)
                                Text(savedRuleCountText).font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                        }
                        .padding(Space.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Theme.rule, lineWidth: Theme.hairline))
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
                                detail: "ゲーム\(sessions.count)件・プレイヤー\(players.count)人・保存したルール") {
                            exportBackup()
                        }
                        HairlineRule().padding(.leading, 44)
                        dataRow(icon: "square.and.arrow.down", title: "バックアップから復元",
                                detail: "同じゲームは重複せず、足りない分だけ追加します") {
                            importKind = .backup
                            showImporter = true
                        }
                        HairlineRule().padding(.leading, 44)
                        dataRow(icon: "tablecells", title: "他アプリのCSVを取り込む",
                                detail: "麻雀スコアアプリの成績CSV（点数・スコア・チップ列）に対応") {
                            importKind = .csv
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

                    autoBackupList
                }

                // リセット
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: "リセット")
                    Button { showResetChoice = true } label: {
                        HStack(spacing: Space.md) {
                            Image(systemName: "trash")
                                .font(.system(size: 16)).foregroundStyle(Theme.negative)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("データをリセット").font(AppFont.body(16)).foregroundStyle(Theme.negative)
                                Text("ゲームの記録だけ、またはすべてを消します")
                                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                            }
                            Spacer()
                        }
                        .padding(Space.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(sessions.isEmpty && players.isEmpty && SavedRuleStore.decode(savedRulesJSON).isEmpty)
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Theme.rule, lineWidth: Theme.hairline))
                    if let resetMessage {
                        Text(resetMessage)
                            .font(AppFont.body(12))
                            .foregroundStyle(backupFailed ? Theme.accentRed : Theme.accent)
                    }
                    Text("プレイヤーごとに消したいときは「プレイヤー」画面のゴミ箱から。消す前の状態は自動バックアップに残るので、間違えても上の一覧から戻せます。")
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
        .onAppear(perform: reloadAutoBackups)
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importKind == .csv
                        ? [.commaSeparatedText, .plainText, .text]
                        : [.json],
                      allowsMultipleSelection: false) { result in
            switch importKind {
            case .backup: handleImport(result)
            case .csv:    handleCSVSelection(result)
            }
        }
        .confirmationDialog("何を消しますか？", isPresented: $showResetChoice, titleVisibility: .visible) {
            Button("ゲームの記録だけ（\(sessions.count)件）", role: .destructive) { pendingReset = .gamesOnly }
            Button("すべて（ゲーム・プレイヤー・保存したルール）", role: .destructive) { pendingReset = .everything }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("「ゲームの記録だけ」ならプレイヤーと保存したルールは残ります。")
        }
        .alert("本当に消しますか？", isPresented: Binding(
            get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } }
        )) {
            Button("キャンセル", role: .cancel) { pendingReset = nil }
            Button("消す", role: .destructive) {
                if let scope = pendingReset { reset(scope) }
                pendingReset = nil
            }
        } message: {
            Text(pendingReset == .everything
                 ? "ゲーム\(sessions.count)件・プレイヤー\(players.count)人・保存したルールをすべて消し、最初の状態に戻します。"
                 : "ゲーム\(sessions.count)件をすべて消します。プレイヤーと保存したルールは残ります。")
        }
        .sheet(item: $csvPreview) { preview in
            CSVImportSheet(preview: preview) { tag in
                applyCSV(preview, tag: tag)
            }
        }
    }

    private var savedRuleCountText: String {
        let count = SavedRuleStore.decode(savedRulesJSON).count
        return count == 0 ? "名前・並び順・「いつもの」を設定できます" : "\(count)件・名前や中身の編集、並び替え、削除"
    }

    /// 復元結果の文言。
    private func restoreMessage(_ summary: BackupService.RestoreSummary) -> String {
        "復元しました：ゲーム\(summary.addedSessions)件・プレイヤー\(summary.addedPlayers)人"
            + (summary.addedRules > 0 ? "・ルール\(summary.addedRules)件" : "")
            + "を追加"
            + (summary.skippedSessions > 0 ? "（重複\(summary.skippedSessions)件はそのまま）" : "")
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

    /// 端末内に自動で残しているバックアップの一覧。
    @ViewBuilder
    private var autoBackupList: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("自動バックアップ（最新\(AutoBackupService.maxGenerations)件）")
                .font(AppFont.body(13, weight: .semibold)).foregroundStyle(Theme.inkSecond)
                .padding(.top, Space.sm)

            if autoBackups.isEmpty {
                Text("まだありません。アプリを閉じたときに自動で作られます。")
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(autoBackups.enumerated()), id: \.element.id) { idx, snap in
                        if idx > 0 { HairlineRule().padding(.leading, Space.lg) }
                        HStack(spacing: Space.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.date.formatted(.dateTime.month().day().hour().minute()))
                                    .font(AppFont.body(14, weight: .medium)).foregroundStyle(Theme.ink)
                                Text("ゲーム\(snap.sessionCount)件・プレイヤー\(snap.playerCount)人")
                                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                            }
                            Spacer()
                            Button { restoreAuto(snap) } label: {
                                Text("復元")
                                    .font(AppFont.body(13, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                                    .background(RoundedRectangle(cornerRadius: Radius.control)
                                        .fill(Theme.accent.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(Space.lg)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Theme.rule, lineWidth: Theme.hairline))

                Text("復元しても今あるゲームは消えません。足りないものだけ戻します。")
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func reloadAutoBackups() {
        autoBackups = AutoBackupService.list()
    }

    private func restoreAuto(_ snapshot: AutoBackupSnapshot) {
        do {
            let summary = try AutoBackupService.restore(snapshot, into: context)
            backupFailed = false
            backupMessage = restoreMessage(summary)
        } catch {
            backupFailed = true
            backupMessage = "復元できませんでした。"
        }
    }

    private func reset(_ scope: DataResetService.AllScope) {
        backupMessage = nil
        do {
            let summary = try DataResetService.resetAll(scope: scope, context: context)
            backupFailed = false
            resetMessage = scope == .everything
                ? "すべて消しました（ゲーム\(summary.deletedSessions)件・プレイヤー\(summary.deletedPlayers)人）。"
                : "ゲームの記録\(summary.deletedSessions)件を消しました。"
        } catch {
            backupFailed = true
            resetMessage = "リセットできませんでした。もう一度お試しください。"
        }
        reloadAutoBackups()
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
            backupMessage = restoreMessage(summary)
        } catch {
            backupFailed = true
            backupMessage = "復元できませんでした。スコアシートで書き出したファイルか確認してください。"
        }
    }

    private func handleCSVSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            csvPreview = try CSVImportService.parse(data)
            backupMessage = nil
        } catch let error as CSVImportError {
            backupFailed = true
            backupMessage = error.errorDescription
        } catch {
            backupFailed = true
            backupMessage = "ファイルを開けませんでした。"
        }
    }

    private func applyCSV(_ preview: CSVImportPreview, tag: String) {
        do {
            let summary = try CSVImportService.apply(preview, tag: tag, into: context)
            backupFailed = false
            backupMessage = "取り込みました：ゲーム\(summary.addedSessions)件"
                + (summary.addedPlayers > 0 ? "・新しいプレイヤー\(summary.addedPlayers)人" : "")
                + (summary.skippedDuplicates > 0 ? "（取り込み済みの\(summary.skippedDuplicates)件は飛ばしました）" : "")
        } catch {
            backupFailed = true
            backupMessage = "取り込みに失敗しました。もう一度お試しください。"
        }
        csvPreview = nil
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

/// 設定画面のファイル選択の用途。
private enum ImportKind { case backup, csv }
