import Foundation

/// 回戦の入力方式。
enum InputMode: String, Codable, CaseIterable, Identifiable {
    case point      // ポイント直接入力（従来）
    case rawScore   // 素点（終了時の持ち点）を入力し、ポイントを自動計算

    var id: String { rawValue }
    var displayName: String { self == .point ? "ポイント入力" : "素点入力" }
    var summary: String {
        self == .point
        ? "計算済みのポイントをそのまま入力します。"
        : "終局時の持ち点を入力すると、ウマ・オカ・罰符を含めて自動計算します。"
    }
}

/// 1000点未満の端数処理。
enum RoundingMode: String, Codable, CaseIterable, Identifiable {
    case gosyaRokunyu   // 五捨六入（500点以下は切り捨て・600点以上は切り上げ）
    case roundHalfUp    // 四捨五入
    case truncate       // 切り捨て

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gosyaRokunyu: return "五捨六入"
        case .roundHalfUp:  return "四捨五入"
        case .truncate:     return "切り捨て"
        }
    }

    /// 1000点単位に換算済みの値を、このモードで整数化する。
    func apply(_ value: Double) -> Int {
        let sign: Double = value < 0 ? -1 : 1
        let mag = abs(value)
        switch self {
        case .gosyaRokunyu: return Int(sign * (mag + 0.4).rounded(.down))
        case .roundHalfUp:  return Int(sign * (mag + 0.5).rounded(.down))
        case .truncate:     return Int(sign * mag.rounded(.down))
        }
    }
}

/// 罰符の受け取り方。
enum PenaltyPayee: String, Codable, CaseIterable, Identifiable {
    case top       // トップが総取り
    case others    // 該当者以外で山分け
    case buster    // 飛ばした人が受け取る（トビ専用）

    var id: String { rawValue }

    /// セグメント表示用の短いラベル。
    var shortLabel: String {
        switch self {
        case .top:    return "トップ"
        case .others: return "山分け"
        case .buster: return "飛ばした人"
        }
    }

    var displayName: String {
        switch self {
        case .top:    return "トップが受け取る"
        case .others: return "該当者以外で山分け"
        case .buster: return "飛ばした人が受け取る"
        }
    }

    /// トビだけは「飛ばした人が受け取る」を選べる。
    static let tobiCases: [PenaltyPayee] = [.top, .others, .buster]
    static let standardCases: [PenaltyPayee] = [.top, .others]
}

/// 罰符の払い方（受け取る人が複数いるときだけ意味を持つ）。
enum PenaltyUnit: String, Codable, CaseIterable, Identifiable {
    case pot        // 場に払う：罰符の総額を受け取る人で分ける（20pt を2人なら 10pt ずつ）
    case perPerson  // 人に払う：受け取る人ごとに満額（20pt を2人なら 20pt ずつ・合計40pt）

    var id: String { rawValue }
    var displayName: String { self == .pot ? "場に払う" : "人に払う" }

    /// 設定画面での説明文。amount は現在の罰符額。
    func detail(amount: Int, receivers: Int) -> String {
        let count = max(receivers, 1)
        switch self {
        case .pot:
            return "罰符 \(amount)pt を受け取る\(count)人で分けます（1人あたり約\(amount / count)pt）。"
        case .perPerson:
            return "受け取る\(count)人それぞれに \(amount)pt ずつ払います（支払いは合計 \(amount * count)pt）。"
        }
    }
}

/// クビ（罰符）の判定条件。
enum KubiCondition: String, Codable, CaseIterable, Identifiable {
    case belowThreshold   // 基準点に届かなかった人（例：20000点なければ罰符）
    case lastPlace        // 最下位の人

    var id: String { rawValue }
    var displayName: String { self == .belowThreshold ? "基準点未満" : "最下位" }
}

/// 素点入力モードで使う対局ルール。
/// すべて 1000点 = 1ポイント換算（既存のポイント欄と同じ単位）で扱う。
struct GameRule: Codable, Equatable {

    // MARK: 基本
    var startingPoints: Int = 25000     // 配給原点
    var returnPoints: Int = 30000       // 返し点（オカの基準）
    var uma: [Int] = [20, 10, -10, -20] // 順位点（1位から順）
    var rounding: RoundingMode = .gosyaRokunyu

    // MARK: トビ（ハコ）
    var tobiEnabled: Bool = false
    var tobiPenalty: Int = 20           // 該当者が支払うポイント
    var tobiIncludesZero: Bool = false  // 0点ちょうどもトビとみなすか
    var tobiPayee: PenaltyPayee = .top
    var tobiUnit: PenaltyUnit = .pot

    // MARK: ヤキトリ（1回も和了なし）
    var yakitoriEnabled: Bool = false
    var yakitoriPenalty: Int = 20
    var yakitoriPayee: PenaltyPayee = .others
    var yakitoriUnit: PenaltyUnit = .pot

    // MARK: クビ（基準点に届かない人・または最下位の罰符）
    var kubiEnabled: Bool = false
    var kubiCondition: KubiCondition = .belowThreshold
    var kubiThreshold: Int = 20000      // この点数に届かなければ罰符
    var kubiPenalty: Int = 10
    var kubiPayee: PenaltyPayee = .top
    var kubiUnit: PenaltyUnit = .pot

    // MARK: 導出値

    /// 全員の持ち点合計（正しく入力できていれば必ずこの値になる）。
    func expectedTotalScore(playerCount: Int) -> Int { startingPoints * playerCount }

