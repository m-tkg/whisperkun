import AppKit
import SwiftUI

/// メニューバーのドロップダウン（ネイティブメニュー形式）。
/// 項目は通常のメニュー文字で、設定への導線・バージョン表示・終了のみ。
struct MenuBarView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("whisperkun \(appVersion)")

        Divider()

        // SettingsLink は背面の設定ウィンドウを前面化しないため、明示的に
        // アプリをアクティブ化してから設定を開く（メニューバー常駐＝accessory 対策）。
        Button("設定…") { openSettingsAndActivate() }
            .keyboardShortcut(",")
        Button(updateMenuTitle) { appState.checkForUpdates() }
            .disabled(appState.isUpdating)

        Divider()

        Button("whisperkun を終了") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// 新バージョンがあればインストール、なければ確認のラベル。
    private var updateMenuTitle: String {
        if let release = appState.availableRelease {
            return String(localized: "アップデート \(release.tagName) をインストール…")
        }
        return String(localized: "アップデートを確認")
    }

    private func openSettingsAndActivate() {
        openSettings()
        bringSettingsToFront()
        // 新規ウィンドウ生成や policy 切替・メニュー閉じの直後にも効くよう念押し。
        Task { @MainActor in bringSettingsToFront() }
    }

    private func bringSettingsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindow() {
            window.makeKeyAndOrderFront(nil)
            // 背面の既存ウィンドウを他アプリより前へ確実に出す。
            window.orderFrontRegardless()
        }
    }

    /// 設定ウィンドウを探す（オンボーディング以外の可視な通常ウィンドウ）。
    /// オンボーディングは identifier で除外する（タイトルはローカライズで変わるため）。
    private func settingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.isVisible
                && window.styleMask.contains(.titled)
                && window.identifier?.rawValue != "onboarding"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}
