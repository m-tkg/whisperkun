# CLAUDE.md

このリポジトリで作業する際のガイド。

## 概要

Whisperkun は macOS のメニューバー常駐型ディクテーションアプリ。ホットキーで録音し、
オンデバイスで文字起こし → 辞書置換 → AI整形 → 前面アプリへ自動入力する。
詳細は [README.md](README.md)、署名/公証は [docs/SIGNING.md](docs/SIGNING.md) を参照。

- Swift 6.0 / macOS 26.0 / Swift Package Manager（XcodeGen は使わない）
- バンドルID: `dev.mtkg.Whisperkun`（ローカル検証ビルドは `dev.mtkg.Whisperkun.local`）

## ビルド・テストコマンド

```sh
swift build                          # ビルド
swift test                           # 全テスト
swift test --filter <Name>           # 個別（例: DictionaryServiceTests）
swift run                            # 直接実行（開発時）
bash Scripts/bundle.sh               # .app 生成（既定 release・ad-hoc 署名）
LOCAL=1 bash Scripts/bundle.sh debug # ローカル検証用（本番と別バンドルID・別名）
```

テストは **Swift Testing**（`@Suite` / `@Test`）。対象は `WhisperkunCore` の純ロジックのみ。

## アーキテクチャ

2ターゲット。純粋ロジック（プラットフォーム非依存・テスト可能）を `WhisperkunCore` に分離する。

- **WhisperkunCore**: `DictionaryService`（単語単位置換）、`DictionaryRule`、`Release` / `VersionComparator`。
- **Whisperkun**（実行ファイル）: `App/`（`WhisperkunApp` / `AppState`）、`Pipeline/DictationCoordinator`、
  `Services/`（Transcription / AI / TextInsertion / Hotkey / Permissions / SettingsStore / BufferConverter /
  Update・SelfUpdater）、`UI/`（MenuBarView / RecordingHUD / OnboardingView / ActivationPolicyController / Settings）。
- `AppState`（`@MainActor @Observable`）がルート状態で、SwiftData（`DictionaryEntry` / `TranscriptionRecord`）と
  各サービスを束ねる。後処理は `DictationCoordinator.process`: **辞書置換 → AI整形** の順。

## 重要な実装上の注意

- **メニューバー常駐（`LSUIElement` / `.accessory`）**: ウィンドウは通常前面に出ない。設定/オンボーディングは
  表示中だけ `ActivationPolicyController` で `.regular` に切り替え、明示的に `activate` + `makeKeyAndOrderFront`
  （`orderFrontRegardless` で背面の既存ウィンドウも前へ）して最前面化する。閉じたら `.accessory` に戻す。
- **Swift 6 並行性 × システムコールバック**: CGEventTap / AVAudioEngine のタップ / `SFSpeechRecognizer`
  の完了ハンドラなどは**バックグラウンドスレッド**で呼ばれる。`@MainActor` 隔離と推論されたクロージャを
  そこで実行すると隔離アサーションでクラッシュする。対策:
  - C コールバック（CGEventTap）は `DispatchQueue.main.async` でメインキュー文脈に乗せてから `MainActor.assumeIsolated`。
    非Sendable は捕捉せず、ポインタは `UInt(bitPattern:)` で渡す。
  - オーディオタップ・完了ハンドラのクロージャは `@Sendable` を付けて非隔離にする（捕捉する型も Sendable に）。
- **録音停止の固着防止**: `TranscriptionService.stop()` は Speech の確定処理が稀に返らないため、
  `withTaskGroup` で**タイムアウト（3秒）**を設け、超過時は暫定テキストで確定して `phase` を戻す。
- **辞書置換の性能**: トークン化（`NLTokenizer`）は `apply` で**1回だけ**。境界は `String.Index` 集合で持ち、
  ルールごとの再トークン化や `String.distance` の O(n²) を避ける。
- **ローカル vs 本番の TCC 衝突**: 同一バンドルIDだと権限が共有され、本番許可済みだとローカルを独立許可できない。
  検証は `LOCAL=1`（別バンドルID `*.local`）でビルドする。
- **ad-hoc 署名**は再ビルドごとに署名が変わり TCC 権限が外れる。保持したいときは安定した署名IDを使う（docs/SIGNING.md）。

## リリース運用

- `main` への push で `.github/workflows/release.yml` が走り、`Resources/Info.plist` の
  `CFBundleShortVersionString` から `v<version>` を作成する（Secrets があれば Developer ID 署名＋公証）。
- リリースしたいときだけ Info.plist のバージョンを上げる。CI ランナーは macOS 26 専用 API（FoundationModels /
  Speech）のため `runs-on: macos-26`。
- **バージョンを上げる PR は1つずつ、Release ワークフロー完了を待ってから次をマージ**する。
  複数を相次いでマージすると、CI 完了順の影響で古いタグが「Latest」を奪うことがある
  （その場合は `gh release edit v<latest> --latest` で修正）。

## 開発フロー

- 直接 `main` にコミットせず PR を作る。
- 純粋ロジック（`WhisperkunCore`）はテストを書く。UI / AX / 録音まわりは実機での手動確認。
  `.menu` 形式のメニューはネイティブ項目なので System Events での自動確認が可能。
- 一時ファイルは `.claude/tmp/` 以下に置く。
