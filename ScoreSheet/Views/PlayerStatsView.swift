import SwiftUI
import SwiftData
import Charts

// MARK: - 絞り込みバー（一覧・詳細で共通）

/// 種別（すべて/四麻/三麻）・年・タグ・メンツで絞り込む。
struct StatsFilterBar: View {
    @Binding var filter: StatsFilter
    let years: [Int]
    var tags: [String] = []
    /// メンツ選びの候補。空ならメンツの絞り込みは出さない。
    var candidates: [Participant] = []

    @State private var showMemberPicker = false

    private var typeBinding: Binding<String> {
        Binding(get: { filter.gameType?.rawValue ?? "all" },
                set: { filter.gameType = GameType(rawValue: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Picker("種別", selection: typeBinding) {
                    Text("すべて").tag("all")
                    Text(GameType.yonma.displayName).tag(GameType.yonma.rawValue)
                    Text(GameType.sanma.displayName).tag(GameType.sanma.rawValue)
                }
                .pickerStyle(.segmented)

                Menu {
                    Button { filter.year = nil } label: {
                        if filter.year == nil { Label("全期間", systemImage: "checkmark") } else { Text("全期間") }
                    }
                    ForEach(years, id: \.self) { y in
                        Button { filter.year = y } label: {
                            if filter.year == y { Label("\(String(y))年", systemImage: "checkmark") } else { Text("\(String(y))年") }
                        }
                    }
                } label: {
                    pill(text: filter.year.map { "\(String($0))年" } ?? "全期間", icon: nil, active: filter.year != nil)
                }
            }

            if !tags.isEmpty || !candidates.isEmpty || filter.tag != nil || !filter.memberIDs.isEmpty {
                HStack(spacing: Space.sm) {
                    if !tags.isEmpty || filter.tag != nil {
                        Menu {
                            Button { filter.tag = nil } label: {
                                if filter.tag == nil { Label("すべてのタグ", systemImage: "checkmark") } else { Text("すべてのタグ") }
                            }
                            ForEach(tags, id: \.self) { t in
                                Button { filter.tag = t } label: {
                                    if filter.tag == t { Label(t, systemImage: "checkmark") } else { Text(t) }
                                }
                            }
                        } label: {
                            pill(text: filter.tag ?? "タグ：すべて", icon: "tag", active: filter.tag != nil)
                        }
                    }
                    if !candidates.isEmpty {
                        Button { showMemberPicker = true } label: {
                            pill(text: memberLabel, icon: "person.2", active: !filter.memberIDs.isEmpty)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    if filter.tag != nil || !filter.memberIDs.isEmpty {
                        Button {
                            filter.tag = nil
                            filter.memberIDs = []
                        } label: {
                            Text("解除").font(AppFont.body(13, weight: .semibold)).foregroundStyle(Theme.inkSecond)
                                .frame(minWidth: 44, minHeight: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showMemberPicker) {
            MemberPickerSheet(candidates: candidates, selected: filter.memberIDs) { filter.memberIDs = $0 }
                .presentationDetents([.medium, .large])
        }
    }

    private var memberLabel: String {
        guard !filter.memberIDs.isEmpty else { return "メンツ：全員" }
        let names = filter.memberIDs.compactMap { id in candidates.first { $0.id == id }?.name }
        return names.count <= 3 ? names.joined(separator: "・") : "\(names.prefix(2).joined(separator: "・"))ほか\(names.count - 2)人"
    }

    private func pill(text: String, icon: String?, active: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
            Text(text).font(AppFont.body(13, weight: .semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(active ? Color.white : Theme.accent)
        .padding(.horizontal, Space.md)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Radius.small)
            .fill(active ? Theme.accent : Theme.accent.opacity(0.10)))
    }
}

// MARK: - メンツ選び

/// 集計に使うメンツを選ぶ。選んだ全員が入っているゲームだけを数える。
struct MemberPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [Participant]
    let onDone: ([UUID]) -> Void
    @State private var picked: [UUID]

    init(candidates: [Participant], selected: [UUID], onDone: @escaping ([UUID]) -> Void) {
        self.candidates = candidates
        self.onDone = onDone
        _picked = State(initialValue: selected)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("選んだ人が全員そろったゲームだけを集計して、その人たちの成績を並べます。")
                        .font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, p in
                            if idx > 0 { HairlineRule().padding(.leading, Space.lg) }
                            Button { toggle(p.id) } label: {
                                HStack(spacing: Space.md) {
                                    PlayerDot(colorHex: p.colorHex, size: 12)
                                    Text(p.name).font(AppFont.body(16)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: picked.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(picked.contains(p.id) ? Theme.accent : Theme.inkFaint)
                                }
                                .padding(.horizontal, Space.lg)
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(Theme.rule, lineWidth: Theme.hairline))
                }
                .padding(Space.lg)
            }
            .background(NotePageBackground())
            .navigationTitle("メンツで絞り込む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("全員") { picked = [] }.disabled(picked.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") { onDone(picked); dismiss() }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let i = picked.firstIndex(of: id) { picked.remove(at: i) } else { picked.append(id) }
    }
}

// MARK: - プレイヤー別成績（一覧）

struct PlayerStatsListView: View {
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]
    @Query(sort: \Player.createdAt) private var players: [Player]
    @State private var filter: StatsFilter
    private let title: String

    /// - Parameters:
    ///   - initialFilter: タグ別成績・最終結果から開くときの絞り込み
    ///   - title: 画面タイトル
    init(initialFilter: StatsFilter = StatsFilter(), title: String = "プレイヤー別成績") {
        _filter = State(initialValue: initialFilter)
        self.title = title
    }

    private var games: [StatsGame] { sessions.map(StatsGame.init(session:)) }
    private var roster: [UUID: (name: String, colorHex: String)] {
        Dictionary(players.map { ($0.id, (name: $0.name, colorHex: $0.colorHex)) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let allGames = games
        let stats = PlayerStatsCalculator.aggregate(games: allGames, filter: filter, roster: roster)
        let gameCount = allGames.filter { filter.includes($0) && !$0.rounds.isEmpty }.count

        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                StatsFilterBar(filter: $filter,
                               years: PlayerStatsCalculator.availableYears(allGames),
                               tags: PlayerStatsCalculator.availableTags(allGames),
                               candidates: PlayerStatsCalculator.memberCandidates(
                                   allGames, roster: players.map { ($0.id, $0.name, $0.colorHex) }))

                if stats.isEmpty {
                    NoteCard {
                        EmptyNote(title: allGames.isEmpty ? "まだ記録がありません" : "該当するゲームがありません",
                                  message: allGames.isEmpty
                                    ? "ゲームを記録すると、プレイヤーごとの通算成績がここに集まります。"
                                    : (filter.memberIDs.isEmpty
                                        ? "種別・期間・タグの絞り込みを変えてみてください。"
                                        : "選んだメンツが全員そろったゲームがありません。メンツや種別を変えてみてください。"),
                                  systemImage: "person.crop.rectangle.stack")
                    }
                } else {
                    Text(filter.memberIDs.isEmpty
                         ? "\(gameCount)ゲームを集計・総合ポイント順"
                         : "このメンツがそろった\(gameCount)ゲームを集計・総合ポイント順")
                        .font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)

                    VStack(spacing: Space.md) {
                        ForEach(Array(stats.enumerated()), id: \.element.id) { idx, s in
                            NavigationLink {
                                PlayerStatsDetailView(playerID: s.id, initialFilter: filter)
                            } label: {
                                row(rank: idx + 1, s)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(rank: Int, _ s: PlayerStats) -> some View {
        NoteCard {
            VStack(spacing: Space.md) {
                HStack(spacing: Space.md) {
                    RankBadge(rank: rank, size: 28)
                    PlayerDot(colorHex: s.colorHex, size: 11)
                    Text(s.name)
                        .font(AppFont.body(17, weight: .semibold)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.sm)
                    Text(s.grandTotal.signedPointString)
                        .font(AppFont.number(22, weight: .bold))
                        .foregroundStyle(Theme.pointColor(s.grandTotal))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                }
                HairlineRule()
                HStack {
                    StatCell(title: "回戦", value: "\(s.rounds)")
                    StatDivider()
                    StatCell(title: "平均順位", value: String(format: "%.2f", s.averageRank))
                    StatDivider()
                    StatCell(title: "トップ率", value: s.topRate.percentString)
                    StatDivider()
                    StatCell(title: "ラス率", value: s.lastRate.percentString)
                }
            }
        }
    }
}

// MARK: - プレイヤー別成績（詳細）

struct PlayerStatsDetailView: View {
    let playerID: UUID
    @State private var filter: StatsFilter

    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]
    @Query(sort: \Player.createdAt) private var players: [Player]
    @State private var showAllOpponents = false

    init(playerID: UUID, initialFilter: StatsFilter) {
        self.playerID = playerID
        _filter = State(initialValue: initialFilter)
    }

    private var games: [StatsGame] {
        sessions.filter { s in s.participants.contains { $0.id == playerID } }
            .map(StatsGame.init(session:))
    }
    private var roster: [UUID: (name: String, colorHex: String)] {
        Dictionary(players.map { ($0.id, (name: $0.name, colorHex: $0.colorHex)) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let allGames = games
        let stats = PlayerStatsCalculator.aggregate(games: allGames, filter: filter, roster: roster)
            .first { $0.id == playerID }

        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                StatsFilterBar(filter: $filter,
                               years: PlayerStatsCalculator.availableYears(allGames),
                               tags: PlayerStatsCalculator.availableTags(allGames),
                               candidates: PlayerStatsCalculator.memberCandidates(
                                   allGames, roster: players.map { ($0.id, $0.name, $0.colorHex) }))

                if let s = stats {
                    header(s)
                    kpiGrid(s)
                    opponentSection(s)
                    rankSection(s)
                    trendSection(s)
                    recordSection(s)
                    recentSection(s)
                } else {
                    NoteCard {
                        EmptyNote(title: "該当するゲームがありません",
                                  message: "種別・期間・タグ・メンツの絞り込みを変えてみてください。",
                                  systemImage: "chart.bar.xaxis")
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle(stats?.name ?? roster[playerID]?.name ?? "成績")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 見出し（主役：総合ポイント）

    private func header(_ s: PlayerStats) -> some View {
        NoteCard {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    PlayerDot(colorHex: s.colorHex, size: 12)
                    Text(s.name).font(AppFont.heading(20)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(s.games)ゲーム・\(s.rounds)回戦")
                        .font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("総合ポイント").font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                    Text(s.grandTotal.signedPointString)
                        .font(AppFont.number(36, weight: .bold))
                        .foregroundStyle(Theme.pointColor(s.grandTotal))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                HairlineRule()
                HStack {
                    StatCell(title: "対局ポイント", value: s.roundPointTotal.signedPointString)
                    StatDivider()
                    StatCell(title: "チップ", value: "\(s.chipCount.signedPointString)枚")
                    StatDivider()
                    StatCell(title: "ゲーム1位", value: "\(s.gameTops)回")
                }
            }
        }
    }

    // MARK: 指標

    private func kpiGrid(_ s: PlayerStats) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "回戦ごとの成績", systemImage: "square.grid.2x2")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 3),
                      spacing: Space.sm) {
                kpi("平均順位", String(format: "%.2f", s.averageRank))
                kpi("トップ率", s.topRate.percentString)
                kpi("連対率", s.rentaiRate.percentString)
                kpi("ラス率", s.lastRate.percentString)
                kpi("トビ率", s.tobiRate?.percentString ?? "—")
                kpi("平均素点", s.averageRawScore.map { "\($0)" } ?? "—")
            }
            if s.rawRounds < s.rounds {
                Text(s.rawRounds == 0
                     ? "トビ率・平均素点は、素点の記録がある回戦だけで計算します（ポイント入力のゲームは対象外）。"
                     : "トビ率・平均素点は、素点の記録がある\(s.rawRounds)回戦で計算しています。")
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func kpi(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppFont.body(11)).foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(AppFont.number(18, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .stroke(Theme.rule, lineWidth: Theme.hairline))
    }

    // MARK: 同卓した相手

    @ViewBuilder
    private func opponentSection(_ s: PlayerStats) -> some View {
        let all = s.opponents
        if !all.isEmpty {
            let limit = 8
            let shown = showAllOpponents ? all : Array(all.prefix(limit))
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(text: "同卓した相手", systemImage: "person.2")
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, o in
                        if idx > 0 { HairlineRule().padding(.leading, Space.lg) }
                        opponentRow(o)
                    }
                    if all.count > limit {
                        HairlineRule()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { showAllOpponents.toggle() }
                        } label: {
                            Text(showAllOpponents ? "閉じる" : "すべて表示（\(all.count)人）")
                                .font(AppFont.body(13, weight: .semibold)).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Theme.rule, lineWidth: Theme.hairline))
                Text("その人と同じゲームに入ったときの、\(s.name)さんの総合ポイント合計です。「上回り」は同じ回戦で相手より上の着順だった割合です。")
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func opponentRow(_ o: OpponentRecord) -> some View {
        HStack(spacing: Space.md) {
            PlayerDot(colorHex: o.colorHex, size: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(o.name).font(AppFont.body(15, weight: .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(o.games)ゲーム・平均\(String(format: "%.2f", o.averageRank))着・上回り\(o.rounds == 0 ? "—" : o.aboveRate.percentString)")
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: 2) {
                PointText(value: o.myGrandTotal, size: 16)
                Text("相手 \(o.theirGrandTotal.signedPointString)")
                    .font(AppFont.number(11)).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: 順位分布

    private func rankSection(_ s: PlayerStats) -> some View {
        let maxRank = max(filter.gameType?.playerCount ?? (s.rankCounts.keys.max() ?? 3), 3)
        let ranks = Array(1...maxRank)
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "順位の内訳", systemImage: "list.number")
            NoteCard {
                VStack(alignment: .leading, spacing: Space.md) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(ranks, id: \.self) { r in
                                let c = s.rankCounts[r] ?? 0
                                if c > 0 {
                                    Rectangle()
                                        .fill(Theme.rankColor(r))
                                        .frame(width: max(geo.size.width * CGFloat(c) / CGFloat(max(s.rounds, 1)) - 2, 2))
                                }
                            }
                        }
                    }
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    VStack(spacing: Space.sm) {
                        ForEach(ranks, id: \.self) { r in
                            let c = s.rankCounts[r] ?? 0
                            HStack(spacing: Space.sm) {
                                RankBadge(rank: r, size: 20)
                                Text("\(r)着").font(AppFont.body(14)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(c)回").font(AppFont.number(14, weight: .semibold)).foregroundStyle(Theme.ink)
                                Text(s.rounds == 0 ? "—" : (Double(c) / Double(s.rounds)).percentString)
                                    .font(AppFont.number(13)).foregroundStyle(Theme.inkSecond)
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 推移

    @ViewBuilder
    private func trendSection(_ s: PlayerStats) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "総合ポイントの推移", systemImage: "chart.xyaxis.line")
            NoteCard {
                if s.history.count < 2 {
                    Text("2ゲーム以上記録すると推移グラフが表示されます。")
                        .font(AppFont.body(13)).foregroundStyle(Theme.inkSecond)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    Chart {
                        RuleMark(y: .value("基準", 0))
                            .foregroundStyle(Theme.rule)
                        ForEach(s.history) { g in
                            LineMark(x: .value("日付", g.date), y: .value("累計", g.cumulative))
                                .foregroundStyle(Theme.accent)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("日付", g.date), y: .value("累計", g.cumulative))
                                .foregroundStyle(Theme.accent)
                                .symbolSize(18)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine().foregroundStyle(Theme.rule)
                            AxisValueLabel(format: .dateTime.year(.twoDigits).month(.defaultDigits))
                                .font(AppFont.number(10))
                                .foregroundStyle(Theme.inkSecond)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Theme.rule)
                            AxisValueLabel().font(AppFont.number(10)).foregroundStyle(Theme.inkSecond)
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    // MARK: 記録

    private func recordSection(_ s: PlayerStats) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "記録", systemImage: "rosette")
            VStack(spacing: 0) {
                recordRow("最高ゲーム", s.bestGame?.grandTotal, s.bestGame?.date)
                HairlineRule().padding(.leading, Space.lg)
                recordRow("最低ゲーム", s.worstGame?.grandTotal, s.worstGame?.date)
                HairlineRule().padding(.leading, Space.lg)
                recordRow("最高回戦（対局pt）", s.bestRoundPoint, nil)
                HairlineRule().padding(.leading, Space.lg)
                recordRow("最低回戦（対局pt）", s.worstRoundPoint, nil)
            }
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Theme.rule, lineWidth: Theme.hairline))
        }
    }

    private func recordRow(_ title: String, _ value: Int?, _ date: Date?) -> some View {
        HStack(spacing: Space.md) {
            Text(title).font(AppFont.body(14)).foregroundStyle(Theme.ink)
            Spacer()
            if let date {
                Text(date, format: .dateTime.year().month().day())
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
            }
            if let value {
                PointText(value: value, size: 16)
            } else {
                Text("—").font(AppFont.number(16)).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }

    // MARK: 直近のゲーム

    private func recentSection(_ s: PlayerStats) -> some View {
        let recent = Array(s.history.reversed().prefix(10))
        return VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel(text: "直近のゲーム", systemImage: "clock")
            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { idx, g in
                    if idx > 0 { HairlineRule().padding(.leading, Space.lg) }
                    if let session = sessions.first(where: { $0.id == g.id }) {
                        NavigationLink(value: session) { recentRow(g, showsChevron: true) }
                            .buttonStyle(.plain)
                    } else {
                        recentRow(g, showsChevron: false)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Theme.rule, lineWidth: Theme.hairline))
        }
    }

    private func recentRow(_ g: PlayerGameRecord, showsChevron: Bool) -> some View {
        HStack(spacing: Space.md) {
            RankBadge(rank: g.gameRank, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(g.date, format: .dateTime.year().month().day())
                        .font(AppFont.body(14, weight: .medium)).foregroundStyle(Theme.ink)
                    Text("\(g.gameType.displayName)・\(g.roundCount)回戦")
                        .font(AppFont.body(12)).foregroundStyle(Theme.inkFaint)
                }
                Text("vs " + g.opponents.joined(separator: "・"))
                    .font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            PointText(value: g.grandTotal, size: 16)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .contentShape(Rectangle())
    }
}

// MARK: - 小さな共通部品

struct StatCell: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(AppFont.body(11)).foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(AppFont.number(15, weight: .semibold)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatDivider: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(width: Theme.hairline, height: 26)
    }
}
