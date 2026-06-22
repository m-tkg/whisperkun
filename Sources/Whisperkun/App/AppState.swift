import Observation
import SwiftData

/// アプリ全体のルート状態。各サービス・永続化・設定を束ねる。
@MainActor
@Observable
final class AppState {
    let permissions = PermissionsManager()
    let dictation = DictationCoordinator()
    let settings = SettingsStore()
    let modelContainer: ModelContainer
    private let onboarding = OnboardingController()

    /// 文字起こしサービスへの参照（UIのライブ表示用）。
    var transcription: TranscriptionService { dictation.transcription }

    init() {
        do {
            modelContainer = try ModelContainer(
                for: DictionaryEntry.self, Snippet.self, Workflow.self, TranscriptionRecord.self
            )
        } catch {
            fatalError("SwiftData コンテナの初期化に失敗: \(error)")
        }

        applySettings()

        dictation.loadPipelineData = { [weak self] in
            self?.fetchPipelineData() ?? PipelineData()
        }
        dictation.onTranscript = { [weak self] text, bundleID in
            self?.saveHistory(text: text, bundleID: bundleID)
        }

        if permissions.accessibilityGranted {
            dictation.installHotkey()
        }

        // 起動後（NSApp 準備後）に権限が不足していればオンボーディングを表示。
        Task { @MainActor in
            onboarding.showIfNeeded(self)
        }
    }

    /// メニューからオンボーディングを再表示する。
    func showOnboarding() {
        onboarding.show(self)
    }

    /// スカラ設定をパイプライン/ホットキーへ反映する。
    func applySettings() {
        dictation.aiFormattingEnabled = settings.aiFormattingEnabled
        dictation.defaultLocaleID = settings.defaultLocaleID
        dictation.applyHotkeySettings(mode: settings.hotkeyMode, modifier: settings.hotkeyModifier)
    }

    /// 権限付与後などに呼び、ホットキー監視を確実に開始する。
    func ensureHotkeyInstalled() {
        permissions.refresh()
        if permissions.accessibilityGranted {
            dictation.installHotkey()
        }
    }

    func toggleRecording() {
        dictation.toggle()
    }

    // MARK: - SwiftData ブリッジ

    private func fetchPipelineData() -> PipelineData {
        let context = modelContainer.mainContext
        let entries = (try? context.fetch(FetchDescriptor<DictionaryEntry>())) ?? []
        let snippets = (try? context.fetch(FetchDescriptor<Snippet>())) ?? []
        let workflows = (try? context.fetch(FetchDescriptor<Workflow>())) ?? []

        var snippetMap: [String: String] = [:]
        for snippet in snippets { snippetMap[snippet.key] = snippet.value }

        return PipelineData(
            dictionaryRules: entries.map(\.rule),
            snippets: snippetMap,
            workflows: workflows.map(\.rule)
        )
    }

    private func saveHistory(text: String, bundleID: String?) {
        let context = modelContainer.mainContext
        context.insert(TranscriptionRecord(text: text, appBundleID: bundleID))
        try? context.save()
    }
}
