import Foundation
import SwiftData

// MARK: - 読み込んだ内容（取り込み前の確認用）

/// CSV から読み取った 1回戦。並びは CSV の列順（= プレイヤー順）。
struct ImportedRound: Equatable {
    var rawScores: [Int?]   // 終局時の持ち点（列がなければ nil）
    var points: [Int]       // その回戦のポイント
}

/// CSV から読み取った 1ゲーム。
struct ImportedGame: Equatable {
    var roomName: String
    var date: Date
    var playerNames: [String]
    var rounds: [ImportedRound]
    var chips: [Int]
    var pointCoefficientPer1000: Double
    var chipPointCoefficient: Double

    var gameType: GameType { playerNames.count == 3 ? .sanma : .yonma }
}

struct CSVImportPreview: Equatable {
    var games: [ImportedGame]
    var playerNames: [String]
    /// 小数のポイントを四捨五入した件数（通常は 0）。
    var roundedPointCount: Int
    /// 全員 0 点の空行として読み飛ばした回戦数。
    var skippedEmptyRounds: Int

    var roundCount: Int { games.reduce(0) { $0 + $1.rounds.count } }
    var dateRange: ClosedRange<Date>? {
        guard let lo = games.map(\.date).min(), let hi = games.map(\.date).max() else { return nil }
        return lo...hi
    }
}

struct CSVImportSummary: Equatable {
    var addedSessions = 0
    var skippedDuplicates = 0
    var addedPlayers = 0
}

enum CSVImportError: LocalizedError, Equatable {
    case unreadableText
    case unsupportedFormat
    case unsupportedPlayerCount(Int)
    case noGames

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "ファイルの文字コードを読み取れませんでした。"
        case .unsupportedFormat:
            return "対応していない形式です。「日付」「回戦数」と、プレイヤーごとの「スコア」列があるCSVを選んでください。"
        case .unsupportedPlayerCount(let n):
            return "\(n)人分の列が見つかりました。取り込めるのは三麻（3人）か四麻（4人）の記録です。"
        case .noGames:
            return "取り込める回戦が見つかりませんでした。"
        }
    }
}

// MARK: - 取り込み処理

/// 他の麻雀スコアアプリから書き出した CSV を取り込む。
///
/// 対応形式（1行 = 1回戦）：
///   部屋名, 日付, 回戦数, ［名前 点数, 名前 スコア, 名前 チップ, 名前 収支］× 人数
/// ・「スコア」をその回戦のポイント、「点数」を素点として保存する
/// ・チップは主に 1回戦目の行に入っている（他の行は "-"）ので、ゲーム内で合計する
/// ・「収支」は表示には使わず、係数（1000点あたり・チップ1枚あたり）の推定にだけ使う
///   → 元アプリと同じ総合ポイントがこのアプリでも再現される
/// ・回戦数が 1 に戻る、または部屋名・日付が変わったら次のゲームとみなす
enum CSVImportService {

    // MARK: 文字コード・CSV分解

    static func decodeText(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        return String(data: data, encoding: .shiftJIS)
    }

