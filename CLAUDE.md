# CLAUDE.md — whisperkun

このリポジトリで作業する際のガイド。

**メニューバー常駐アプリ（kun シリーズ）共通の方針は上位ディレクトリの [`../CLAUDE_base.md`](../CLAUDE_base.md) を参照**
（Swift Package 構成・アップデート・ログイン項目・kunkit 連携・リリース手順（`make release-tag`）・
署名/公証・ブランチ運用・開発の進め方など）。共通方針を変えるときは `CLAUDE_base.md`
（[kun-template](https://github.com/m-tkg/kun-template) が canonical）を編集する。
本ファイルには whisperkun 固有の事項のみを記す。

---

# whisperkun 固有事項

## 概要

whisperkun は macOS のメニューバー常駐型ディクテーションアプリ。ホットキーで録音し、
オンデバイスで文字起こし → 辞書置換 → AI整形 → 前面アプリへ自動入力する。
詳細は [README.md](README.md)、署名/公証は [docs/SIGNING.md](docs/SIGNING.md) を参照。

- Swift 6.0 / macOS 26.0 / Swift Package Manager（XcodeGen は使わない）
- バンドルID: `com.mtkg.whisperkun`（ローカル検証ビルドは `com.mtkg.whisperkun.local`）。
  `Info.plist` の `CFBundleIdentifier`、`Scripts/bundle.sh` で一貫させる。ログの subsystem は
  `Support/Log.swift` に一元化されており（`Log.logger(category:)` を使う）、`Logger(subsystem:)` を直書きしない。
  `.local` の基底ID判定は kunkit `KunSupport` の `BundleIdentity` を使う（旧 `whisperkunCore` 版から移設）。

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

- **whisperkunCore**: `DictionaryService`（単語単位置換）、`DictionaryRule` など純ロジック。
- **whisperkun**（実行ファイル）: `App/`（`WhisperkunApp` / `AppState`）、`Pipeline/DictationCoordinator`、
  `Services/`（Transcription / AI / TextInsertion / Hotkey / Permissions / LaunchAtLogin / SettingsStore /
  BufferConverter / Update）、`UI/`（MenuBarView / RecordingHUD / OnboardingView /
  ActivationPolicyController / Settings）。
- `AppState`（`@MainActor @Observable`）がルート状態で、SwiftData（`DictionaryEntry` / `TranscriptionRecord`）と
  各サービスを束ねる。後処理は `DictationCoordinator.process`: **辞書置換 → AI整形** の順。

### kunkit 由来の共通実装（複製を持たない）

kun シリーズ共通の実装は共有ライブラリ [kunkit](https://github.com/m-tkg/kunkit)（SPM 依存）を参照し、アプリ内に複製を置かない。
- `KunSupport`: `BundleIdentity`（`.local` 基底ID判定・`isLocalBuild`）。
- `KunUpdateKit`: `ReleaseInfo` / `VersionComparator`、`GitHubReleaseFetcher`（ETag 条件付き取得）、
  `ReleaseDownloader`（zip DL）、`KunUpdateSchedule`（チェック間隔6時間）。
- `KunAppKit`: `SelfUpdater`（zip DL→`ditto` 展開→基底ID検証→切り離しスクリプトで入替・再起動）、
  `KunAppLaunch`（多重起動ガード）。
- `KunIntegrationBridge`: kuntraykun 連携（後述）。
- **据え置き**（whisperkun 固有のまま）: 自動起動 `LaunchAtLoginService`（SwiftUI 設定と直結の enum static。
  kunkit `LoginItemController` は ObservableObject で API 形状が異なり載せ替えは UI 改修を伴うため）と
  設定永続化 `SettingsStore`（`@Observable`＋UserDefaults キー個別・移行付きで、kunkit `KunSettingsStore` の
  単一 JSON 方式とは設計が異なるため）。

base 必須チェックリストの実装対応（実装済み）:

- **多重起動防止**: `AppState.init` で kunkit `KunAppLaunch.terminateIfAlreadyRunning()` を呼び、
  同 bundle ID の他インスタンスを前面化して `exit(0)`。
- **自動起動（ログイン項目）**: `LaunchAtLoginService` が `SMAppService.mainApp` を register/unregister。
  **状態はシステム側が source of truth**（`Settings`/JSON に持たず、表示時に読み直す）。トグルは即時反映。
- **設定ダイアログ**: SwiftUI の `Settings` シーンを `TabView` で機能ごとに分割（一般/権限/ホットキー/辞書/履歴）。
  「一般」タブは左端。表示中は `ActivationPolicyController` が `.regular`、全クローズで `.accessory` に戻す。
- **メニュー先頭のバージョン**: `MenuBarView` 先頭に `whisperkun <version>`。ローカルビルドは
  `WhisperkunApp.isLocalBuild`（bundle ID が `.local` 終端か）でアイコンに「ローカル」を併記。
- **自己更新**: `UpdateService`（公開 GitHub API から最新リリースを取得＝kunkit `GitHubReleaseFetcher` の
  ETag 条件付き取得）＋ kunkit `KunAppKit` の `SelfUpdater(appName: "whisperkun")`（zip を `ReleaseDownloader`＝
  URLSession で DL → `ditto` 展開 → **基底ID（`.local` 除去）で bundle ID 検証** → 切り離しスクリプトで入替・再起動）。
  基底ID比較によりローカルビルドからも本番リリースへ更新できる。
- **定期監視＋スリープ復帰チェック**: `UpdateCoordinator`（`AppState.updates`。init の `start()` で配線）が起動時1回に加え
  `Timer.scheduledTimer`（間隔 **6時間**・`tolerance` 10%＝kunkit `KunUpdateSchedule`）で定期サイレントチェックし、
  `Timer` がスリープ中に発火しないため `NSWorkspace.didWakeNotification` で**復帰時にも即チェック**する。間隔は未認証
  GitHub API のレート制限 **60回/時** に十分収まる値。タイマー/通知ブロックは非隔離なので `MainActor.assumeIsolated` で
  `startUpdateCheck(interactive:)` を呼ぶ。
- **メニューバーの赤バッジ**: 新版があるとアイコン右下に赤丸（最新なら消す）。更新有無は
  `UpdateCoordinator.setAvailableRelease(_:)`（base の `setUpdateAvailable`/`clearUpdateAvailable` 相当）に**集約**し、
  `onUpdateAvailabilityChanged` クロージャで `StatusItemController` のバッジと同期する（起動時・定期・復帰・手動の全経路が
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

## リリース・開発の固有メモ

共通のリリース手順・ブランチ運用・TDD 方針は `../CLAUDE_base.md` を参照。whisperkun 固有:
- **CI ランナーは `runs-on: macos-26`**（FoundationModels / Speech の macOS 26 専用 API を使うため）。
- 署名/公証の詳細は [docs/SIGNING.md](docs/SIGNING.md)。Secrets 登録は
  `~/git/github.com/m-tkg/setup-release-secrets.sh -r m-tkg/whisperkun`。
- テスト: 純粋ロジック（`whisperkunCore`）は TDD。UI / AX / 録音まわりは実機で手動確認。
  `.menu` 形式のメニューはネイティブ項目なので System Events で自動確認できる。

## Kuntraykun 連携（実装済み・kunkit 利用）

本アプリは kuntraykun（`com.mtkg.kuntraykun`）にメニューバーアイコンを集約させる連携（v1〜v4:
アイコン集約・実アイコン書き出し・アップデート集約・サブメニュー表示）に対応している。
- **実装は共有ライブラリ [kunkit](https://github.com/m-tkg/kunkit)**（SPM 依存、`KunIntegrationBridge` プロダクト）。
  `KuntraykunBridge` / `KuntraykunIconExport` / `KuntraykunMenuExport` を提供し、アプリ側に連携ロジックの複製は持たない。
- **MenuBarExtra からの作り替え**: `MenuBarExtra` はメニューを座標指定で `popUp` する公開 API が無く、
  kuntraykun の `showMenu`（指定座標にメニューを出す）に応えられない。そのため、メニューバーを
  AppKit の `NSStatusItem` + `NSMenu` に作り替えた（`Sources/whisperkun/App/AppDelegate.swift`、
  `@NSApplicationDelegateAdaptor` で接続）。`AppState` は `AppDelegate` が保持して SwiftUI に渡す。
- 配線: `StatusItemController.makeKuntraykunBridge(menu:)`（`KuntraykunBridge(statusItem:menu:)` の標準配線。
  メニューは `AppDelegate` が所有するため引数で渡す）を `AppDelegate` が `bridge.start()` する。
  start() が観測開始・`appLaunched` 送信・初回メニュー書き出しまで行う。
  アイコン書き出し（v2）は `StatusItemController.applyIcon()` の `KuntraykunIconExport.export(_:)`、
  アップデート報告（v3）は `kuntraykunBridge?.reportUpdate(_:)`、
  メニュー文言の変化（v4、`onUpdateAvailabilityChanged`）は `bridge.exportMenuSnapshot()`。
- 本アプリのメニューは開くたびに `menuNeedsUpdate` で同期再構築するため「表示（トラッキング）中の
  スナップショット書き出しは開いているメニューを壊す」点に注意が要るが、kunkit の Bridge が
  トラッキング通知の観測で自動的に保留し、閉じたあとに書き出す（アプリ側の保留処理は不要）。
- kuntraykun のサブメニューから実行される項目のうちウィンドウを開くものは、各アクション側が
  前面化（`NSApp.activate`）を行う（`HostedWindowController` / `DiagnosticsExporter`）。
- 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`、共通方針は `../CLAUDE_base.md`「Kuntraykun 連携」。
- 管理対象フラグは kunkit が `UserDefaults`（キー `KuntraykunManaged`）に永続化する。
