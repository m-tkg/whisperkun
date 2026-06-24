import SwiftUI

/// 権限（マイク/音声認識/アクセシビリティ）の状態確認と付与。
/// 以前はメニューバーに出していたものを設定ウィンドウへ集約した。
struct PermissionsSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("権限") {
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
            }

            Section {
                Button("状態を再確認") { appState.permissions.refresh() }
                if !appState.permissions.allGranted {
                    Button("セットアップガイドを開く") { appState.showOnboarding() }
                }
            } footer: {
                Text("アクセシビリティはシステム設定で許可後、「状態を再確認」を押してください。")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func permissionRow(title: LocalizedStringKey, state: PermissionState, action: @escaping () -> Void) -> some View {
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
