import SwiftUI
import whisperkunCore

struct HotkeySettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("起動方式") {
                Picker("方式", selection: Binding(
                    get: { appState.settings.hotkeyMode },
                    set: { appState.settings.hotkeyMode = $0; appState.applySettings() }
                )) {
                    Text("プッシュトゥトーク（長押し中だけ録音）").tag(HotkeyMode.pushToTalk)
                    Text("トグル（押すたびに開始/停止）").tag(HotkeyMode.toggle)
                }
                .pickerStyle(.radioGroup)
            }

            Section("修飾キー") {
                HStack {
                    HotkeyRecorder(modifiers: Binding(
                        get: { appState.settings.hotkeyModifiers },
                        set: { appState.settings.hotkeyModifiers = $0; appState.applySettings() }
                    ))
                    .frame(width: 300, height: 28)

                    Button {
                        appState.settings.hotkeyModifiers = []
                        appState.applySettings()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("ホットキーをクリア（未設定）")
                    .disabled(appState.settings.hotkeyModifiers.isEmpty)
                }

                Text("ボックスをクリックしてから、使いたい修飾キーを押してください（左右どちらも・複数同時押しも可。押している間は表示され、すべて離すと確定）。未設定の間はホットキーで録音できません。左側のキー（左 Command など）はコピー/貼り付け等の通常操作と衝突しやすいので注意。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appState.settings.hotkeyModifiers.isEmpty, !appState.dictation.hotkeyInstalled {
                Section {
                    Text("ホットキーが未起動です。アクセシビリティ権限を許可してください。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("アクセシビリティを許可してホットキーを開始") {
                        appState.permissions.requestAccessibility()
                        appState.ensureHotkeyInstalled()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
