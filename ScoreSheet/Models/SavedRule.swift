import Foundation

/// 「いつものルール」として保存した設定一式。
/// 新規ゲームでワンタップ呼び出しするため、種別・入力方式・係数も一緒に持つ。
struct SavedRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var gameTypeRaw: String = GameType.yonma.rawValue
    var inputModeRaw: String = InputMode.point.rawValue
    var rule: GameRule = GameRule()
    var pointCoefficientPer1000: Double = AppDefaults.pointCoefficientPer1000
    var chipPointCoefficient: Double = AppDefaults.chipPointCoefficient
    /// 呼び出したゲームに自動で付けるタグ（1.5.0 から）。タグ別成績とつなげるため。
    var tags: [String] = []
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, name, gameTypeRaw, inputModeRaw, rule, pointCoefficientPer1000, chipPointCoefficient, tags, createdAt
    }

    var gameType: GameType { GameType(rawValue: gameTypeRaw) ?? .yonma }
    var inputMode: InputMode { InputMode(rawValue: inputModeRaw) ?? .point }

    init(id: UUID = UUID(), name: String, gameType: GameType, inputMode: InputMode,
         rule: GameRule, pointCoefficientPer1000: Double, chipPointCoefficient: Double,
         tags: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.gameTypeRaw = gameType.rawValue
        self.inputModeRaw = inputMode.rawValue
        self.rule = rule
        self.pointCoefficientPer1000 = pointCoefficientPer1000
        self.chipPointCoefficient = chipPointCoefficient
        self.tags = tags
        // 保存（iso8601）で秒未満が落ちるので、最初から秒単位にそろえて前後で同じ値にする。
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
    }

    /// 画面に出す1行の要約（例：四麻・素点・25000持ち30000返し・ウマ+20/+10/-10/-20）。
    var summary: String {
        var parts = [gameType.displayName, inputMode == .rawScore ? "素点" : "ポイント"]
        if inputMode == .rawScore {
            parts.append("\(rule.startingPoints)持ち\(rule.returnPoints)返し")
            let uma = rule.normalizedUma(playerCount: gameType.playerCount)
            parts.append("ウマ" + uma.map(\.signedPointString).joined(separator: "/"))
            var penalties: [String] = []
            if rule.tobiEnabled { penalties.append("トビ") }
            if rule.yakitoriEnabled { penalties.append("ヤキトリ") }
            if rule.kubiEnabled { penalties.append("クビ") }
            if !penalties.isEmpty { parts.append(penalties.joined(separator: "/")) }
        }
        parts.append("1000点\(Int(pointCoefficientPer1000))pt・チップ\(Int(chipPointCoefficient))pt")
        return parts.joined(separator: "・")
    }

    /// 中身（名前・ID・作成日・タグ以外）が同じか。新規ゲーム画面で「選択中」表示に使う。
    func matches(gameType: GameType, inputMode: InputMode, rule: GameRule,
                 pointCoefficientPer1000: Double, chipPointCoefficient: Double) -> Bool {
        guard self.gameType == gameType,
              self.inputMode == inputMode,
              self.pointCoefficientPer1000 == pointCoefficientPer1000,
              self.chipPointCoefficient == chipPointCoefficient else { return false }
        // ポイント入力ではルールを使わないので比べない。
        return inputMode == .point || self.rule == rule
    }
}

// 項目が増えても古い保存データを読めるよう、無いキーは既定値で補う（GameRule と同じ方針）。
extension SavedRule {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "マイルール"
        gameTypeRaw = try c.decodeIfPresent(String.self, forKey: .gameTypeRaw) ?? GameType.yonma.rawValue
        inputModeRaw = try c.decodeIfPresent(String.self, forKey: .inputModeRaw) ?? InputMode.point.rawValue
        rule = try c.decodeIfPresent(GameRule.self, forKey: .rule) ?? GameRule()
        pointCoefficientPer1000 = try c.decodeIfPresent(Double.self, forKey: .pointCoefficientPer1000)
            ?? AppDefaults.pointCoefficientPer1000
        chipPointCoefficient = try c.decodeIfPresent(Double.self, forKey: .chipPointCoefficient)
            ?? AppDefaults.chipPointCoefficient
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// 保存ルールの読み書き。UserDefaults に JSON 文字列で置く（@AppStorage で画面が自動更新されるように）。
enum SavedRuleStore {
    static let maxNameLength = 20

    static func decode(_ json: String) -> [SavedRule] {
        guard let data = json.data(using: .utf8), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 1件壊れていても他は残す。
        guard let items = try? decoder.decode([Lossy<SavedRule>].self, from: data) else { return [] }
        return items.compactMap(\.value)
    }

    static func encode(_ rules: [SavedRule]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(rules) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func load(_ defaults: UserDefaults = .standard) -> [SavedRule] {
        decode(defaults.string(forKey: AppSettingsKey.savedRules) ?? "")
    }

    static func save(_ rules: [SavedRule], _ defaults: UserDefaults = .standard) {
        defaults.set(encode(rules), forKey: AppSettingsKey.savedRules)
    }

    static func normalizedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    /// 追加する。同じ名前があればその枠を上書きする（ID・作成日は残す）。
    /// - Returns: 更新後の一覧と、上書きしたかどうか
    static func upsert(_ rule: SavedRule, into rules: [SavedRule]) -> (rules: [SavedRule], replaced: Bool) {
        var list = rules
        var item = rule
        item.name = normalizedName(item.name)
        if let idx = list.firstIndex(where: { $0.name == item.name }) {
            item.id = list[idx].id
            item.createdAt = list[idx].createdAt
            list[idx] = item
            return (list, true)
        }
        list.append(item)
        return (list, false)
    }

    /// バックアップから戻すとき用：同じ ID・同じ名前が無いものだけ足す。
    static func merge(_ incoming: [SavedRule], into rules: [SavedRule]) -> (rules: [SavedRule], added: Int) {
        var list = rules
        var added = 0
        for r in incoming where !list.contains(where: { $0.id == r.id || $0.name == r.name }) {
            list.append(r)
            added += 1
        }
        return (list, added)
    }

    /// まだ使っていない「マイルール1」「マイルール2」…の名前。
    /// タグの入力を整える（前後の空白を除き、空・重複を落とす）。
    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func suggestedName(existing: [SavedRule]) -> String {
        let names = Set(existing.map(\.name))
        var i = existing.count + 1
        while names.contains("マイルール\(i)") { i += 1 }
        return "マイルール\(i)"
    }
}

/// 配列の一部が読めなくても全体を捨てないための入れ物。
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
