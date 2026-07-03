import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]

    @State private var showSetup = false
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

                // 新規卓（主役）
                Button { showSetup = true } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: "square.and.pencil")
                        Text("新規卓をはじめる")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                // インデックス（メニュー）
                VStack(spacing: 0) {
                    indexRow(icon: "clock.arrow.circlepath", title: "過去の卓", route: .history)
                    HairlineRule().padding(.leading, 44)
                    indexRow(icon: "person.2", title: "メンバー", route: .players)
                    HairlineRule().padding(.leading, 44)
                    indexRow(icon: "slider.horizontal.3", title: "設定", route: .settings)
                }
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Theme.rule, lineWidth: Theme.hairline))

                // 直近の卓
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "直近の卓")
                        VStack(spacing: Space.md) {
                            ForEach(recent) { session in
                                Button { path.append(session) } label: {
                                    recentRow(session)
                                }
                                .buttonStyle(.plain)
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
        .sheet(isPresented: $showSetup) {
            TableSetupView { session in
                context.insert(session)
                try? context.save()
                showSetup = false
                path.append(session)
            }
        }
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
