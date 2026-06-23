import SwiftUI

/// メニューバーのドロップダウン（ネイティブメニュー形式）。
/// 項目は通常のメニュー文字で、設定への導線・バージョン表示・終了のみ。
struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        Text("Whisperkun \(appVersion)")

        Divider()

        SettingsLink { Text("設定…") }
            .keyboardShortcut(",")
        Button("Whisperkun を終了") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