    /// ダブルクォート（"a,b" や "" のエスケープ）に対応した CSV 分解。
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text).makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }

        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n", "\r":
                row.append(field); field = ""
                rows.append(row); row = []
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    // MARK: 解析

    private struct PlayerColumns {
        var name: String
        var score: Int          // 「スコア」列（必須）
        var raw: Int?           // 「点数」列
        var chip: Int?          // 「チップ」列
        var balance: Int?       // 「収支」列（係数の推定にだけ使う）
    }

    static func parse(_ data: Data, calendar: Calendar = .current) throws -> CSVImportPreview {
        guard let text = decodeText(data) else { throw CSVImportError.unreadableText }
        return try parse(text: text, calendar: calendar)
    }

    static func parse(text: String, calendar: Calendar = .current) throws -> CSVImportPreview {
        let rows = parseCSV(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces) }) else {
            throw CSVImportError.unsupportedFormat
        }
        guard let dateCol = header.firstIndex(of: "日付"),
              let roundCol = header.firstIndex(where: { $0 == "回戦数" || $0 == "回戦" }) else {
            throw CSVImportError.unsupportedFormat
        }
        let roomCol = header.firstIndex(of: "部屋名")
        let players = playerColumns(header)
        guard !players.isEmpty else { throw CSVImportError.unsupportedFormat }
        guard players.count == 3 || players.count == 4 else {
            throw CSVImportError.unsupportedPlayerCount(players.count)
        }

        var builders: [GameBuilder] = []
        var lastKey: String? = nil
        var lastRound = 0
        var rounded = 0
        var skippedEmpty = 0

        for row in rows.dropFirst() {
            func cell(_ i: Int?) -> String {
                guard let i, i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespaces)
            }
            guard let date = parseDate(cell(dateCol), calendar: calendar) else { continue }
            let room = cell(roomCol)
            let key = room + "|" + cell(dateCol)
            let roundNo = Int(cell(roundCol)) ?? (lastRound + 1)

            if key != lastKey || roundNo <= lastRound || builders.isEmpty {
                builders.append(GameBuilder(roomName: room, date: date, playerCount: players.count))
            }
            lastKey = key
            lastRound = roundNo

            let scores = players.map { Double(cell($0.score)) }
            guard scores.allSatisfy({ $0 != nil }) else { continue }
            let points = scores.map { s -> Int in
                let v = s!
                if v != v.rounded() { rounded += 1 }
                return Int(v.rounded(.toNearestOrAwayFromZero))
            }
            let raws = players.map { p in p.raw.flatMap { Int(cell($0)) } }
            let chips = players.map { p in p.chip.flatMap { Int(cell($0)) } }
            let balances = players.map { p in p.balance.flatMap { Double(cell($0)) } }

            let b = builders.count - 1
            for i in players.indices {
                builders[b].chips[i] += chips[i] ?? 0
                if let m = balances[i] {
                    builders[b].samples.append((score: scores[i]!, chip: Double(chips[i] ?? 0), balance: m))
                }
            }

            let isEmpty = points.allSatisfy { $0 == 0 } && raws.allSatisfy { ($0 ?? 0) == 0 }
            if isEmpty { skippedEmpty += 1; continue }
            builders[b].rounds.append(ImportedRound(rawScores: raws, points: points))
        }

        // 係数：推定できないゲームは、同じファイル内で最も多い値を使う
        let estimates = builders.map { estimateCoefficients($0.samples) }
        let commonPer1000 = mostCommon(estimates.compactMap { $0.per1000 }) ?? AppDefaults.pointCoefficientPer1000
        let commonChip = mostCommon(estimates.compactMap { $0.chip }) ?? AppDefaults.chipPointCoefficient

        let names = players.map(\.name)
        let games: [ImportedGame] = zip(builders, estimates).compactMap { b, est in
            guard !b.rounds.isEmpty else { return nil }
            return ImportedGame(roomName: b.roomName,
                                date: b.date,
                                playerNames: names,
                                rounds: b.rounds,
                                chips: b.chips,
                                pointCoefficientPer1000: est.per1000 ?? commonPer1000,
                                chipPointCoefficient: est.chip ?? commonChip)
        }
        guard !games.isEmpty else { throw CSVImportError.noGames }

        return CSVImportPreview(games: games, playerNames: names,
                                roundedPointCount: rounded, skippedEmptyRounds: skippedEmpty)
    }

    private struct GameBuilder {
        var roomName: String
        var date: Date
        var rounds: [ImportedRound] = []
        var chips: [Int]
        var samples: [(score: Double, chip: Double, balance: Double)] = []

        init(roomName: String, date: Date, playerCount: Int) {
            self.roomName = roomName
            self.date = date
            self.chips = Array(repeating: 0, count: playerCount)
        }
    }

    /// 見出しから「名前 スコア」などの列をプレイヤーごとにまとめる（列の登場順＝席順）。
    private static func playerColumns(_ header: [String]) -> [PlayerColumns] {
        let suffixes = ["スコア", "点数", "チップ", "収支"]
        var order: [String] = []
        var found: [String: [String: Int]] = [:]
        for (i, h) in header.enumerated() {
            for suffix in suffixes where h.hasSuffix(suffix) {
                let name = String(h.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                if found[name] == nil { order.append(name); found[name] = [:] }
                found[name]?[suffix] = i
            }
        }
        return order.compactMap { name in
            guard let cols = found[name], let score = cols["スコア"] else { return nil }
            return PlayerColumns(name: name, score: score, raw: cols["点数"],
                                 chip: cols["チップ"], balance: cols["収支"])
        }
    }

    static func parseDate(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == " " })
        guard parts.count >= 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        // 時刻は分からないので正午に置く（日付の境目でずれないように）。
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    /// 収支 ≒ ポイント × a ＋ チップ × b となる a（1000点あたり）と b（チップ1枚あたり）を最小二乗で求める。
    /// 推定できない側は nil（例：チップが全員 0 のゲームは b が決まらない）。
    static func estimateCoefficients(_ samples: [(score: Double, chip: Double, balance: Double)])
        -> (per1000: Double?, chip: Double?) {
        let ss = samples.reduce(0) { $0 + $1.score * $1.score }
        let cc = samples.reduce(0) { $0 + $1.chip * $1.chip }
        let sc = samples.reduce(0) { $0 + $1.score * $1.chip }
        let sm = samples.reduce(0) { $0 + $1.score * $1.balance }
        let cm = samples.reduce(0) { $0 + $1.chip * $1.balance }

        func clean(_ v: Double) -> Double? {
            guard v.isFinite, v >= 0 else { return nil }
            return v.rounded()
        }

        let det = ss * cc - sc * sc
        if ss > 0, cc > 0, abs(det) > 1e-9 {
            return (clean((sm * cc - cm * sc) / det), clean((ss * cm - sc * sm) / det))
        }
        if ss > 0 { return (clean(sm / ss), nil) }
        if cc > 0 { return (nil, clean(cm / cc)) }
        return (nil, nil)
    }

    private static func mostCommon(_ values: [Double]) -> Double? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }

    // MARK: 保存

    /// 読み込んだゲームを保存する。
    /// ・名前が一致する名簿のプレイヤーに紐付け、いなければ名簿に追加する
    /// ・同じ日・同じメンバー・同じ点数のゲームがすでにあれば重複として飛ばす
    @discardableResult
    static func apply(_ preview: CSVImportPreview,
                      tag: String?,
                      into context: ModelContext) throws -> CSVImportSummary {
        var summary = CSVImportSummary()
        let calendar = Calendar.current

        var roster = try context.fetch(FetchDescriptor<Player>(sortBy: [SortDescriptor(\.createdAt)]))
        var participants: [Participant] = []
        for name in preview.playerNames {
            if let p = roster.first(where: { $0.name.trimmingCharacters(in: .whitespaces) == name }) {
                participants.append(p.participant)
            } else {
                let color = Theme.playerPalette[roster.count % Theme.playerPalette.count]
                let p = Player(name: name, colorHex: color)
                context.insert(p)
                roster.append(p)
                participants.append(p.participant)
                summary.addedPlayers += 1
            }
        }

        let existing = try context.fetch(FetchDescriptor<TableSession>())
        var fingerprints = Set(existing.map { fingerprint(of: $0, calendar: calendar) })
        let cleanTag = tag?.trimmingCharacters(in: .whitespaces) ?? ""

        // 同じ日のゲームが複数あるとき、CSV の並び（新しい順）を保てるよう時刻を少しずつずらす。
        var perDay: [Date: Int] = [:]

        for game in preview.games {
            let rounds: [[PlayerRoundPoint]] = game.rounds.map { round in
                let ranks = rankOrder(round)
                return participants.indices.map { i in
                    PlayerRoundPoint(participantID: participants[i].id,
                                     rank: ranks[i],
                                     point: round.points[i],
                                     isAutoCalculated: false,
                                     rawScore: round.rawScores[i])
                }
            }
            let chips = participants.indices.map { ChipEntry(participantID: participants[$0].id, chipCount: game.chips[$0]) }

            let fp = fingerprint(date: game.date, participantIDs: participants.map(\.id),
                                 rounds: rounds, chips: chips, calendar: calendar)
            guard !fingerprints.contains(fp) else { summary.skippedDuplicates += 1; continue }
            fingerprints.insert(fp)

            let day = calendar.startOfDay(for: game.date)
            let offset = perDay[day, default: 0]
            perDay[day] = offset + 1

            let session = TableSession(gameType: game.gameType,
                                       participants: participants,
                                       pointCoefficientPer1000: game.pointCoefficientPer1000,
                                       chipPointCoefficient: game.chipPointCoefficient,
                                       tags: cleanTag.isEmpty ? [] : [cleanTag],
                                       memo: memo(for: game),
                                       inputMode: .point)
            session.date = game.date.addingTimeInterval(-Double(offset) * 60)
            session.chips = chips
            context.insert(session)
            for (idx, pts) in rounds.enumerated() {
                let rr = RoundResult(roundNumber: idx + 1, points: pts)
                rr.session = session
                session.rounds.append(rr)
                context.insert(rr)
            }
            summary.addedSessions += 1
        }

        try context.save()
        return summary
    }

    /// 順位：素点がそろっていれば素点の高い順、なければポイントの高い順。同点は席順。
    static func rankOrder(_ round: ImportedRound) -> [Int] {
        let n = round.points.count
        let raws = round.rawScores.compactMap { $0 }
        let useRaw = raws.count == n
        let order = (0..<n).sorted { a, b in
            let va = useRaw ? raws[a] : round.points[a]
            let vb = useRaw ? raws[b] : round.points[b]
            return va == vb ? a < b : va > vb
        }
        var rank = Array(repeating: 0, count: n)
        for (pos, idx) in order.enumerated() { rank[idx] = pos + 1 }
        return rank
    }

    private static func memo(for game: ImportedGame) -> String {
        let room = game.roomName
        // 部屋名が日付だけのものはメモに残しても意味がないので省く。
        if room.isEmpty || parseDate(room) != nil { return "CSVから取り込み" }
        return "CSVから取り込み（\(room)）"
    }

    // MARK: 重複判定

    private static func fingerprint(of session: TableSession, calendar: Calendar) -> String {
        fingerprint(date: session.date,
                    participantIDs: session.participants.map(\.id),
                    rounds: session.sortedRounds.map(\.points),
                    chips: session.chips,
                    calendar: calendar)
    }

    /// 日付（日単位）・メンバー・各回戦のポイント・チップが同じなら同一ゲームとみなす。
    private static func fingerprint(date: Date, participantIDs: [UUID],
                                    rounds: [[PlayerRoundPoint]], chips: [ChipEntry],
                                    calendar: Calendar) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        let ids = participantIDs.map(\.uuidString).sorted()
        let roundText = rounds.map { pts in
            ids.map { id in String(pts.first(where: { $0.participantID.uuidString == id })?.point ?? 0) }
                .joined(separator: ":")
        }.joined(separator: "/")
        let chipText = ids.map { id in String(chips.first(where: { $0.participantID.uuidString == id })?.chipCount ?? 0) }
            .joined(separator: ":")
        return "\(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0)|\(ids.joined(separator: ","))|\(roundText)|\(chipText)"
    }
}