    /// オカ（トップが受け取る供託分）。返し点 > 配給原点 のときに発生。
    func okaPoint(playerCount: Int) -> Int {
        (returnPoints - startingPoints) * playerCount / 1000
    }

    /// 人数に合わせてウマ配列の長さを整える。
    func normalizedUma(playerCount: Int) -> [Int] {
        var u = uma
        if u.count > playerCount { u = Array(u.prefix(playerCount)) }
        while u.count < playerCount { u.append(0) }
        return u
    }

    /// 人数変更時にウマの既定値も含めて整合させる。
    mutating func normalize(for gameType: GameType) {
        if uma.count != gameType.playerCount {
            uma = GameRule.defaultUma(for: gameType)
        }
    }

    static func defaultUma(for gameType: GameType) -> [Int] {
        gameType == .sanma ? [20, 0, -20] : [20, 10, -10, -20]
    }

    // MARK: 既定・プリセット

    static func standard(for gameType: GameType) -> GameRule {
        var r = GameRule()
        if gameType == .sanma {
            r.startingPoints = 35000
            r.returnPoints = 40000
            r.uma = [20, 0, -20]
        }
        return r
    }
}

/// よく使うルールの組み合わせ。新規ゲーム作成時にワンタップで適用する。
struct RulePreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let detail: String
    let make: (GameType) -> GameRule

    static func == (l: RulePreset, r: RulePreset) -> Bool { l.name == r.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    static let all: [RulePreset] = [
        RulePreset(name: "標準", detail: "25000持ち30000返し・ウマ10-20") { GameRule.standard(for: $0) },
        RulePreset(name: "ウマ5-10", detail: "順位点を小さめに") { type in
            var r = GameRule.standard(for: type)
            r.uma = type == .sanma ? [10, 0, -10] : [10, 5, -5, -10]
            return r
        },
        RulePreset(name: "ウマ10-30", detail: "順位点を大きめに") { type in
            var r = GameRule.standard(for: type)
            r.uma = type == .sanma ? [30, 0, -30] : [30, 10, -10, -30]
            return r
        },
        RulePreset(name: "オカなし", detail: "25000持ち25000返し・ウマのみ") { type in
            var r = GameRule.standard(for: type)
            r.returnPoints = r.startingPoints
            return r
        },
        RulePreset(name: "罰符あり", detail: "標準＋トビ/ヤキトリ/クビ") { type in
            var r = GameRule.standard(for: type)
            r.tobiEnabled = true
            r.yakitoriEnabled = true
            r.kubiEnabled = true
            return r
        }
    ]
}

// MARK: - 前後のバージョンと互換に読むためのデコード
// 保存済み JSON に無いキーは既定値で補う。
// （項目が増えても、古いデータのルール設定が丸ごと初期化されないようにするため）
extension GameRule {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameRule()
        self.init()
        startingPoints = try c.decodeIfPresent(Int.self, forKey: .startingPoints) ?? d.startingPoints
        returnPoints = try c.decodeIfPresent(Int.self, forKey: .returnPoints) ?? d.returnPoints
        uma = try c.decodeIfPresent([Int].self, forKey: .uma) ?? d.uma
        rounding = try c.decodeIfPresent(RoundingMode.self, forKey: .rounding) ?? d.rounding

        tobiEnabled = try c.decodeIfPresent(Bool.self, forKey: .tobiEnabled) ?? d.tobiEnabled
        tobiPenalty = try c.decodeIfPresent(Int.self, forKey: .tobiPenalty) ?? d.tobiPenalty
        tobiIncludesZero = try c.decodeIfPresent(Bool.self, forKey: .tobiIncludesZero) ?? d.tobiIncludesZero
        tobiPayee = try c.decodeIfPresent(PenaltyPayee.self, forKey: .tobiPayee) ?? d.tobiPayee
        tobiUnit = try c.decodeIfPresent(PenaltyUnit.self, forKey: .tobiUnit) ?? d.tobiUnit

        yakitoriEnabled = try c.decodeIfPresent(Bool.self, forKey: .yakitoriEnabled) ?? d.yakitoriEnabled
        yakitoriPenalty = try c.decodeIfPresent(Int.self, forKey: .yakitoriPenalty) ?? d.yakitoriPenalty
        yakitoriPayee = try c.decodeIfPresent(PenaltyPayee.self, forKey: .yakitoriPayee) ?? d.yakitoriPayee
        yakitoriUnit = try c.decodeIfPresent(PenaltyUnit.self, forKey: .yakitoriUnit) ?? d.yakitoriUnit

        kubiEnabled = try c.decodeIfPresent(Bool.self, forKey: .kubiEnabled) ?? d.kubiEnabled
        kubiCondition = try c.decodeIfPresent(KubiCondition.self, forKey: .kubiCondition) ?? d.kubiCondition
        kubiThreshold = try c.decodeIfPresent(Int.self, forKey: .kubiThreshold) ?? d.kubiThreshold
        kubiPenalty = try c.decodeIfPresent(Int.self, forKey: .kubiPenalty) ?? d.kubiPenalty
        kubiPayee = try c.decodeIfPresent(PenaltyPayee.self, forKey: .kubiPayee) ?? d.kubiPayee
        kubiUnit = try c.decodeIfPresent(PenaltyUnit.self, forKey: .kubiUnit) ?? d.kubiUnit
    }
}
