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

    var id: String { rawValue }
    var displayName: String { self == .top ? "トップが受け取る" : "他の人で山分け" }
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

    // MARK: ヤキトリ（1回も和了なし）
    var yakitoriEnabled: Bool = false
    var yakitoriPenalty: Int = 20
    var yakitoriPayee: PenaltyPayee = .others

    // MARK: クビ（最下位の罰符）
    var kubiEnabled: Bool = false
    var kubiPenalty: Int = 10
    var kubiPayee: PenaltyPayee = .top

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
