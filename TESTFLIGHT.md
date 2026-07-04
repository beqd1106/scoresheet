# TestFlight 配布手順（Codemagic）

Mac不要。Codemagic がクラウドの Mac で「ビルド→署名→TestFlightアップロード」まで実行します。
**API キーと Codemagic 連携はカチカン等で登録済みの `AppStoreConnect` を流用**するため、
新規のキー発行・Codemagic登録は不要です。

---

## 済んでいること（流用・作業不要）
- App Store Connect API キー（チームキー）… Codemagic に `AppStoreConnect` 名で登録済み
- 署名（証明書・プロファイル）… Codemagic の自動署名で毎回生成
- App ID `com.beqd1106.scoresheet` の登録 / App Store Connect アプリ「スコアシート」作成 … 済

## 残りの作業

### STEP A. Codemagic にこのリポジトリを追加（初回のみ・1クリック）
1. https://codemagic.io/apps を開く（GitHub連携済みのはず）
2. リポジトリ一覧に `beqd1106/scoresheet` があれば「Add application」→ iOS を選択
   - 無ければ「Add application」→ GitHub → `scoresheet` を選択
3. `codemagic.yaml` を自動検出するので、そのまま保存でOK（追加設定不要）

### STEP B. 配布ビルドを実行（タグを push するだけ）
```bash
cd Downloads/ScoreSheet
git tag v1.0.0
git push origin v1.0.0
```
→ Codemagic が `ios-testflight` を自動起動。数分でビルド→署名→**TestFlightへ自動アップロード**。
（Codemagic の画面から手動「Start new build」でも可）

### STEP C. テスターに配布
1. App Store Connect →「スコアシート」→ **TestFlight** タブ
2. アップロードされたビルドが「処理中」→数分で有効化
3. 内部テスト：テスターに自分のApple ID等を追加 → すぐ配布
4. 外部テスト：グループ作成＋テスト情報入力（軽いレビューあり）

---

## 補足
- **配信タブ（スクリーンショット/審査用に追加）は一般公開用**。TestFlightには不要なので触らなくてOK。
- **ビルド番号**は `$BUILD_NUMBER` を自動反映（再アップロードでも重複しない）。
- **バージョン**を上げる時は `project.yml` の `MARKETING_VERSION` を変更。
- **輸出コンプライアンス**は `ITSAppUsesNonExemptEncryption=NO` を宣言済みのため毎回の手入力は不要。
- 追加課金なし（既存Apple Developer会員＋Codemagic無料枠）。
