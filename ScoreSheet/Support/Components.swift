import SwiftUI

// MARK: - 再利用コンポーネント（ノート感を余白・罫線・ラベルで表現）

/// ページ背景（白地＋うっすら方眼グリッド）。テンパス準拠。
struct NotePageBackground: View {
    var spacing: CGFloat = 24
    var body: some View {
        ZStack {
            Theme.paper
            Canvas { ctx, size in
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                ctx.stroke(path, with: .color(Theme.grid), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

/// ノートのインデックスラベル風の小見出し。短い下線付き。
struct SectionLabel: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Space.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.mutedBlue)
            }
            Text(text)
                .font(AppFont.label(13))
                .tracking(0.5)
                .foregroundStyle(Theme.inkSecond)
        }
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(Theme.mutedBlue.opacity(0.5))
                .frame(width: 22, height: 2)
                .offset(y: 6)
        }
        .padding(.bottom, 4)
    }
}

/// ノートの1ページのようなカード。白い紙・極細枠・ごく薄い影。
struct NoteCard<Content: View>: View {
    var padding: CGFloat = Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        // VStack で包まないと、複数ビューを渡したとき TupleView が親のレイアウトに
        // 展開され、子ごとに別々のカードになってしまう。
        VStack(alignment: .leading, spacing: 0) {
            content
        }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Theme.rule, lineWidth: Theme.hairline)
            )
        // 影なし・フラット（テンパス準拠）
    }
}

/// 極細の区切り線。
struct HairlineRule: View {
    var color: Color = Theme.rule
    var body: some View {
        Rectangle().fill(color).frame(height: Theme.hairline)
    }
}

/// 符号付きスコア表示（等幅・符号色）。
struct PointText: View {
    let value: Int
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(value.signedPointString)
            .font(AppFont.number(size, weight: weight))
            .foregroundStyle(Theme.pointColor(value))
    }
}

/// 順位バッジ（丸すぎない角丸の四角）。
struct RankBadge: View {
    let rank: Int
    var size: CGFloat = 26

    var body: some View {
        Text("\(rank)")
            .font(AppFont.number(size * 0.55, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Theme.rankColor(rank))
            )
    }
}

/// プレイヤーの色ドット。
struct PlayerDot: View {
    let colorHex: String
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(Color(hex: colorHex)).frame(width: size, height: size)
    }
}

// MARK: - ボタンスタイル

/// 主役ボタン：ネイビー塗り、大きめでタップしやすい。
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.body(16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(enabled ? Theme.accent : Theme.inkFaint)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 副ボタン：枠線のみ。
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.body(16, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Theme.accent.opacity(0.4), lineWidth: Theme.hairline)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - 空状態

struct EmptyNote: View {
    let title: String
    let message: String
    var systemImage: String = "book.closed"

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.inkFaint)
            Text(title).font(AppFont.heading(18)).foregroundStyle(Theme.ink)
            Text(message)
                .font(AppFont.body(14))
                .foregroundStyle(Theme.inkSecond)
                .multilineTextAlignment(.center)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
    }
}
