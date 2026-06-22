import AppKit
import SwiftUI

/// メニューバー常駐（LSUIElement / `.accessory`）アプリで、特定のウィンドウ表示中だけ
/// Dock 表示と前面化を可能にするための activation policy 切り替え。
///
/// アクセサリアプリは通常 active になれず、ウィンドウが前面に出ない・Dock にも出ない。
/// オンボーディングや設定ウィンドウの表示中だけ `.regular` にし、閉じたら `.accessory`
/// へ戻す。複数ウィンドウに備えて表示数を参照カウントする。
@MainActor
final class ActivationPolicyController {
    static let shared = ActivationPolicyController()
    private var count = 0
    private init() {}

    /// 前面表示が必要なウィンドウが現れたとき。Dock に出し、アプリを前面化する。
    func beginForegroundWindow() {
        count += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 前面ウィンドウが閉じたとき。最後の1枚なら `.accessory` に戻す（Dock から消す）。
    func endForegroundWindow() {
        count = max(0, count - 1)
        if count == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// ウィンドウに載っている間だけ `ActivationPolicyController` を介して Dock 表示＋前面化する
/// 不可視の AppKit ビュー。SwiftUI の `.background(ForegroundActivation())` で使う。
///
/// 設定ウィンドウは SwiftUI が使い回す（閉じても破棄されず再表示される）ため、
/// `viewDidMoveToWindow` は再オープン時に発火しないことがある。`didBecomeKey` も監視して
/// 再オープンにも追従する。また、メニューバーのポップオーバー閉鎖や policy 切替の直後に
/// 前面化が打ち消されないよう、前面化は次の run loop で行う。
private final class ForegroundActivationView: NSView {
    private var active = false
    private weak var observed: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            // ウィンドウから外れた（閉じた）。
            deactivate()
            return
        }
        observe(window)
        activate(window)
    }

    private func observe(_ window: NSWindow) {
        guard observed !== window else { return }
        if let observed {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: observed)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: observed)
        }
        observed = window
        NotificationCenter.default.addObserver(self, selector: #selector(handleClose),
                                               name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBecomeKey),
                                               name: NSWindow.didBecomeKeyNotification, object: window)
    }

    /// 再オープン等でウィンドウがキーになったら policy を保証する。
    @objc private func handleBecomeKey() {
        if let observed { activate(observed) }
    }

    private func activate(_ window: NSWindow) {
        if !active {
            active = true
            ActivationPolicyController.shared.beginForegroundWindow()
        }
        // policy 切替やポップオーバー閉鎖の直後に確実に前面へ出すため次の run loop で実行する。
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func handleClose() {
        deactivate()
    }

    private func deactivate() {
        guard active else { return }
        active = false
        ActivationPolicyController.shared.endForegroundWindow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// 表示されている間だけアプリを前面化し Dock に表示する SwiftUI ヘルパ。
/// オンボーディング/設定など「前に出てほしいウィンドウ」のビューに `.background()` で付ける。
struct ForegroundActivation: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ForegroundActivationView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
