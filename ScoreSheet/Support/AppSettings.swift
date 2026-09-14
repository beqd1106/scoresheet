import SwiftUI

/// UserDefaults に保存するデフォルト設定のキー。
enum AppSettingsKey {
    static let defaultGameType = "settings.defaultGameType"
    static let pointCoefficientPer1000 = "settings.pointCoefficientPer1000"
    static let chipPointCoefficient = "settings.chipPointCoefficient"
    static let quickPoints = "settings.quickPoints"        // カンマ区切り "5,10,15,20,30"
    static let appearance = "settings.appearance"
    static let defaultInputMode = "settings.defaultInputMode"
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
    static let pointCoefficientPer1000: Double = 50   // 1000点 = 50pt
    static let chipPointCoefficient: Double = 100      // チップ1枚 = 100pt
    static let quickPoints: [Int] = [50, 100, 150, 200, 300]

    // 係数入力の刻みと上限
    static let per1000Step: Double = 50
    static let per1000Max: Double = 1000
    static let chipStep: Double = 100
    static let chipMax: Double = 2000
}
