import SwiftUI

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
