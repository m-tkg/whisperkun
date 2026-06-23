import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var appState: AppState

    /// 文字起こしの選択肢（よく使う言語）。
    private let locales: [(id: String, label: String)] = [
        ("ja-JP", "日本語"),
        ("en-US", "英語 (US)"),
        ("zh-CN", "中国語 (簡体)"),
        ("ko-KR", "韓国語"),
    ]

    var body: some View {
        Form {
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
                        Text(locale.label).tag(locale.id)
                    }
                }
            }

            Section("アップデート") {
                Button(updateButtonTitle) { appState.checkForUpdates() }
                    .disabled(appState.isUpdating)
                Text("現在のバージョン: \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var updateButtonTitle: String {
        if let release = appState.availableRelease {
            return "アップデート \(release.tagName) をインストール…"
        }
        return "アップデートを確認"
    }
}
