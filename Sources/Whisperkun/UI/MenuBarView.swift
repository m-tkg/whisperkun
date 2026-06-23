import SwiftUI

/// メニューバーのドロップダウン。設定への導線と終了のみ。
/// 録音操作・ライブ表示は HUD、権限/AI整形/アップデートは設定ウィンドウへ集約する。
struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Whisperkun")
                .font(.headline)

            Divider()

            SettingsLink { Text("設定…") }
                .keyboardShortcut(",")
            Button("Whisperkun を終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 220)
    }
}
