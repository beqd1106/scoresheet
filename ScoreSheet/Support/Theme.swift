import SwiftUI

// MARK: - デザイントークン
// コンセプト：大人が日常使いできる「上品な記録ノート」。
// オフホワイトの紙面・極細の罫線・ネイビー/くすんだブルー/深緑の差し色。
// ライトを基本にダークでも雰囲気を壊さない。色数は3〜4色に抑える。

enum Theme {

    // MARK: 紙面・インク（背景と文字）
    /// ページ全体の背景（生成りに近いオフホワイト）。
    static let paper       = Color(light: "F7F4EC", dark: "16181C")
    /// カード＝ノートの1ページ（やや明るい紙）。
    static let card        = Color(light: "FFFFFF", dark: "1F2228")
    /// 沈んだ区画（ヘッダー帯・入力欄など）。
    static let sunken      = Color(light: "F1EDE2", dark: "24272E")

    /// 主要テキスト（黒に近いネイビー寄り）。
    static let ink         = Color(light: "1F2A37", dark: "ECEAE3")
    /// 補助テキスト。
    static let inkSecond   = Color(light: "5B6673", dark: "A7ADB6")
    /// さらに弱いテキスト・プレースホルダ。
    static let inkFaint    = Color(light: "97A0AB", dark: "6E757E")

    // MARK: 罫線（繊細に）
    /// 汎用の極細罫線（温かみのある薄グレー）。
    static let rule        = Color(light: "E6E1D4", dark: "2E323A")
    /// 淡いブルーの区切り（ノートの罫線感）。
    static let ruleBlue    = Color(light: "DCE3EA", dark: "313742")
    static let hairline: CGFloat = 1

    // MARK: 差し色（アクセント）
    /// ネイビー：主役ボタン・見出しのアクセント。
    static let accent      = Color(light: "23395B", dark: "8AA6C6")
    /// くすんだブルー。
    static let mutedBlue   = Color(light: "4A6C8C", dark: "7EA0C4")
    /// 深めのグリーン。
    static let deepGreen   = Color(light: "2F5D50", dark: "77A99A")
    /// 落ち着いたベージュ（バッジ・補助）。
    static let beige       = Color(light: "C9B896", dark: "9C8C68")

    // MARK: 数値の符号色（強すぎない）
    /// プラス：落ち着いた青。
    static let positive    = Color(light: "2F5D8A", dark: "7EA9D6")
    /// マイナス：強すぎない赤茶。
    static let negative    = Color(light: "A24B3C", dark: "D19488")

    static func pointColor(_ value: Int) -> Color {
        if value > 0 { return positive }
        if value < 0 { return negative }
        return inkFaint
    }

    // MARK: 順位バッジ色（派手にしない）
    static func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1:  return accent      // ネイビー
        case 2:  return mutedBlue
        case 3:  return deepGreen
        default: return Color(light: "8A8577", dark: "8A8F98")
        }
    }

    /// プレイヤーに割り当てる控えめなカラーパレット。
    static let playerPalette: [String] = [
        "23395B", // ネイビー
        "2F5D50", // 深緑
        "8C5A3C", // ブラウン
        "4A6C8C", // くすんだブルー
        "6A5A7A", // すみれ
        "7A6A45", // ベージュブラウン
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
    static let card:    CGFloat = 14   // 丸すぎない自然な角丸
    static let control: CGFloat = 10
    static let small:   CGFloat = 8
    static let pill:    CGFloat = 999
}

// MARK: - タイポグラフィ
// 見出し：セリフでほんの少しノート感／本文：サンセリフ／数値：等幅数字で視認性最優先。

enum AppFont {
    /// ページ見出し（インデックスラベル風）。
    static func label(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    /// セクション大見出し。
    static func heading(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
    /// スコア・順位の数値（等幅）。
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    /// 本文。
    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Color 補助

extension Color {
    /// ライト/ダークで切り替わる動的カラー。
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

/// プラス記号付き整数（0 は "0"、負は "-" 付き）。
extension Int {
    var signedPointString: String { self > 0 ? "+\(self)" : "\(self)" }
}
