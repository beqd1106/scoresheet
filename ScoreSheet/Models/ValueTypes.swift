import Foundation

/// 卓に参加するプレイヤーのスナップショット。
/// Player（名簿）から複製して TableSession 内に保持する。
/// 名簿側で改名・削除されても過去の記録が壊れないように独立させる意図。
struct Participant: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

/// 1回戦における 1 プレイヤーの結果。
/// rawScore / isYakitori は素点入力モードで使う追加情報。
/// 旧バージョンの保存データには存在しないため Optional（省略時は nil としてデコードされる）。
struct PlayerRoundPoint: Codable, Hashable, Identifiable {
    var id: UUID
    var participantID: UUID
    var rank: Int              // 1 = トップ
    var point: Int
    var isAutoCalculated: Bool  // トップの自動計算値なら true
    var rawScore: Int?          // 素点モード：終局時の持ち点
    var isYakitori: Bool?       // 素点モード：ヤキトリ該当
    var busterID: UUID?         // 素点モード：この人を飛ばした人（トビ罰符の受取先に使う）

    init(id: UUID = UUID(), participantID: UUID, rank: Int, point: Int,
         isAutoCalculated: Bool, rawScore: Int? = nil, isYakitori: Bool? = nil,
         busterID: UUID? = nil) {
        self.id = id
        self.participantID = participantID
        self.rank = rank
        self.point = point
        self.isAutoCalculated = isAutoCalculated
        self.rawScore = rawScore
        self.isYakitori = isYakitori
        self.busterID = busterID
    }
}

/// 素点から算出した 1 プレイヤー分の精算内訳（非永続）。
struct RoundSettlement: Identifiable, Equatable {
    var id: UUID { participantID }
    var participantID: UUID
    var rank: Int
    var basePoint: Int      // 素点と返し点の差（端数処理後）
    var umaPoint: Int       // 順位点
    var penaltyPoint: Int   // トビ・ヤキトリ・クビの授受合計
    var okaPoint: Int       // オカ＋端数調整（トップのみ）
    var isTobi: Bool
    var isYakitori: Bool
    var isKubi: Bool = false

    /// この回戦の最終ポイント。
    var total: Int { basePoint + umaPoint + penaltyPoint + okaPoint }
}

/// チップ結果（各プレイヤー 1 件）。枚数はプラス・マイナス可。
struct ChipEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var participantID: UUID
    var chipCount: Int

    init(id: UUID = UUID(), participantID: UUID, chipCount: Int) {
        self.id = id
        self.participantID = participantID
        self.chipCount = chipCount
    }
}

/// 最終集計 1 プレイヤー分（計算結果・非永続）。
struct FinalResult: Identifiable {
    var id: UUID { participantID }
    var participantID: UUID
    var name: String
    var colorHex: String
    var roundPointTotal: Int
    var chipPointTotal: Int
    var grandTotal: Int
    var topCount: Int
    var averageRank: Double
    var rank: Int
}
