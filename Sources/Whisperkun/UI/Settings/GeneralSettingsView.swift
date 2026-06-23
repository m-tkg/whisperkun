import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var appState: AppState

    /// ログイン項目トグルの表示状態。システム（`SMAppService`）を真実の源とし、
    /// 操作のたびに読み直すためのローカルキャッシュ。
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    /// 登録/解除に失敗したときのメッセージ。
    @State private var launchAtLoginError: String?

    /// 文字起こしの選択肢（よく使う言語）。
    private let locales: [(id: String, label: String)] = [
        ("ja-JP", "日本語"),
        ("en-US", "英語 (US)"),
        ("zh-CN", "中国語 (簡体)"),
        ("ko-KR", "韓国語"),
    ]

    var body: some View {
        Form {
            Section("起動") {
                Toggle("ログイン時に自動起動する", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))

                if let error = launchAtLoginError {
                    Text("設定に失敗しました: \(error)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("AI整形") {
                Toggle("Foundation Models で整形する", isOn: Binding(
                    get: { appState.settings.aiFormattingEnabled },
                    set: { appState.settings.aiFormattingEnabled = $0; appState.applySettings() }
                ))
                .disabled(!appState.dictation.aiAvailable)

                if let reason = appState.dictation.aiUnavailableReason {
                    Text("利用不可: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("文字起こし") {
                Picker("既定の言語", selection: Binding(
                    get: { appState.settings.defaultLocaleID },
                    set: { appState.settings.defaultLocaleID = $0; appState.applySettings() }
                )) {
                    ForEach(locales, id: \.id) { locale in
                        Text(LocalizedStringKey(locale.label)).tag(locale.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { launchAtLogin = LaunchAtLoginService.isEnabled }
    }

    /// ログイン項目の登録/解除を行い、結果でトグルとエラー表示を更新する。
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        // システム側の実際の状態に合わせて表示を確定する。
        launchAtLogin = LaunchAtLoginService.isEnabled
    }
}
