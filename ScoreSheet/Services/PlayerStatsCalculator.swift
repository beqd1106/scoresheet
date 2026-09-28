import Foundation

/// 通算成績の集計に使う 1ゲーム分の値。
/// @Model から切り離しておくことで、集計ロジックを画面やデータベース抜きでテストできる。
struct StatsGame: Identifiable, Equatable {
    var id: UUID
    var date: Date
    var gameType: GameType
    var participants: [Participant]
    /// 集計に数える回戦だけ（空行・入力途中は除外済み）。回戦番号順。
    var rounds: [[PlayerRoundPoint]]
    /// そのゲームの総合ポイント（対局×1000点係数＋チップ×チップ係数）。
    var grandTotals: [UUID: Int]
    /// そのゲームでの総合順位。
    var gameRanks: [UUID: Int]
    /// 対局ポイントの生合計（係数をかける前）。
    var roundPointTotals: [UUID: Int]
    var chipCounts: [UUID: Int]
}

extension StatsGame {
    init(session: TableSession) {
        let results = ScoreCalculator.finalResults(for: session)
        id = session.id
        date = session.date
        gameType = session.gameType
        participants = session.participants
        rounds = ScoreCalculator.countedRounds(session)
            .sorted { $0.roundNumber < $1.roundNumber }
            .map(\.points)
        grandTotals = Dictionary(results.map { ($0.participantID, $0.grandTotal) }, uniquingKeysWith: { a, _ in a })
        gameRanks = Dictionary(results.map { ($0.participantID, $0.rank) }, uniquingKeysWith: { a, _ in a })
        roundPointTotals = Dictionary(results.map { ($0.participantID, $0.roundPointTotal) }, uniquingKeysWith: { a, _ in a })
        chipCounts = Dictionary(session.participants.map { ($0.id, session.chipCount(for: $0.id)) },
                                uniquingKeysWith: { a, _ in a })
    }
}

/// 集計の絞り込み条件。
struct StatsFilter: Equatable {
    var gameType: GameType? = nil   // nil = 三麻・四麻すべて
    var year: Int? = nil            // nil = 全期間

    func includes(_ game: StatsGame, calendar: Calendar = .current) -> Bool {
        if let gameType, game.gameType != gameType { return false }
        if let year, calendar.component(.year, from: game.date) != year { return false }
        return true
    }
}

/// あるプレイヤーの 1ゲーム分の記録（推移グラフ・直近ゲーム一覧用）。
struct PlayerGameRecord: Identifiable, Equatable {
    var id: UUID            // ゲーム（TableSession）の ID
    var date: Date
    var gameType: GameType
    var grandTotal: Int
    var gameRank: Int
    var roundCount: Int
    var opponents: [String]
    var cumulative: Int     // このゲームまでの総合ポイント累計
}

/// プレイヤー 1人分の通算成績。
struct PlayerStats: Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String

    var games = 0
    var gameTops = 0            // ゲーム単位の総合1位の回数
    var rounds = 0
    var rankCounts: [Int: Int] = [:]
    var lastCount = 0           // 各回戦の最下位（三麻は3着・四麻は4着）
    var grandTotal = 0
    var roundPointTotal = 0
    var chipCount = 0

    // 素点が残っている回戦だけで数える項目
    var rawRounds = 0
    var rawScoreSum = 0
    var tobiCount = 0

    var bestRoundPoint: Int? = nil
    var worstRoundPoint: Int? = nil
    var history: [PlayerGameRecord] = []   // 日付の古い順

    // MARK: 率

    private func rate(_ count: Int) -> Double { rounds == 0 ? 0 : Double(count) / Double(rounds) }

    var averageRank: Double {
        guard rounds > 0 else { return 0 }
        let sum = rankCounts.reduce(0) { $0 + $1.key * $1.value }
        return Double(sum) / Double(rounds)
    }
    var topRate: Double { rate(rankCounts[1] ?? 0) }
    var rentaiRate: Double { rate((rankCounts[1] ?? 0) + (rankCounts[2] ?? 0)) }
    var lastRate: Double { rate(lastCount) }

    /// 素点の記録がない（ポイント入力だけ）の場合は nil。
    var tobiRate: Double? { rawRounds == 0 ? nil : Double(tobiCount) / Double(rawRounds) }
    var averageRawScore: Int? { rawRounds == 0 ? nil : Int((Double(rawScoreSum) / Double(rawRounds)).rounded()) }

    var bestGame: PlayerGameRecord? { history.max { $0.grandTotal < $1.grandTotal } }
    var worstGame: PlayerGameRecord? { history.min { $0.grandTotal < $1.grandTotal } }
}

