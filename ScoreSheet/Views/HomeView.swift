import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]

    @State private var showSetup = false
    @State private var toDelete: TableSession? = nil
    @AppStorage(AppSettingsKey.storeArchivedAt) private var storeArchivedAt: Double = 0
    private let vm = HomeViewModel()

    private var recent: [TableSession] { Array(sessions.prefix(3)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {

                // 表紙タイトル
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("スコアシート")
                        .font(AppFont.heading(28))
                        .foregroundStyle(Theme.ink)
                    Text("麻雀の記録帳")
                        .font(AppFont.body(14))
                        .foregroundStyle(Theme.inkSecond)
                }
                .padding(.top, Space.sm)

                // データベースを作り直したときの案内
                storeArchivedNotice

                // 新規ゲーム（主役）
                Button { showSetup = true } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: "square.and.pencil")
                        Text("新しいゲームをはじめる")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                // インデックス（メニュー）
                VStack(spacing: 0) {
                    indexRow(icon: "clock.arrow.circlepath", title: "過去のゲーム", route: .history)
                    HairlineRule().padding(.leading, 44)
                    indexRow(icon: "tag", title: "タグ別成績", route: .tags)
                    HairlineRule().padding(.leading, 44)
                    indexRow(icon: "person.2", title: "プレイヤー", route: .players)
                    HairlineRule().padding(.leading, 44)
                    indexRow(icon: "slider.horizontal.3", title: "設定", route: .settings)
                }
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Theme.rule, lineWidth: Theme.hairline))

                // 直近のゲーム
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "直近のゲーム")
                        VStack(spacing: Space.md) {
                            ForEach(recent) { session in
                                Button { path.append(session) } label: {
                                    recentRow(session)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { toDelete = session } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        // ホームまで戻ってきた＝続きから開く対象はもうない。
        .onAppear { UserDefaults.standard.removeObject(forKey: AppSettingsKey.resumeSessionID) }
        .sheet(isPresented: $showSetup) {
            TableSetupView { session in
                context.insert(session)
                try? context.save()
                showSetup = false
                path.append(session)
            }
        }
        .confirmationDialog("このゲームを削除しますか？", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }
        ), titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                if let s = toDelete { context.delete(s); try? context.save() }
                toDelete = nil
            }
            Button("キャンセル", role: .cancel) { toDelete = nil }
        }
    }

    /// 保存データが開けず作り直したときに出す案内。
    /// 黙って空の状態で始まると「消えた」ように見えるため、復元への導線を示す。
    @ViewBuilder
    private var storeArchivedNotice: some View {
        if storeArchivedAt > 0 {
            NoteCard(padding: Space.lg) {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(spacing: Space.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.accentYellow)
                        Text("保存データを読み込めませんでした")
                            .font(AppFont.body(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Text(archivedNoticeText)
                        .font(AppFont.body(13))
                        .foregroundStyle(Theme.inkSecond)
                    HStack(spacing: Space.md) {
                        NavigationLink(value: HomeRoute.settings) {
                            Text("バックアップから復元")
                                .font(AppFont.body(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Theme.accent))
                        }
                        .buttonStyle(.plain)
                        Button { storeArchivedAt = 0 } label: {
                            Text("閉じる")
                                .font(AppFont.body(14, weight: .semibold))
                                .foregroundStyle(Theme.inkSecond)
                                .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var archivedNoticeText: String {
        let when = Date(timeIntervalSince1970: storeArchivedAt)
            .formatted(.dateTime.year().month().day().hour().minute())
        return "\(when)に、開けなくなった保存データを端末内へ退避して、新しく作り直しました。"
            + "以前のゲームは表示されませんが、バックアップを書き出してあれば設定から復元できます。"
    }

    private func indexRow(icon: String, title: String, route: HomeRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.mutedBlue)
                    .frame(width: 28)
                Text(title).font(AppFont.body(16)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.vertical, Space.lg)
            .padding(.horizontal, Space.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recentRow(_ session: TableSession) -> some View {
        NoteCard(padding: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text(session.gameType.displayName)
                        .font(AppFont.label(12))
                        .foregroundStyle(Theme.mutedBlue)
                        .padding(.horizontal, Space.sm).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: Radius.small).fill(Theme.sunken))
                    Spacer()
                    Text(session.date, format: .dateTime.month().day())
                        .font(AppFont.body(13)).foregroundStyle(Theme.inkFaint)
                }
                Text(session.participants.map(\.name).joined(separator: "・"))
                    .font(AppFont.body(15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(session.rounds.count)回戦")
                    .font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
            }
        }
    }
}
