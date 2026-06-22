import SwiftUI

@main
struct WhisperkunApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Whisperkun", systemImage: "mic.fill") {
            MenuBarView(appState: appState)
                .modelContainer(appState.modelContainer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
                .modelContainer(appState.modelContainer)
        }
    }
}
