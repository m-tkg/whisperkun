import AppKit
import SwiftUI

/// 初回起動時に3つの権限付与を案内するオンボーディング。
struct OnboardingView: View {
    @Bindable var appState: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Whisperkun へようこそ")
                    .font(.title2.bold())
                Text("音声入力を使うには、次の3つの権限が必要です。")
                    .foregroundStyle(.secondary)
            }

            step(
                number: 1,
                title: "マイク",
                detail: "音声を取り込みます。",
                granted: appState.permissions.microphone == .granted,
                action: { Task { await appState.permissions.requestMicrophone() } }
            )
            step(
                number: 2,
                title: "音声認識",
                detail: "オンデバイスで文字起こしします。",
                granted: appState.permissions.speechRecognition == .granted,
                action: { Task { await appState.permissions.requestSpeechRecognition() } }
            )
            step(
                number: 3,
                title: "アクセシビリティ",
                detail: "他アプリへの貼り付けとホットキーに使います。システム設定で許可後、「再確認」を押してください。",
                granted: appState.permissions.accessibilityGranted,
                action: {
                    appState.permissions.requestAccessibility()
                    appState.ensureHotkeyInstalled()
                }
            )

            HStack {
                Button("再確認") { appState.ensureHotkeyInstalled() }
                Spacer()
                Button(appState.permissions.allGranted ? "始める" : "あとで") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460, height: 380)
    }

    @ViewBuilder
    private func step(number: Int, title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("許可", action: action)
            }
        }
    }
}

/// オンボーディングウィンドウ（NSWindow）を管理する。
@MainActor
final class OnboardingController {
    private var window: NSWindow?

    /// 権限が未充足なら表示する。
    func showIfNeeded(_ appState: AppState) {
        guard !appState.permissions.allGranted else { return }
        show(appState)
    }

    func show(_ appState: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: OnboardingView(appState: appState) { [weak self] in
            self?.close()
        })
        // SwiftUIビューにウィンドウサイズを追従させない（制約更新ループの回避）。
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "はじめに"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 380))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func close() {
        window?.close()
        window = nil
    }
}
