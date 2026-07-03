import SwiftUI

/// UserDefaults に保存するデフォルト設定のキー。
enum AppSettingsKey {
    static let defaultGameType = "settings.defaultGameType"
    static let pointCoefficientPer1000 = "settings.pointCoefficientPer1000"
    static let chipPointCoefficient = "settings.chipPointCoefficient"
    static let quickPoints = "settings.quickPoints"        // カンマ区切り "5,10,15,20,30"
    static let appearance = "settings.appearance"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "端末に合わせる"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppDefaults {
    static let pointCoefficientPer1000: Double = 1.0
    static let chipPointCoefficient: Double = 5.0
    static let quickPoints: [Int] = [5, 10, 15, 20, 30]
}
