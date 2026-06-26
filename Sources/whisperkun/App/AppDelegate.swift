import AppKit
import SwiftUI

/// メニューバー常駐の入口（AppKit）。
///
/// kuntraykun 連携（メニューを指定座標へ popUp する）には AppKit の `NSStatusItem` + `NSMenu` が必要なため、
/// SwiftUI の `MenuBarExtra` ではなくここでメニューバーを構築する。設定画面は SwiftUI の `Settings` シーンを
/// `showSettingsWindow:` で開く。アプリ全体の状態 `AppState` はここで生成し、SwiftUI シーンへ渡す。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// アプリ全体のルート状態（SwiftUI の Settings シーンにも渡す）。
    let appState = AppState()

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var kuntraykunBridge: KuntraykunBridge?

    /// ローカル検証ビルド（バンドルID が `.local`）かどうか。
    private var isLocalBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".local")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = Self.menuBarImage() {
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "whisperkun")
            }
            // ローカルビルドは「ローカル」を併記して本番と区別する。
            if isLocalBuild {
                button.title = " ローカル"
                button.imagePosition = .imageLeading
            }
        }
        menu.delegate = self
        statusItem.menu = menu

        // kuntraykun 連携: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        let bridge = KuntraykunBridge(
            setHidden: { [weak self] hidden in self?.statusItem.isVisible = !hidden },
            popUpMenu: { [weak self] point in self?.statusItem.menu?.popUp(positioning: nil, at: point, in: nil) }
        )
        bridge.start()
        kuntraykunBridge = bridge
    }

    // MARK: - メニュー（開くたびに再構築し、アップデート文言を最新化する）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var versionTitle = "whisperkun \(appVersion)"
        if isLocalBuild { versionTitle += " (ローカル)" }
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = !appState.isUpdating
        menu.addItem(updateItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "whisperkun を終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// 新バージョンがあればインストール、なければ確認のラベル。
    private var updateTitle: String {
        if let release = appState.availableRelease {
            return "アップデート \(release.tagName) をインストール…"
        }
        return "アップデートを確認"
    }

    // MARK: - アクション

    /// SwiftUI の Settings シーンを開く（メニューバー常駐＝accessory のため前面化も行う）。
    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        appState.checkForUpdates()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// メニューバー用テンプレート画像（アプリアイコンと同じ MenuBarIcon）。無ければ nil。
    private static func menuBarImage() -> NSImage? {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
