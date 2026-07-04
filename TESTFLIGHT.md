# TestFlight 配布手順（GitHub Actions）

Mac不要。RankYomi と同じ **GitHub Actions（`.github/workflows/release.yml`）** で
「ビルド → 自動署名 → TestFlight アップロード」まで実行する。Codemagic は使わない。

署名は `codemagic-cli-tools` が App Store Connect API キーと固定の配布証明書秘密鍵
（`CERTIFICATE_PRIVATE_KEY`）から、証明書とプロビジョニングを `--create` で自動用意する。
ランナーは `macos-26`（App Store Connect が iOS 26 SDK / Xcode 26 以降を要求するため）。

---

## 必要な GitHub Secrets（beqd1106/scoresheet リポジトリ）
| Secret | 内容 | 状態 |
|---|---|---|
| `CERTIFICATE_PRIVATE_KEY` | 配布証明書の秘密鍵(PEM) | 設定済み（scoresheet_dist.p12 から抽出） |
| `ASC_ISSUER_ID` | App Store Connect の Issuer ID | 要設定 |
| `ASC_KEY_ID` | API キーの Key ID | 要設定 |
| `ASC_KEY_P8` | API キー(.p8)の中身 | 要設定 |

ASC 3種は RankYomi と同じチームキーを流用可（`Desktop/appleP8/AuthKey_*.p8`）。

## 実行
1. GitHub → Actions → `release-testflight` → **Run workflow**（`main`）
   - もしくは `gh workflow run release-testflight.yml --repo beqd1106/scoresheet`
2. 数分で「ビルド → 署名 → TestFlight アップロード」まで自動実行
3. App Store Connect →「スコアシート」→ TestFlight でビルドが処理中→有効化

## テスターに配布
- 内部テスト：テスターに Apple ID を追加 → すぐ配布
- 外部テスト：グループ作成＋テスト情報入力（軽いレビューあり）

## 補足
- ビルド番号は GitHub の run 番号を自動反映（重複しない）。
- バージョンを上げる時は `project.yml` の `MARKETING_VERSION` を変更。
- 輸出コンプラは `ITSAppUsesNonExemptEncryption=NO` 宣言済み。
- `ios.yml`（build + テスト）は push 毎に自動実行のコンパイル/回帰チェック。
