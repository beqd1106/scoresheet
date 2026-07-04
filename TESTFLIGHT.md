# TestFlight 配布手順（Codemagic）

Mac不要。Codemagic がクラウドの Mac で「ビルド→署名→TestFlightアップロード」まで実行します。
`codemagic.yaml` は用意済みなので、以下の**あなたのアカウント側の設定**だけ行えば配布できます。

---

## STEP 1. App Store Connect でアプリを登録
1. https://appstoreconnect.apple.com/apps を開く
2. 「＋」→「新規App」
3. 入力：
   - プラットフォーム：iOS
   - 名前：**スコアシート**
   - プライマリ言語：日本語
   - バンドルID：**com.beqd1106.scoresheet**
     - 一覧に無ければ https://developer.apple.com/account/resources/identifiers で
       同IDを先に登録（Explicit App ID）
   - SKU：`scoresheet`（任意の一意文字列）
4. 作成（この時点ではまだ審査には出しません。TestFlightの箱ができるだけ）

## STEP 2. App Store Connect API キーを発行
1. https://appstoreconnect.apple.com/access/integrations/api を開く
2. 「チーム鍵」→「＋」で新規キー
   - 名前：`codemagic`
   - アクセス：**App Manager**（またはAdmin）
3. 発行後に取得・控える：
   - **Issuer ID**（ページ上部の長いUUID）
   - **Key ID**
   - **AuthKey_XXXX.p8**（ダウンロードは1回だけ。無くさない）

## STEP 3. Codemagic に API キーを登録
1. https://codemagic.io/ にログイン（GitHubアカウントで可）→ このリポジトリ `scoresheet` を追加
2. Teams / Personal Account → Integrations → **App Store Connect** → Add key
   - 名前は **`scoresheet_asc`** にする（`codemagic.yaml` がこの名前を参照）
   - Issuer ID / Key ID / .p8 を貼り付け
3. コード署名：Codemagic の Automatic signing を使うので、上記キーがあれば
   証明書・プロファイルは自動生成されます（手動アップロード不要）

## STEP 4. 配布ビルドを実行
方法A（推奨・タグで配布）：ローカルで
```bash
cd Downloads/ScoreSheet
git tag v1.0.0
git push origin v1.0.0
```
方法B：Codemagic の画面から `ios-testflight` ワークフローを「Start new build」

数分後、ビルド成功で **TestFlight に自動アップロード** されます。

## STEP 5. テスターに配布
1. App Store Connect →「スコアシート」→ TestFlight
2. ビルドが「処理中」→数分で有効化
3. 内部テスト：ユーザーを追加（自分のApple ID等）→すぐ配布
4. 外部テスト：グループ作成＋簡単なテスト情報入力（軽いレビューあり）

---

## 補足
- **ビルド番号**は Codemagic の `$BUILD_NUMBER` を自動で CFBundleVersion に反映するため、
  再アップロードでも重複しません（`codemagic.yaml` で処理済み）。
- **バージョン**（1.0.0）を上げたい時は `project.yml` の `MARKETING_VERSION` を変更。
- 追加課金なし（既存のApple Developer会員＋Codemagic無料枠で完結）。
- 初回のみ App Store Connect の「輸出コンプライアンス」で
  「暗号化を使用していない」を選べば即進みます（本アプリは独自暗号化なし）。
