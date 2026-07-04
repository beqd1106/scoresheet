import SwiftUI
import Charts

/// 成績の可視化：累計ポイント推移（折れ線）＋ 順位分布。
struct StatsView: View {
    let session: TableSession

    private var series: [CumulativePoint] { ScoreCalculator.cumulativeSeries(for: session) }
    private var distribution: [UUID: [Int: Int]] { ScoreCalculator.rankDistribution(for: session) }
    private var maxRound: Int { session.rounds.map(\.roundNumber).max() ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {

                if session.rounds.isEmpty {
                    NoteCard {
                        EmptyNote(title: "まだデータがありません",
                                  message: "回戦を記録すると、推移グラフが表示されます。",
                                  systemImage: "chart.xyaxis.line")
                    }
                } else {
                    // 累計推移
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "累計ポイントの推移", systemImage: "chart.xyaxis.line")
                        NoteCard {
                            chart
                            HairlineRule().padding(.vertical, Space.sm)
                            legend
                        }
                    }

                    // 順位分布
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel(text: "順位の内訳", systemImage: "list.number")
                        NoteCard(padding: Space.md) {
                            VStack(spacing: Space.sm) {
                                ForEach(session.participants) { p in
                                    distributionRow(p)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Space.lg)
        }
        .background(NotePageBackground())
        .navigationTitle("成績グラフ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 折れ線グラフ

    private var chart: some View {
        Chart(series) { point in
            LineMark(
                x: .value("回戦", point.roundNumber),
                y: .value("累計", point.cumulative)
            )
            .foregroundStyle(by: .value("プレイヤー", point.name))
            .symbol(by: .value("プレイヤー", point.name))
            .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale(range: participantColors)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: Array(0...max(maxRound, 1))) { value in
                AxisGridLine().foregroundStyle(Theme.rule)
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(n == 0 ? "開始" : "\(n)")
                            .font(AppFont.number(11))
                            .foregroundStyle(Theme.inkSecond)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.rule)
                AxisValueLabel().font(AppFont.number(11)).foregroundStyle(Theme.inkSecond)
            }
        }
        .frame(height: 240)
    }

    /// name 順に対応する色（chartForegroundStyleScale の range と一致させる）。
    private var participantColors: [Color] {
        session.participants.map { Color(hex: $0.colorHex) }
    }

    private var legend: some View {
        HStack(spacing: Space.lg) {
            ForEach(session.participants) { p in
                HStack(spacing: Space.xs) {
                    PlayerDot(colorHex: p.colorHex, size: 9)
                    Text(p.name).font(AppFont.body(12)).foregroundStyle(Theme.inkSecond)
                }
            }
            Spacer()
        }
    }

    // MARK: 順位分布の行

    private func distributionRow(_ p: Participant) -> some View {
        let counts = distribution[p.id] ?? [:]
        return HStack(spacing: Space.md) {
            PlayerDot(colorHex: p.colorHex)
            Text(p.name).font(AppFont.body(15, weight: .medium)).foregroundStyle(Theme.ink)
                .frame(width: 72, alignment: .leading)
            HStack(spacing: Space.sm) {
                ForEach(1...session.gameType.playerCount, id: \.self) { rank in
                    HStack(spacing: 3) {
                        RankBadge(rank: rank, size: 18)
                        Text("\(counts[rank] ?? 0)")
                            .font(AppFont.number(14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            Spacer()
        }
    }
}
