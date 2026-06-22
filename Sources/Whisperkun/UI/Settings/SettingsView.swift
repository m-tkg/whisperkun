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

            SnippetsSettingsView()
                .tabItem { Label("スニペット", systemImage: "text.badge.plus") }

            WorkflowsSettingsView()
                .tabItem { Label("ワークフロー", systemImage: "flowchart") }

            HistoryView()
                .tabItem { Label("履歴", systemImage: "clock") }
        }
        .frame(width: 560, height: 420)
    }
}
