import SwiftUI

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
                Picker("キー", selection: Binding(
                    get: { appState.settings.hotkeyModifier },
                    set: { appState.settings.hotkeyModifier = $0; appState.applySettings() }
                )) {
                    ForEach(HotkeyModifier.allCases, id: \.self) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
            }

            if !appState.dictation.hotkeyInstalled {
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
