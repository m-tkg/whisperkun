import AppKit
import SwiftUI

/// 設定ウィンドウ（NSWindow）を管理する。
///
/// SwiftUI の `Settings` シーンは、メニューバー常駐（accessory）＋ AppKit メニュー（NSStatusItem）構成だと
/// `showSettingsWindow:` で開けない（アクションは true を返すが窓を生成しない）。そのため OnboardingController と
/// 同様に `SettingsView` を自前の `NSWindow` にホストする。前面化/Dock 表示は `ForegroundActivation` が担う。
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    /// 設定ウィンドウを表示（生成済みなら再利用して前面化）する。
    func show(_ appState: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView(appState: appState)
                .modelContainer(appState.modelContainer)
        )
        // SwiftUIビューにウィンドウサイズを追従させない（制約更新ループの回避）。
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "設定")
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 420))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

/// 設定ウィンドウのルート。タブで各設定をまとめる。
struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem { Label("一般", systemImage: "gearshape") }

            HotkeySettingsView(appState: appState)
                .tabItem { Label("ホットキー", systemImage: "keyboard") }

            DictionarySettingsView()
                .tabItem { Label("辞書", systemImage: "character.book.closed") }

            HistoryView()
                .tabItem { Label("履歴", systemImage: "clock") }

            PermissionsSettingsView(appState: appState)
                .tabItem { Label("権限", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 420)
        // 設定ウィンドウ表示中だけ前面化＋Dock表示する。
        .background(ForegroundActivation())
    }
}
