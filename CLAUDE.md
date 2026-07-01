# CLAUDE.md

このリポジトリで作業する際のガイド。共通方針は上位の
[CLAUDE_base.md](../CLAUDE_base.md)（メニューバー常駐アプリ共通ガイド）に従い、
本ファイルには whisperkun 固有の事項を記す。

## 概要

whisperkun は macOS のメニューバー常駐型ディクテーションアプリ。ホットキーで録音し、
オンデバイスで文字起こし → 辞書置換 → AI整形 → 前面アプリへ自動入力する。
詳細は [README.md](README.md)、署名/公証は [docs/SIGNING.md](docs/SIGNING.md) を参照。

- Swift 6.0 / macOS 26.0 / Swift Package Manager（XcodeGen は使わない）
- バンドルID: `com.mtkg.whisperkun`（ローカル検証ビルドは `com.mtkg.whisperkun.local`）。
  `Info.plist` の `CFBundleIdentifier`、`Scripts/bundle.sh` で一貫させる。ログの subsystem は
  `Support/Log.swift` に一元化されており（`Log.logger(category:)` を使う）、`Logger(subsystem:)` を直書きしない。
  `.local` の基底ID判定は `whisperkunCore` の `BundleIdentity` を使う。

## ビルド・テストコマンド

```sh
swift build                          # ビルド
swift test                           # 全テスト
swift test --filter <Name>           # 個別（例: DictionaryServiceTests）
swift run                            # 直接実行（開発時）
bash Scripts/bundle.sh               # .app 生成（既定 release・ad-hoc 署名）
LOCAL=1 bash Scripts/bundle.sh debug # ローカル検証用（本番と別バンドルID・別名）
```

テストは **Swift Testing**（`@Suite` / `@Test`）。対象は `whisperkunCore` の純ロジックのみ。

## アーキテクチャ

2ターゲット。純粋ロジック（プラットフォーム非依存・テスト可能）を `whisperkunCore` に分離する。

- **whisperkunCore**: `DictionaryService`（単語単位置換）、`DictionaryRule`、`ReleaseInfo` / `VersionComparator`。
- **whisperkun**（実行ファイル）: `App/`（`WhisperkunApp` / `AppState`）、`Pipeline/DictationCoordinator`、
  `Services/`（Transcription / AI / TextInsertion / Hotkey / Permissions / LaunchAtLogin / SettingsStore /
  BufferConverter / Update・SelfUpdater）、`UI/`（MenuBarView / RecordingHUD / OnboardingView /
  ActivationPolicyController / Settings）。
- `AppState`（`@MainActor @Observable`）がルート状態で、SwiftData（`DictionaryEntry` / `TranscriptionRecord`）と
  各サービスを束ねる。後処理は `DictationCoordinator.process`: **辞書置換 → AI整形** の順。

base 必須チェックリストの実装対応（実装済み）:

- **多重起動防止**: `AppState.terminateIfAlreadyRunning()` が同 bundle ID の他インスタンスを前面化して `exit(0)`。
- **自動起動（ログイン項目）**: `LaunchAtLoginService` が `SMAppService.mainApp` を register/unregister。
  **状態はシステム側が source of truth**（`Settings`/JSON に持たず、表示時に読み直す）。トグルは即時反映。
- **設定ダイアログ**: SwiftUI の `Settings` シーンを `TabView` で機能ごとに分割（一般/権限/ホットキー/辞書/履歴）。
  「一般」タブは左端。表示中は `ActivationPolicyController` が `.regular`、全クローズで `.accessory` に戻す。
- **メニュー先頭のバージョン**: `MenuBarView` 先頭に `whisperkun <version>`。ローカルビルドは
  `WhisperkunApp.isLocalBuild`（bundle ID が `.local` 終端か）でアイコンに「ローカル」を併記。
- **自己更新**: `UpdateService`（公開 GitHub API を ephemeral セッションで取得）＋ `SelfUpdater`
  （zip を `ditto` 展開 → **基底ID（`.local` 除去）で bundle ID 検証** → 切り離しスクリプトで入替・再起動）。
  基底ID比較によりローカルビルドからも本番リリースへ更新できる。
