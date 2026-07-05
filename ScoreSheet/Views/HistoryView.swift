import SwiftUI
import SwiftData

struct HistoryView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var context
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]

    enum Mode: String, CaseIterable, Identifiable { case list = "リスト", calendar = "カレンダー"; var id: String { rawValue } }
    @State private var mode: Mode = .list
    @State private var toDelete: TableSession? = nil
    @State private var settingsTarget: TableSession? = nil

    private let cal = Calendar.current
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: Date())

    private let vm = HistoryViewModel()

    private var sessionsByDay: [Date: [TableSession]] {
        Dictionary(grouping: sessions) { cal.startOfDay(for: $0.date) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !sessions.isEmpty {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(Space.lg)
            }

            if sessions.isEmpty {
                ScrollView {
                    EmptyNote(title: "履歴がありません",
                              message: "ゲームをはじめると、ここに記録が残ります。",
                              systemImage: "clock")
                    .padding(.top, Space.xxxl)
                }
            } else if mode == .list {
                listView
            } else {
                calendarView
            }
        }
        .background(NotePageBackground())
        .navigationTitle("過去のゲーム")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $settingsTarget) { GameSettingsSheet(session: $0) }
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

    // MARK: リスト

    private var listView: some View {
        List {
            ForEach(sessions) { session in
                Button { path.append(session) } label: { row(session) }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.lg, bottom: Space.xs, trailing: Space.lg))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { toDelete = session } label: { Label("削除", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { settingsTarget = session } label: { Label("設定", systemImage: "gearshape") }.tint(Theme.accent)
                    }
                    .contextMenu {
                        Button { settingsTarget = session } label: { Label("設定・タグを編集", systemImage: "gearshape") }
                        Button(role: .destructive) { toDelete = session } label: { Label("削除", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: カレンダー

    private var calendarView: some View {
        ScrollView {
            VStack(spacing: Space.lg) {
                // 月ナビ
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(monthTitle).font(AppFont.heading(17)).foregroundStyle(Theme.ink)
                    Spacer()
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Space.sm)

                // 曜日
                HStack(spacing: 0) {
                    ForEach(["日", "月", "火", "水", "木", "金", "土"], id: \.self) { w in
                        Text(w).font(AppFont.body(11, weight: .semibold))
                            .foregroundStyle(Theme.inkSecond).frame(maxWidth: .infinity)
                    }
                }
                // 日付グリッド
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 40) }
                    ForEach(monthDays, id: \.self) { date in dayCell(date) }
                }
                .padding(Space.md)
                .background(RoundedRectangle(cornerRadius: Radius.card).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Theme.rule, lineWidth: Theme.hairline))

                // 選択日のゲーム
                let dayGames = selectedDay.flatMap { sessionsByDay[$0] } ?? []
                VStack(alignment: .leading, spacing: Space.md) {
                    SectionLabel(text: selectedDayTitle)
                    if dayGames.isEmpty {
                        Text("この日のゲームはありません。").font(AppFont.body(14)).foregroundStyle(Theme.inkSecond)
                    } else {
                        ForEach(dayGames) { session in
                            Button { path.append(session) } label: { row(session) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { settingsTarget = session } label: { Label("設定・タグを編集", systemImage: "gearshape") }
                                    Button(role: .destructive) { toDelete = session } label: { Label("削除", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let day = cal.component(.day, from: date)
        let isSel = selectedDay.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let has = !(sessionsByDay[cal.startOfDay(for: date)] ?? []).isEmpty
        return VStack(spacing: 3) {
            Text("\(day)").font(AppFont.number(14, weight: isSel ? .bold : .regular))
                .foregroundStyle(isSel ? Theme.accent : Theme.ink)
            Circle().fill(has ? Theme.accent : .clear).frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Radius.small)
            .fill(isSel ? Theme.accent.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = cal.startOfDay(for: date) }
    }

    // MARK: カレンダー計算

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "yyyy年 M月"; return f.string(from: month)
    }
    private var selectedDayTitle: String {
        guard let d = selectedDay else { return "" }
        let f = DateFormatter(); f.dateFormat = "M月d日(E)"; f.locale = Locale(identifier: "ja_JP"); return f.string(from: d)
    }
    private var firstOfMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
    }
    private var leadingBlanks: Int { cal.component(.weekday, from: firstOfMonth) - 1 }
    private var monthDays: [Date] {
        let range = cal.range(of: .day, in: .month, for: month) ?? 1..<2
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: firstOfMonth) }
    }
    private func shiftMonth(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: month) { month = m }
    }

    // MARK: 行

    private func row(_ session: TableSession) -> some View {
        NoteCard {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack {
                    Text(session.gameType.displayName)
                        .font(AppFont.label(12)).foregroundStyle(Theme.mutedBlue)
                        .padding(.horizontal, Space.sm).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: Radius.small).fill(Theme.sunken))
                    Spacer()
                    Text(vm.dateText(session.date)).font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                }
                Text(session.participants.map(\.name).joined(separator: "・"))
                    .font(AppFont.body(15, weight: .medium)).foregroundStyle(Theme.ink)
                HStack(spacing: Space.md) {
                    Text("\(session.rounds.count)回戦").font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                    if let top = vm.topName(of: session) {
                        HStack(spacing: 4) {
                            RankBadge(rank: 1, size: 16)
                            Text(top).font(AppFont.body(13, weight: .medium)).foregroundStyle(Theme.ink)
                        }
                    }
                }
                if !session.tags.isEmpty {
                    FlowLayout(spacing: Space.xs) {
                        ForEach(session.tags, id: \.self) { TagChip(text: $0) }
                    }
                }
            }
        }
    }
}
