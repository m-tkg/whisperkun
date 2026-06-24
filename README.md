# whisperkun

macOS のメニューバー常駐型の音声入力（ディクテーション）アプリ。ホットキーで録音し、
**オンデバイス**で文字起こし → 後処理（用語辞書の置換・AI整形）→ 前面アプリへ自動入力する。

- オンデバイス文字起こし（Speech framework / `SpeechAnalyzer`）
- オンデバイス AI 整形（Foundation Models / Apple Intelligence。フィラー除去・句読点補完など、意味は変えない軽整形）
- 単語単位のユーザー辞書（例: 「カルテ」→「KARTE」。ただし「カルティエ」内では置換しない）
- グローバル修飾キーのホットキー（push-to-talk / トグル、左右の修飾キー・複数同時押し対応）
- 文字起こし履歴、入力先への自動ペースト
- GitHub リリースからの自動アップデート

## 動作要件

- macOS 26.0 以降（Apple Intelligence 対応端末だと AI 整形が使える。非対応でも文字起こしは可能）
- マイク / 音声認識 / アクセシビリティ の各権限（初回起動のオンボーディングで案内）

## ビルドと実行

Swift Package Manager 製。XcodeGen は使わない。

```sh
swift build                 # ビルド
swift test                  # テスト（whisperkunCore の純ロジック）
swift run                   # 開発中の直接実行

bash Scripts/bundle.sh      # .app バンドルを生成（既定 release・ad-hoc 署名）
open Whisperkun.app
```

### ローカル検証ビルド

本番アプリ（`com.mtkg.whisperkun`）を既にアクセシビリティ許可済みだと、同じバンドルIDの
ローカルビルドは権限を独立して付与できない。`LOCAL=1` を付けるとバンドルID と表示名を分けた
「whisperkun (Local)」（`com.mtkg.whisperkun.local`）を生成し、システム設定の権限一覧に
本番と別エントリとして並ぶ。

```sh
LOCAL=1 bash Scripts/bundle.sh debug
open "Whisperkun (Local).app"
```

## アーキテクチャ

2ターゲット構成。純粋ロジックを `whisperkunCore` に分離し、テスト対象にする。

- **whisperkunCore**（ライブラリ / テスト対象）
  - `DictionaryService` … 単語単位の用語置換（`NLTokenizer` の境界に一致する箇所のみ置換）
  - `DictionaryRule` … 置換ルール
  - `Release` … GitHub リリース情報モデル ＋ バージョン比較（`VersionComparator`）
- **whisperkun**（実行ファイル / AppKit + SwiftUI）
  - `App/` … `WhisperkunApp`（MenuBarExtra ＋ Settings）、`AppState`（ルート状態・SwiftData ブリッジ）
  - `Pipeline/DictationCoordinator` … 録音→文字起こし→後処理→挿入の統括
  - `Services/` … `TranscriptionService`（Speech）、`AIService`（Foundation Models）、
    `TextInsertionService`（ペースト）、`HotkeyService`（CGEventTap）、`PermissionsManager`、
    `SettingsStore`、`BufferConverter`、`UpdateService` / `SelfUpdater`（自動更新）
  - `UI/` … `MenuBarView`、`RecordingHUD`、`OnboardingView`、`ActivationPolicyController`、`Settings/`

データフロー:

```
ホットキー / 手動トグル
  → 録音（AVAudioEngine）＋オンデバイス文字起こし（SpeechAnalyzer）
  → 後処理（DictationCoordinator）: 辞書置換 → AI整形
  → 前面アプリへ挿入（Cmd+V 合成）
  → 履歴を保存（SwiftData）
```

## 権限・署名

- App Sandbox 無効（他アプリへのペースト / CGEventTap のため）、Hardened Runtime 有効、マイク用エンタイトルメント。
- 配布用の Developer ID 署名・公証（notarization）の設定は [docs/SIGNING.md](docs/SIGNING.md) を参照。

## リリース

`main` への push で GitHub Actions（`.github/workflows/release.yml`）が走り、
`Resources/Info.plist` の `CFBundleShortVersionString` を読んで `v<version>` のタグ付き
リリース（署名・公証済み `Whisperkun.zip`）を作成する。リリースしたいときは Info.plist の
バージョンを上げてマージする。

## ライセンス

未定。