/// プレイヤー別の通算成績を集計する（純粋関数）。
enum PlayerStatsCalculator {

    /// - Parameters:
    ///   - games: 全ゲーム
    ///   - filter: 種別・年の絞り込み
    ///   - roster: 名簿の最新の名前と色（改名後の名前で表示するため）。名簿にいない人は記録時の名前を使う
    /// - Returns: 総合ポイントの高い順
    static func aggregate(games: [StatsGame],
                          filter: StatsFilter = StatsFilter(),
                          roster: [UUID: (name: String, colorHex: String)] = [:],
                          calendar: Calendar = .current) -> [PlayerStats] {
        let target = games
            .filter { filter.includes($0, calendar: calendar) && !$0.rounds.isEmpty }
            .sorted { $0.date < $1.date }

        var stats: [UUID: PlayerStats] = [:]

        for game in target {
            let n = game.participants.count
            for p in game.participants {
                var s = stats[p.id] ?? PlayerStats(id: p.id,
                                                   name: roster[p.id]?.name ?? p.name,
                                                   colorHex: roster[p.id]?.colorHex ?? p.colorHex)
                if roster[p.id] == nil {
                    // 名簿にいない人は、いちばん新しい記録の名前・色で表示する。
                    s.name = p.name
                    s.colorHex = p.colorHex
                }

                let grand = game.grandTotals[p.id] ?? 0
                let gameRank = game.gameRanks[p.id] ?? 0
                s.games += 1
                if gameRank == 1 { s.gameTops += 1 }
                s.grandTotal += grand
                s.roundPointTotal += game.roundPointTotals[p.id] ?? 0
                s.chipCount += game.chipCounts[p.id] ?? 0

                for round in game.rounds {
                    guard let entry = round.first(where: { $0.participantID == p.id }) else { continue }
                    s.rounds += 1
                    s.rankCounts[entry.rank, default: 0] += 1
                    if entry.rank == n { s.lastCount += 1 }
                    s.bestRoundPoint = max(s.bestRoundPoint ?? entry.point, entry.point)
                    s.worstRoundPoint = min(s.worstRoundPoint ?? entry.point, entry.point)
                    if let raw = entry.rawScore {
                        s.rawRounds += 1
                        s.rawScoreSum += raw
                        if raw < 0 { s.tobiCount += 1 }
                    }
                }

                let cumulative = (s.history.last?.cumulative ?? 0) + grand
                s.history.append(PlayerGameRecord(
                    id: game.id,
                    date: game.date,
                    gameType: game.gameType,
                    grandTotal: grand,
                    gameRank: gameRank,
                    roundCount: game.rounds.count,
                    opponents: game.participants.filter { $0.id != p.id }.map { roster[$0.id]?.name ?? $0.name },
                    cumulative: cumulative
                ))
                stats[p.id] = s
            }
        }

        return stats.values.sorted { a, b in
            if a.grandTotal != b.grandTotal { return a.grandTotal > b.grandTotal }
            if a.averageRank != b.averageRank { return a.averageRank < b.averageRank }
            return a.name < b.name
        }
    }

    /// 絞り込みの選択肢に出す年（新しい順）。
    static func availableYears(_ games: [StatsGame], calendar: Calendar = .current) -> [Int] {
        Array(Set(games.map { calendar.component(.year, from: $0.date) })).sorted(by: >)
    }
}

extension Double {
    /// 0.253 → "25.3%"
    var percentString: String { String(format: "%.1f%%", self * 100) }
}
