import AppKit
import SwiftUI

@main
struct WhisperkunApp: App {
    /// メニューバー（NSStatusItem）と AppState を保持する AppKit デリゲート。
    /// kuntraykun 連携（メニューの座標指定 popUp）に AppKit が必要なため、
    /// SwiftUI の MenuBarExtra ではなくここでメニューバーを構築する。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 設定ウィンドウは AppDelegate が SettingsView を自前 NSWindow にホストして開く
        // （accessory + AppKit メニュー構成では SwiftUI の Settings シーンが showSettingsWindow: で
        // 開けないため）。SwiftUI App はシーンを最低1つ要求するので、空の Settings シーンだけ置く。
        Settings {
            EmptyView()
        }
    }
}
