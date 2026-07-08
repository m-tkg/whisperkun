import AppKit
import KunAppKit
import Observation
import SwiftData
import whisperkunCore

/// アプリ全体のルート状態。各サービス・永続化・設定を束ねる。
@MainActor
@Observable
final class AppState {
    let permissions = PermissionsManager()
    let dictation = DictationCoordinator()
    let settings = SettingsStore()
    /// アップデート統括（起動時/定期/復帰チェック・インストール）。
    let updates = UpdateCoordinator()
    let modelContainer: ModelContainer
    private let onboarding = OnboardingController()

    /// 文字起こしサービスへの参照（UIのライブ表示用）。
    var transcription: TranscriptionService { dictation.transcription }

    init() {
        // 多重起動防止: 同一バンドルIDの既存インスタンスがあれば前面化して自分は終了する（kunkit 共通実装）。
        KunAppLaunch.terminateIfAlreadyRunning()

        do {
            modelContainer = try ModelContainer(
                for: DictionaryEntry.self, TranscriptionRecord.self
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

        // 起動時サイレントチェック＋定期/スリープ復帰チェックを開始。
        updates.start()
    }

    /// メニューからオンボーディングを再表示する。
    func showOnboarding() {
        onboarding.show(self)
    }

    /// スカラ設定をパイプライン/ホットキーへ反映する。
    func applySettings() {
        dictation.aiFormattingEnabled = settings.aiFormattingEnabled
        dictation.defaultLocaleID = settings.defaultLocaleID
        dictation.applyHotkeySettings(mode: settings.hotkeyMode, modifiers: settings.hotkeyModifiers)
        // 修飾キーが設定済みで権限があれば監視を開始する（未設定なら applyHotkeySettings 側で停止済み）。
        if !settings.hotkeyModifiers.isEmpty, permissions.accessibilityGranted {
            dictation.installHotkey()
        }
    }

    /// 権限付与後などに呼び、ホットキー監視を確実に開始する。
    func ensureHotkeyInstalled() {
        permissions.refresh()
        if permissions.accessibilityGranted {
            dictation.installHotkey()
        }
    }

    // MARK: - SwiftData ブリッジ

    private func fetchPipelineData() -> PipelineData {
        let context = modelContainer.mainContext
        let entries = (try? context.fetch(FetchDescriptor<DictionaryEntry>())) ?? []
        return PipelineData(dictionaryRules: entries.map(\.rule))
    }

    private func saveHistory(text: String, bundleID: String?) {
        let context = modelContainer.mainContext
        context.insert(TranscriptionRecord(text: text, appBundleID: bundleID))
        try? context.save()
    }
}
