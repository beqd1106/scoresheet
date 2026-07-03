import Foundation

/// 三麻 / 四麻。
enum GameType: String, Codable, CaseIterable, Identifiable {
    case sanma   // 三麻（3人）
    case yonma   // 四麻（4人）

    var id: String { rawValue }

    /// 参加人数。
    var playerCount: Int { self == .sanma ? 3 : 4 }

    var displayName: String { self == .sanma ? "三麻" : "四麻" }
}
