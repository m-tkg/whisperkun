import AppKit
import SwiftUI

@main
struct WhisperkunApp: App {
    @State private var appState = AppState()

    /// ローカル検証ビルド（バンドルID が `.local`）かどうか。
    private var isLocalBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".local")
    }

    /// メニューバー用アイコン（アプリアイコンと同じ画像）。バンドルに無ければ nil。
    /// テンプレート画像にして、メニューバーの明暗に追従し白黒反転表示する
    /// （明るいメニューバーでは黒、暗いメニューバーでは白）。
    private static let menuBarImage: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .modelContainer(appState.modelContainer)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: appState)
                .modelContainer(appState.modelContainer)
        }
    }

    /// メニューバーに表示するラベル。アプリアイコンと同じ画像を使い、
    /// ローカルビルドは「ローカル」を併記して本番と区別する。
    @ViewBuilder
    private var menuBarLabel: some View {
        if let image = Self.menuBarImage {
            // テンプレートとして描画し、メニューバーの明暗に追従させる（白黒反転）。
            let icon = Image(nsImage: image).renderingMode(.template)
            if isLocalBuild {
                HStack(spacing: 3) { icon; Text("ローカル") }
            } else {
                icon
            }
        } else {
            // 画像が無い環境（swift run 等）はシステムアイコンにフォールバック。
            if isLocalBuild {
                Label("ローカル", systemImage: "mic.fill")
            } else {
                Image(systemName: "mic.fill")
            }
        }
    }
}
