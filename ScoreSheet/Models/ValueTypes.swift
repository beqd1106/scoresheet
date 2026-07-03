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
struct PlayerRoundPoint: Codable, Hashable, Identifiable {
    var id: UUID
    var participantID: UUID
    var rank: Int              // 1 = トップ
    var point: Int
    var isAutoCalculated: Bool  // トップの自動計算値なら true

    init(id: UUID = UUID(), participantID: UUID, rank: Int, point: Int, isAutoCalculated: Bool) {
        self.id = id
        self.participantID = participantID
        self.rank = rank
        self.point = point
        self.isAutoCalculated = isAutoCalculated
    }
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
