import AppKit
import SwiftUI
import whisperkunCore

/// メニューバー常駐の入口（AppKit）。
///
/// kuntraykun 連携（メニューを指定座標へ popUp する）には AppKit の `NSStatusItem` + `NSMenu` が必要なため、
/// SwiftUI の `MenuBarExtra` ではなくここでメニューバーを構築する。ステータスアイテム自体（アイコン/バッジ）は
/// `StatusItemController` が管理し、ここはライフサイクルとメニュー構築・アクションを担う。
/// アプリ全体の状態 `AppState` はここで生成し、SwiftUI シーンへ渡す。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// アプリ全体のルート状態（SwiftUI の Settings シーンにも渡す）。
    let appState = AppState()

    private var statusItemController: StatusItemController!
    private let menu = NSMenu()
    private var kuntraykunBridge: KuntraykunBridge?
    /// 設定ウィンドウ（SwiftUI の SettingsView を自前 NSWindow にホスト）。
    private let settingsWindowController = SettingsWindowController()

    /// ローカル検証ビルド（バンドルID が `.local`）かどうか。
    private var isLocalBuild: Bool {
        BundleIdentity.isLocal(Bundle.main.bundleIdentifier)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItemController = StatusItemController()
        self.statusItemController = statusItemController
        menu.delegate = self
        statusItemController.menu = menu

        // 新版があるときの赤バッジを UpdateCoordinator の更新有無と同期させる。
        appState.updates.onUpdateAvailabilityChanged = { [weak self] available in
            self?.statusItemController.setBadgeVisible(available)
            // kuntraykun にもアップデート有無を伝える（集約バッジ/赤丸用）。
            self?.kuntraykunBridge?.reportUpdate(available)
            // アップデート項目の文言が変わるので、kuntraykun 用スナップショットも書き出し直す（連携 v4）。
            self?.exportMenuSnapshot()
        }
        // 起動時チェックが既に完了している場合に取りこぼさないよう初期同期する。
        appState.updates.onUpdateAvailabilityChanged?(appState.updates.availableRelease != nil)

        // kuntraykun 連携: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        // v4: メニュー構造を共有してサブメニュー表示・項目実行にも応じる。
        let bridge = KuntraykunBridge(
            setHidden: { [weak self] hidden in self?.statusItemController.setHidden(hidden) },
            popUpMenu: { [weak self] point in self?.statusItemController.popUpMenu(at: point) },
            exportMenu: { [weak self] in self?.exportMenuSnapshot() },
            performMenuItem: { [weak self] id in self?.performMenuItem(id: id) ?? false }
        )
        bridge.start()
        kuntraykunBridge = bridge
        // bridge 生成前に確定していた更新状態を改めて報告する。
        bridge.reportUpdate(appState.updates.availableRelease != nil)
        // 起動時に現在のメニュー構造を書き出しておく（kuntraykun 起動済みでもすぐサブメニューが出せる）。
        exportMenuSnapshot()
    }

    /// 再アクティブ化時にアイコンを貼り直す。万一フォールバック（mic.fill）になっていても、
    /// `MenuBarIcon` が読めれば本来のアイコンへ自己修復する（自己更新の再起動直後対策）。
    func applicationDidBecomeActive(_ notification: Notification) {
        statusItemController.applyIcon()
    }

    // MARK: - メニュー（開くたびに再構築し、アップデート文言を最新化する）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var versionTitle = "whisperkun \(AppInfo.version)"
        if isLocalBuild { versionTitle += " (\(String(localized: "ローカル")))" }
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: String(localized: "設定…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = !appState.updates.isUpdating
        menu.addItem(updateItem)

        let diagnosticsItem = NSMenuItem(title: String(localized: "診断ログを書き出す…"), action: #selector(exportDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "whisperkun を終了"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - kuntraykun 連携 v4（メニュースナップショット）

    /// メニュー構造を kuntraykun 用の共有場所へ書き出す（連携 v4）。
    /// `export(_:)` が `menu.update()` → `menuNeedsUpdate` を同期的に呼ぶため、
    /// 開くたびに再構築するこのメニューでも呼んだ時点の最新内容が書き出される。
    /// 起動時・requestMenu 受信時・メニュー文言が変わる箇所（アップデート有無の変化）から呼ぶ。
    private func exportMenuSnapshot() {
        KuntraykunMenuExport.export(menu)
    }

    /// kuntraykun のサブメニューでクリックされた項目（インデックスパス ID）を実行する（連携 v4）。
    /// 各項目の target は self なのでレスポンダチェーンに依存せず実行できる。
    /// ウィンドウを開く項目（設定… / 診断ログ…）は各アクション側が前面化（activate）を行う。
    private func performMenuItem(id: String) -> Bool {
        KuntraykunMenuExport.performItem(id: id, in: menu)
    }

    /// 新バージョンがあればインストール、なければ確認のラベル。
    private var updateTitle: String {
        if let release = appState.updates.availableRelease {
            return String(localized: "アップデート \(release.tagName) をインストール…")
        }
        return String(localized: "アップデートを確認")
    }

    // MARK: - アクション

    /// SwiftUI の Settings シーンを開く（メニューバー常駐＝accessory のため前面化も行う）。
    @objc private func openSettings() {
        // SwiftUI の Settings シーンは accessory + AppKit メニュー構成では showSettingsWindow: で
        // 開けない（true を返すが窓を生成しない）ため、SettingsView を自前の NSWindow にホストする。
        settingsWindowController.show(appState)
    }

    @objc private func checkForUpdates() {
        appState.updates.checkForUpdates()
    }

    @objc private func exportDiagnostics() {
        DiagnosticsExporter.export()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
