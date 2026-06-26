import AppKit
import SwiftUI

@main
struct WhisperkunApp: App {
    /// メニューバー（NSStatusItem）と AppState を保持する AppKit デリゲート。
    /// kuntraykun 連携（メニューの座標指定 popUp）に AppKit が必要なため、
    /// SwiftUI の MenuBarExtra ではなくここでメニューバーを構築する。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 設定画面は SwiftUI の Settings シーン（メニューの「設定…」が showSettingsWindow: で開く）。
        Settings {
            SettingsView(appState: appDelegate.appState)
                .modelContainer(appDelegate.appState.modelContainer)
        }
    }
}
