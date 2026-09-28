import SwiftUI
import SwiftData
import Charts

// MARK: - 絞り込みバー（一覧・詳細で共通）

/// 種別（すべて/四麻/三麻）と年で絞り込む。
struct StatsFilterBar: View {
    @Binding var filter: StatsFilter
    let years: [Int]

    private var typeBinding: Binding<String> {
        Binding(get: { filter.gameType?.rawValue ?? "all" },
                set: { filter.gameType = GameType(rawValue: $0) })
    }

    var body: some View {
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
                HStack(spacing: 4) {
                    Text(filter.year.map { "\(String($0))年" } ?? "全期間")
                        .font(AppFont.body(13, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Space.md)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: Radius.small).fill(Theme.accent.opacity(0.10)))
            }
        }
    }
}

// MARK: - プレイヤー別成績（一覧）

struct PlayerStatsListView: View {
    @Query(sort: \TableSession.date, order: .reverse) private var sessions: [TableSession]
    @Query(sort: \Player.createdAt) private var players: [Player]
    @State private var filter = StatsFilter()

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
                StatsFilterBar(filter: $filter, years: PlayerStatsCalculator.availableYears(allGames))

                if stats.isEmpty {
                    NoteCard {
                        EmptyNote(title: allGames.isEmpty ? "まだ記録がありません" : "該当するゲームがありません",
                                  message: allGames.isEmpty
                                    ? "ゲームを記録すると、プレイヤーごとの通算成績がここに集まります。"
                                    : "種別や期間の絞り込みを変えてみてください。",
                                  systemImage: "person.crop.rectangle.stack")
                    }
                } else {
                    Text("\(gameCount)ゲームを集計・総合ポイント順")
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
        .navigationTitle("プレイヤー別成績")
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
                StatsFilterBar(filter: $filter, years: PlayerStatsCalculator.availableYears(allGames))

                if let s = stats {
                    header(s)
                    kpiGrid(s)
                    rankSection(s)
                    trendSection(s)
                    recordSection(s)
                    recentSection(s)
                } else {
                    NoteCard {
                        EmptyNote(title: "該当するゲームがありません",
                                  message: "種別や期間の絞り込みを変えてみてください。",
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
