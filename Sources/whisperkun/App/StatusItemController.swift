import AppKit
import KunIntegrationBridge
import KunSupport
import whisperkunCore

private let logger = Log.logger(category: "StatusItem")

/// メニューバーの `NSStatusItem` を管理する: アイコンの適用と自己修復、
/// ローカルビルドの「ローカル」併記、赤バッジのオーバーレイ、kuntraykun 向けアイコン書き出し。
/// メニューの構築・アクションは `AppDelegate` が担う。
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    /// 新版があるとき右下に出す赤バッジ（更新有無は UpdateCoordinator が集約して同期する）。
    private var updateBadgeView: NSView?

    /// メニューバーアイコンの一辺（pt）。バッジ位置の基準に使う。
    private static let iconWidth: CGFloat = 18
    /// 赤バッジの直径（pt）。
    private static let badgeSize: CGFloat = 7

    /// ステータスアイテムに表示するメニュー。
    var menu: NSMenu? {
        get { statusItem.menu }
        set { statusItem.menu = newValue }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button, BundleIdentity.isLocal(Bundle.main.bundleIdentifier) {
            // ローカルビルドは「ローカル」を併記して本番と区別する。
            button.title = " ローカル"
            button.imagePosition = .imageLeading
        }
        applyIcon()
        installUpdateBadge()
    }

    /// ステータスアイコンを（再）設定し、kuntraykun 用にも書き出す。起動時・再アクティブ化時に呼ぶ。
    /// 万一フォールバック（mic.fill）になっていても、`MenuBarIcon` が読めれば本来のアイコンへ
    /// 自己修復する（自己更新の再起動直後対策）。
    func applyIcon() {
        guard let button = statusItem.button else { return }
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

    /// 赤バッジの表示/非表示（新版の有無）。
    func setBadgeVisible(_ visible: Bool) {
        updateBadgeView?.isHidden = !visible
    }

    /// kuntraykun 連携ブリッジを標準配線で生成する（アイコンの隠し/popUp/メニュー書き出し/項目実行/
    /// 表示中の書き出し保留は kunkit 側の既定実装。`NSStatusItem` は破棄せず保持し isVisible で隠す）。
    /// メニューの構築・アクションは `AppDelegate` が担うため、メニューは引数で受け取る。
    func makeKuntraykunBridge(menu: NSMenu) -> KuntraykunBridge {
        KuntraykunBridge(statusItem: statusItem, menu: menu)
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
