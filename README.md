# スコアシート（麻雀の記録帳）

三麻・四麻に対応した、対局結果を記録・集計する iOS アプリ（SwiftUI / SwiftData / MVVM）。
和了点の計算は行わず、**各回のポイントとチップ枚数を入力して最終合計を見やすく集計する**ことに特化。

> スコア管理・成績記録用アプリです。ポイント係数は成績換算のための数値で、実金額や精算を表しません。

## 特長
- 三麻 / 四麻の切り替え
- 回戦を無限に追加（1回戦・2回戦…）
- 2着以下のポイントを入力するとトップを自動計算（合計が 0 になる）
- チップは最後にまとめて入力（1枚あたりの係数で自動換算）
- 最終結果をランキング表示（対局／チップ／総合・トップ回数・平均順位）
- 履歴の保存・編集・削除、CSV 出力、ダークモード対応
- ローカル保存（SwiftData）でオフライン完結・低コスト

## デザイン
「大人が日常使いできる上品な記録ノート」。オフホワイトの紙面・極細の罫線・
ネイビー／くすんだブルー／深緑の差し色で統一。数値は等幅で視認性最優先。
デザイントークンは `Support/Theme.swift`、共通部品は `Support/Components.swift`。

## ビルド（Mac不要 / GitHub Actions）
XcodeGen でプロジェクトを生成してビルドします。

```bash
brew install xcodegen
xcodegen generate
open ScoreSheet.xcodeproj   # Mac の場合
```

GitHub に push すると `.github/workflows/ios.yml` がシミュレータ向けにビルド確認します
（署名なし）。TestFlight 配布時は署名シークレットの追加が必要です。

## 構成
```
ScoreSheet/
  ScoreSheetApp.swift
  Support/     AppSettings / Theme（デザイントークン）/ Components（共通部品）
  Models/      GameType / ValueTypes / Player / RoundResult / TableSession
  Services/    ScoreCalculator / CSVExporter / SampleDataService
  ViewModels/  TableSetup / RoundInput / ChipInput / FinalResult / Other(Home/History/TableScore/Settings)
  Views/       Root / Home / TableSetup / TableScore / RoundInput / ChipInput / FinalResult / History / PlayerList / Settings
```

## 将来拡張
iCloud / AWS 同期、共有、グラフ。クラウド化時は月額 2 万円以内・サーバーレス優先・
AWS Budgets / Cost Anomaly Detection を必須設計。
