import AppKit
import OSLog
import SwiftUI
import whisperkunCore

private let logger = Log.logger(category: "AppDelegate")

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
    /// 設定ウィンドウ（SwiftUI の SettingsView を自前 NSWindow にホスト）。
    private let settingsWindowController = SettingsWindowController()
    /// 新版があるとき右下に出す赤バッジ（更新有無は AppState が集約して同期する）。
    private var updateBadgeView: NSView?

    /// メニューバーアイコンの一辺（pt）。バッジ位置の基準に使う。
    private static let iconWidth: CGFloat = 18
    /// 赤バッジの直径（pt）。
    private static let badgeSize: CGFloat = 7

    /// ローカル検証ビルド（バンドルID が `.local`）かどうか。
    private var isLocalBuild: Bool {
        BundleIdentity.isLocal(Bundle.main.bundleIdentifier)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button, isLocalBuild {
            // ローカルビルドは「ローカル」を併記して本番と区別する。
            button.title = " ローカル"
            button.imagePosition = .imageLeading
        }
        applyStatusItemIcon()
        menu.delegate = self
        statusItem.menu = menu

        // 新版があるとき表示する赤バッジをボタンにオーバーレイし、AppState の更新有無と同期させる。
        installUpdateBadge()
        appState.onUpdateAvailabilityChanged = { [weak self] available in
            self?.updateBadgeView?.isHidden = !available
            // kuntraykun にもアップデート有無を伝える（集約バッジ/赤丸用）。
            self?.kuntraykunBridge?.reportUpdate(available)
        }
        // 起動時チェックが既に完了している場合に取りこぼさないよう初期同期する。
        appState.onUpdateAvailabilityChanged?(appState.availableRelease != nil)

        // kuntraykun 連携: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        let bridge = KuntraykunBridge(
            setHidden: { [weak self] hidden in self?.statusItem.isVisible = !hidden },
            popUpMenu: { [weak self] point in self?.statusItem.menu?.popUp(positioning: nil, at: point, in: nil) }
        )
        bridge.start()
        kuntraykunBridge = bridge
        // bridge 生成前に確定していた更新状態を改めて報告する。
        bridge.reportUpdate(appState.availableRelease != nil)
    }

    /// 再アクティブ化時にアイコンを貼り直す。万一フォールバック（mic.fill）になっていても、
    /// `MenuBarIcon` が読めれば本来のアイコンへ自己修復する（自己更新の再起動直後対策）。
    func applicationDidBecomeActive(_ notification: Notification) {
        applyStatusItemIcon()
    }

    /// ステータスアイコンを（再）設定し、kuntraykun 用にも書き出す。起動時・再アクティブ化時に呼ぶ。
    private func applyStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        if let image = Self.menuBarImage() {
            button.image = image
        } else if button.image == nil {
            // 本来あり得ない（Resources に MenuBarIcon.png が無い）。原因切り分け用にログを残す。
            logger.error("MenuBarIcon をバンドルから読み込めませんでした。mic.fill にフォールバックします。")
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "whisperkun")
        }
        // kuntraykun 一覧用に、現在のメニューバーアイコンを共有場所へ書き出す（連携 v2）。
        KuntraykunIconExport.export(button.image)
    }

    /// 赤バッジ view をボタンに重ね、アイコン幅基準で右下に Auto Layout 固定する。
    /// 位置は trailing 基準ではなく**アイコン画像の幅基準**にすることで、「ローカル」テキスト併記時
    /// （`imagePosition = .imageLeading`）でも常にアイコングリフの右下に乗る。
    private func installUpdateBadge() {
        guard let button = statusItem.button else { return }
        let badge = UpdateBadgeView(frame: .zero)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Self.badgeSize),
            badge.heightAnchor.constraint(equalToConstant: Self.badgeSize),
            badge.leadingAnchor.constraint(equalTo: button.leadingAnchor,
                                           constant: Self.iconWidth - Self.badgeSize),
            badge.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        updateBadgeView = badge
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
        updateItem.isEnabled = !appState.isUpdating
        menu.addItem(updateItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "whisperkun を終了"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// 新バージョンがあればインストール、なければ確認のラベル。
    private var updateTitle: String {
        if let release = appState.availableRelease {
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
        appState.checkForUpdates()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// メニューバー用テンプレート画像（アプリアイコンと同じ MenuBarIcon）。無ければ nil。
    ///
    /// `NSImage(named:)` は名前キャッシュ／アセット解決に依存し、自己更新による再起動直後など
    /// 稀に nil を返して mic.fill フォールバックに化けることがある。Resources の URL から
    /// 直接読み込むことで決定的にする（ファイルが在れば必ず読める）。
    private static func menuBarImage() -> NSImage? {
        let image: NSImage?
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png") {
            image = NSImage(contentsOf: url)
        } else {
            image = NSImage(named: "MenuBarIcon")
        }
        guard let image else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
