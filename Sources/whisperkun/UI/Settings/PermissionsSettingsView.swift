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
            Image(systemName: state.symbolName)
                .foregroundStyle(state.indicatorColor)
            Text(title)
            Spacer()
            if state != .granted {
                Button("許可", action: action)
                    .buttonStyle(.borderless)
            }
        }
    }

    private var accessibilityRow: some View {
        // アクセシビリティは付与/未付与の2値（PermissionsManager 参照）。未付与は denied として表示する。
        let state: PermissionState = appState.permissions.accessibilityGranted ? .granted : .denied
        return HStack {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.indicatorColor)
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

}
