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
private final class ForegroundActivationView: NSView {
    private var active = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, !active {
            active = true
            ActivationPolicyController.shared.beginForegroundWindow()
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleClose),
                name: NSWindow.willCloseNotification, object: window
            )
        } else if window == nil, active {
            // ウィンドウから外れた（閉じた）。
            deactivate()
        }
    }

    @objc private func handleClose() {
        deactivate()
    }

    private func deactivate() {
        guard active else { return }
        active = false
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        ActivationPolicyController.shared.endForegroundWindow()
    }
}

/// 表示されている間だけアプリを前面化し Dock に表示する SwiftUI ヘルパ。
/// オンボーディング/設定など「前に出てほしいウィンドウ」のビューに `.background()` で付ける。
struct ForegroundActivation: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ForegroundActivationView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