- **定期監視＋スリープ復帰チェック**: `AppState.scheduleUpdateChecks()`（init で配線）が起動時1回に加え
  `Timer.scheduledTimer`（間隔 **1時間**・`tolerance` 10%）で定期サイレントチェックし、`Timer` がスリープ中に
  発火しないため `NSWorkspace.didWakeNotification` で**復帰時にも即チェック**する。間隔は未認証 GitHub API の
  レート制限 **60回/時** に十分収まる値。タイマー/通知ブロックは非隔離なので `MainActor.assumeIsolated` で
  `startUpdateCheck(interactive:)` を呼ぶ。
- **メニューバーの赤バッジ**: 新版があるとアイコン右下に赤丸（最新なら消す）。更新有無は
  `AppState.setAvailableRelease(_:)`（base の `setUpdateAvailable`/`clearUpdateAvailable` 相当）に**集約**し、
  `onUpdateAvailabilityChanged` クロージャで `AppDelegate` のバッジと同期する（起動時・定期・復帰・手動の全経路が
  ここを通る）。バッジは `UI/UpdateBadgeView`（`NSView`+`CALayer` の赤丸・白縁取り）を `statusItem.button` に
  オーバーレイし、**アイコン幅基準で右下に Auto Layout 固定**（`leading = button.leading + (iconWidth - badgeSize)`、
  `bottom = button.bottom`）。「ローカル」併記時（`imagePosition = .imageLeading`）でもアイコングリフ右下に乗る。
  ベース画像は **template のまま維持**（焼き込まない）、`hitTest` を `nil` 返しにしてクリックをボタンへ透過させる。
  kuntraykun に集約されアイコンを隠している間（`statusItem.isVisible = false`）はバッジも非表示（集約先への伝搬は対象外）。

## ローカライズ（固有方式）

base は `Localization.swift` の `L.string`/`L.format` 方式だが、**whisperkun は SwiftUI の自動ローカライズを採用**する。

- 方式は「**キー＝日本語ソース文字列**」。SwiftUI が自動で `Localizable.strings` を引く
  （`Text("...")` / `Toggle("...")` / `LocalizedStringKey` 等）。補間 `Text("〜: \(x)")` は `%@` 形式キーになる。
  コードから明示参照する場面は `String(localized: "...")` を使う（メニュー文言・HUD ステータス等）。
- **UI 文字列を追加・変更したら必ず日英両方をローカライズする**。`Resources/ja.lproj/Localizable.strings` と
  `Resources/en.lproj/Localizable.strings` の**両方**にエントリを足す（日本語側はキーと値が同一）。
  en/ja でキー集合を一致させること。
- `Info.plist` に **`CFBundleLocalizations`（en, ja）が必須**。無いと macOS がアプリ言語を開発リージョンに
  固定し、ローカライズが効かなくなる。`CFBundleDevelopmentRegion` は `ja`（日本語優先アプリ）。
- `.lproj` は `Scripts/bundle.sh` が `Contents/Resources/` にコピーする（`Package.swift` の resources 指定は使わない）。

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

### イベントタップ（CGEventTap）

ホットキーは `HotkeyService` が `CGEventTap` で `flagsChanged` を監視して修飾キーの押下/解放を検出する
（録音開始/停止のトリガー）。base「イベントタップ系」に準拠した注意点:

- **`listenOnly` で監視し、イベントは消費しない**（通常の入力を妨げない）。アクセシビリティ権限が前提。
- **コールバック内で重い処理や同期 post をしない**。副作用は `DispatchQueue.main.async` で復帰後に逃がす。
- **`tapDisabledByTimeout` / `tapDisabledByUserInput` では `tapEnable` で再有効化**し、取りこぼし後の固着を防ぐ。

## リリース運用

- `main` への push で `.github/workflows/release.yml` が走り、`Resources/Info.plist` の
  `CFBundleShortVersionString` から `v<version>` を作成する（Secrets があれば Developer ID 署名＋公証、
  無ければ ad-hoc 署名・公証スキップにフォールバック）。
