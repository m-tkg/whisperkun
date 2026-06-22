import SwiftUI

/// メニューバーのドロップダウン内容。M1では権限状態の表示と要求のみ。
struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Whisperkun")
                .font(.headline)

            Divider()

            permissionRow(
                title: "マイク",
                state: appState.permissions.microphone,
                action: { Task { await appState.permissions.requestMicrophone() } }
            )
            permissionRow(
                title: "音声認識",
                state: appState.permissions.speechRecognition,
                action: { Task { await appState.permissions.requestSpeechRecognition() } }
            )
            accessibilityRow

            Divider()

            recordingSection

            Divider()

            if !appState.permissions.allGranted {
                Button("はじめに（権限を設定）") { appState.showOnboarding() }
            }
            Button("権限の状態を再確認") { appState.permissions.refresh() }
            SettingsLink { Text("設定…") }
                .keyboardShortcut(",")

            Divider()

            Button(updateMenuTitle) { appState.checkForUpdates() }
                .disabled(appState.isUpdating)
            Button("Whisperkun を終了") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 260)
    }

    private var hotkeyStatusText: String {
        let modifiers = appState.settings.hotkeyModifiers
        guard !modifiers.isEmpty else {
            return "ホットキー: 未設定（設定 → ホットキーで割り当て）"
        }
        let action = appState.settings.hotkeyMode == .pushToTalk ? "長押しで録音" : "押すたびに開始/停止"
        if appState.dictation.hotkeyInstalled {
            return "ホットキー: \(HotkeyModifier.displayName(for: modifiers)) \(action)"
        }
        return "ホットキー: 未起動（アクセシビリティ許可が必要）"
    }

    private var updateMenuTitle: String {
        if let release = appState.availableRelease {
            return "アップデート \(release.tagName) をインストール…"
        }
        return "アップデートを確認…"
    }

    @ViewBuilder
    private var recordingSection: some View {
        let phase = appState.transcription.phase
        Button(appState.transcription.isRunning ? "録音を停止" : "録音を開始") {
            appState.toggleRecording()
        }
        .disabled(!appState.permissions.allGranted)

        switch phase {
        case .preparing:
            Text("準備中…").font(.caption).foregroundStyle(.secondary)
        case .listening:
            Text("認識中…").font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Text("エラー: \(message)").font(.caption).foregroundStyle(.red)
        case .idle:
            EmptyView()
        }

        if !appState.transcription.liveText.isEmpty {
            Text(appState.transcription.liveText)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
        }

        Text(hotkeyStatusText)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Toggle("AIで整形（Foundation Models）", isOn: Binding(
            get: { appState.settings.aiFormattingEnabled },
            set: { appState.settings.aiFormattingEnabled = $0; appState.applySettings() }
        ))
        .toggleStyle(.checkbox)
        .disabled(!appState.dictation.aiAvailable)

        if let reason = appState.dictation.aiUnavailableReason {
            Text("AI整形は利用不可: \(reason)")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, state: PermissionState, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: symbol(for: state))
                .foregroundStyle(color(for: state))
            Text(title)
            Spacer()
            if state != .granted {
                Button("許可", action: action)
                    .buttonStyle(.borderless)
            }
        }
    }

    private var accessibilityRow: some View {
        HStack {
            Image(systemName: appState.permissions.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(appState.permissions.accessibilityGranted ? .green : .red)
            Text("アクセシビリティ")
            Spacer()
            if !appState.permissions.accessibilityGranted {
                Button("許可") {
                    appState.permissions.requestAccessibility()
                    appState.ensureHotkeyInstalled()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func symbol(for state: PermissionState) -> String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle"
        case .notDetermined: return "questionmark.circle"
        }
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        }
    }
}
