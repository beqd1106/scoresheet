# iCloud（CloudKit）同期 セットアップ手順

スコアシートは SwiftData + CloudKit で iCloud に自動同期します。
これにより **端末からアプリを消しても、同じ Apple ID で再インストールすればスコアが自動で戻ります**。

コード側（モデル・ModelContainer・entitlements・project.yml）はすでに対応済みです。
ただし CloudKit は Apple 側の設定が必要で、以下は**ブラウザでの手動作業**です。
※ これらを行う前に TestFlight ビルド（release.yml）を回すと、**署名でエラーになります**。

---

## 1. App ID に iCloud(CloudKit) を有効化

1. https://developer.apple.com/account → Certificates, Identifiers & Profiles → Identifiers
2. Bundle ID `com.beqd1106.scoresheet` を開く
3. Capabilities で **iCloud** にチェック → Services で **CloudKit** を選択
4. 「Edit」から使用する **iCloud Container** に
   `iCloud.com.beqd1106.scoresheet` を作成して割り当て（無ければ「+」で新規作成）
5. Save

## 2. 既存のプロビジョニングプロファイルを削除（重要）

CI（codemagic-cli-tools）は既存プロファイルがあると再利用してしまい、
iCloud 権限が入っていない古いプロファイルで署名が失敗します。

1. Profiles 一覧で `com.beqd1106.scoresheet` の **App Store** 用プロファイルを削除
2. 次回 release.yml 実行時に `--create` で iCloud 入りプロファイルが自動再生成されます

## 3. CloudKit スキーマ（Mac なし運用のため Development 環境を使用）

本アプリは entitlements に `com.apple.developer.icloud-container-environment = Development` を
設定しているため、**TestFlight ビルドでも CloudKit の Development 環境を使います**。
これにより、Mac がなくても **初回起動時にスキーマ（レコードタイプ）が自動生成**され、
Production への手動デプロイをしなくても同期が動きます。

- やること：特になし。TestFlight でアプリを起動すれば自動でスキーマが作られ同期が始まります。
- 確認したい場合：https://icloud.developer.apple.com/dashboard →
  コンテナ `iCloud.com.beqd1106.scoresheet` → Development 環境に `CD_TableSession` 等の
  レコードタイプが出来ていれば成功。

### 将来 App Store で一般公開するとき（今はしなくてよい）

一般公開ビルドは Production 環境が必要です。そのときだけ以下を行う：
1. `project.yml` / entitlements の `com.apple.developer.icloud-container-environment` を
   `Production` に変更（または削除）
2. CloudKit Console で Development のスキーマを **Deploy to Production**

## 4. 動作確認

- 端末Aでスコアを入力 → 端末B（同じ Apple ID）に自動反映されるか
- 端末Aでアプリ削除 → 再インストール → スコアが戻るか
- iCloud 未ログインでもアプリが起動する（ローカルのみで動作）ことを確認
  ※ コードは CloudKit 初期化失敗時にローカル保存へフォールバックします

---

## メモ

- entitlements: `ScoreSheet/ScoreSheet.entitlements`（`project.yml` の `entitlements` から生成）
- ModelContainer: `cloudKitDatabase: .automatic`（`ScoreSheetApp.swift`）
- モデルは CloudKit 制約に合わせ、全プロパティにデフォルト値・to-many は空配列デフォルト・unique 制約なし
- Push 通知（バックグラウンド即時同期）は未設定。起動時・保存時に同期されます。
  即時同期が欲しい場合は Push Notifications capability と `aps-environment` / Background Modes を追加。