- リリースしたいときだけ Info.plist のバージョンを上げる。CI ランナーは macOS 26 専用 API（FoundationModels /
  Speech）のため `runs-on: macos-26`。
- **バージョンを上げる PR は1つずつ、Release ワークフロー完了を待ってから次をマージ**する。
  複数を相次いでマージすると、CI 完了順の影響で古いタグが「Latest」を奪うことがある
  （その場合は `gh release edit v<latest> --latest` で修正）。
- **配布署名/公証の Secrets（計6つ）** は上位の `setup-release-secrets.sh` で一括登録する:
  ```sh
  ~/git/github.com/m-tkg/setup-release-secrets.sh -r m-tkg/whisperkun
  ```
  署名は Developer ID Application（Team ID `G72M73C546`）。安定署名で TCC 権限がアップデート越しに保持される。
  詳細は [docs/SIGNING.md](docs/SIGNING.md)。

## 開発フロー

- **`main` へ直接コミット/push しない**。変更は必ず PR 経由（`gh pr create`）。main への push はリリースに直結する。
- 作業ブランチは**必ず最新の `main` から切る**:
  `git fetch origin && git switch main && git pull --ff-only`（または `git fetch && git switch -c <branch> origin/main`）。
- **PR 作成後に追加修正するときは、まず `gh pr view <番号> --json state,mergedAt` でマージ済みでないか確認する**。
  マージ済みなら作業ブランチへ push しても main に反映されない（孤立する）ので、**最新 `main` から新ブランチを切り直して別 PR を出す**
  （元コミットは `git cherry-pick <sha>` で移植できる）。
- 純粋ロジック（`whisperkunCore`）はテストを書く（原則 TDD）。UI / AX / 録音まわりは実機での手動確認。
  `.menu` 形式のメニューはネイティブ項目なので System Events での自動確認が可能。
- 新機能の追加手順: ①判定ロジックを `whisperkunCore` に純粋実装＋テスト → ②設定が要るなら `Settings` に追加 →
  ③設定 UI（タブ）を足す → ④GUI 文字列を ja/en 両方に対訳追加。
- 一時ファイルは `.claude/tmp/` 以下に置く。

## Kuntraykun 連携（実装済み）

本アプリは kuntraykun（`com.mtkg.kuntraykun`）にメニューバーアイコンを集約させる連携に対応している。
- **MenuBarExtra からの作り替え**: `MenuBarExtra` はメニューを座標指定で `popUp` する公開 API が無く、
  kuntraykun の `showMenu`（指定座標にメニューを出す）に応えられない。そのため、メニューバーを
  AppKit の `NSStatusItem` + `NSMenu` に作り替えた（`Sources/whisperkun/App/AppDelegate.swift`、
  `@NSApplicationDelegateAdaptor` で接続）。設定画面は SwiftUI の `Settings` シーンのまま
  （メニューの「設定…」は `showSettingsWindow:` で開く）。`AppState` は `AppDelegate` が保持して SwiftUI に渡す。
- **連携本体**: `Sources/whisperkun/App/KuntraykunBridge.swift`。分散通知 `sync`/`showMenu` を観測し、
  起動時に `appLaunched` を送信。管理対象 かつ kuntraykun 起動中なら自分のアイコンを隠し、`showMenu` で
  自分のメニューを指定座標に `popUp` する（未起動ならフォールバック表示）。
- 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`、共通方針は `../CLAUDE_base.md`「Kuntraykun 連携」。
- 管理対象フラグは `UserDefaults`（キー `KuntraykunManaged`）に永続化する。
- **実アイコンのライブ書き出し（v2）**: `KuntraykunIconExport.export(_:)`（`Sources/whisperkun/App/KuntraykunIconExport.swift`）で、
  `AppDelegate` がメニューバーアイコンを設定する箇所で現在アイコンを
  `~/Library/Application Support/Kuntraykun/MenuBarIcons/<基底ID>.png` に書き出す（テンプレートは `.template` マーカー併記）。
  kuntraykun はこれを優先して一覧に表示する。赤バッジは別 view なので書き出し対象外。
