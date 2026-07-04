import SwiftUI

// MARK: - デザイントークン
// コンセプト（テンパス準拠）：白い方眼ノート × クリーン／フラット。
// 純白背景＋うっすら方眼グリッド、影なし、細い罫線、赤/青/黄の原色をポイント使い。
// 「雀荘っぽさ（緑・和紙・金）」は避ける。ライト基本、ダークでも雰囲気維持。

enum Theme {

    // MARK: 紙面・インク
    static let paper       = Color(light: "FFFFFF", dark: "111318")
    static let card        = Color(light: "FFFFFF", dark: "1A1D23")
    static let sunken      = Color(light: "F2F4F8", dark: "20242B")

    static let ink         = Color(light: "1B1E23", dark: "ECEEF2")
    static let inkSecond   = Color(light: "5A616B", dark: "A6ADB6")
    static let inkFaint    = Color(light: "9AA1AB", dark: "6E757E")

    // MARK: 罫線・方眼
    static let rule        = Color(light: "E2E4EA", dark: "2C313A")
    static let grid        = Color(light: "E7E9EF", dark: "252A32")  // 方眼グリッド線
    static let ruleBlue    = Color(light: "DDE6F5", dark: "2A3340")
    static let hairline: CGFloat = 1

    // MARK: 原色アクセント
    static let accent      = Color(light: "1F63E0", dark: "6BA0FF")  // 青（主役）
    static let mutedBlue   = Color(light: "3B6FD4", dark: "7FA8F0")
    static let accentRed   = Color(light: "E2413F", dark: "F0837C")
    static let accentYellow = Color(light: "E5A812", dark: "F0BE45")
    static let deepGreen   = Color(light: "2E7D6B", dark: "6FBCA9")  // 互換用（ほぼ不使用）
    static let beige       = Color(light: "B7A17A", dark: "9C8C68")  // 互換用

    // MARK: 数値の符号色（＋青 / −赤）
    static let positive    = Color(light: "1F63E0", dark: "6BA0FF")
    static let negative    = Color(light: "E2413F", dark: "F0837C")

    static func pointColor(_ value: Int) -> Color {
        if value > 0 { return positive }
        if value < 0 { return negative }
        return inkFaint
    }

    // MARK: 順位バッジ色（原色ベース・フラット）
    static func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1:  return accent          // 青
        case 2:  return Color(light: "6B7280", dark: "9AA1AB")  // スレート
        case 3:  return accentYellow    // 黄
        default: return Color(light: "A0A6AE", dark: "7C828B")  // グレー
        }
    }

    /// プレイヤーに割り当てる控えめカラー。
    static let playerPalette: [String] = [
        "1F63E0", // 青
        "E2413F", // 赤
        "E5A812", // 黄
        "2E7D6B", // ティール
        "6A5A7A", // すみれ
        "8C5A3C", // ブラウン
    ]
}

// MARK: - 余白・角丸スケール

enum Space {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum Radius {
    static let card:    CGFloat = 14
    static let control: CGFloat = 10
    static let small:   CGFloat = 8
    static let pill:    CGFloat = 999
}

// MARK: - タイポグラフィ
// 見出し：やや太めサンセリフ／本文：サンセリフ／数値：等幅で視認性最優先。

enum AppFont {
    static func label(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold)
    }
    static func heading(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold)
    }
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Color 補助

extension Color {
    init(light: String, dark: String) {
        self = Color(UIColor { tc in
            UIColor(Color(hex: tc.userInterfaceStyle == .dark ? dark : light))
        })
    }

    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let r, g, b: UInt64
        if s.count == 6 {
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        } else {
            (r, g, b) = (127, 127, 127)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }
}

extension Int {
    var signedPointString: String { self > 0 ? "+\(self)" : "\(self)" }
}
