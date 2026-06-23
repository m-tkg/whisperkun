import AppKit
import Observation
import SwiftData
import WhisperkunCore

/// アプリ全体のルート状態。各サービス・永続化・設定を束ねる。
@MainActor
@Observable
final class AppState {
    let permissions = PermissionsManager()
    let dictation = DictationCoordinator()
    let settings = SettingsStore()
    let modelContainer: ModelContainer
    private let onboarding = OnboardingController()

    // MARK: - アップデート
    @ObservationIgnored private let updateService = UpdateService()
    @ObservationIgnored private lazy var selfUpdater = SelfUpdater(service: updateService)
    /// 利用可能な新バージョン（無ければ nil）。メニュー表示に使う。
    private(set) var availableRelease: ReleaseInfo?
    /// アップデート確認/インストールが進行中か。
    private(set) var isUpdating = false

    /// 文字起こしサービスへの参照（UIのライブ表示用）。
    var transcription: TranscriptionService { dictation.transcription }

    init() {
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

        // 起動時にサイレントでアップデートを確認（結果はメニューに反映）。
        startUpdateCheck(interactive: false)
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

    func toggleRecording() {
        dictation.toggle()
    }

    // MARK: - アップデート

    /// メニューの「アップデートを確認」から呼ぶ（結果をダイアログ表示）。
    func checkForUpdates() {
        startUpdateCheck(interactive: true)
    }

    /// 最新リリースを確認する。`interactive` 時は結果（最新/更新あり/エラー）をダイアログ表示する。
    private func startUpdateCheck(interactive: Bool) {
        guard !isUpdating else { return }
        Task { @MainActor in
            do {
                let release = try await updateService.fetchLatestRelease()
                if VersionComparator.isNewer(tag: release.tagName, than: UpdateService.currentVersion) {
                    availableRelease = release
                    if interactive { promptInstall(release) }
                } else {
                    availableRelease = nil
                    if interactive {
                        showAlert(title: "最新です",
                                  message: "現在のバージョン \(UpdateService.currentVersion) が最新です。")
                    }
                }
            } catch {
                if interactive {
                    showAlert(title: "アップデートの確認に失敗しました",
                              message: error.localizedDescription)
                }
            }
        }
    }

    /// 更新インストールの確認ダイアログを表示し、承認されたら入れ替えを実行する。
    private func promptInstall(_ release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "新しいバージョン \(release.tagName) があります"
        alert.informativeText = "現在のバージョン: \(UpdateService.currentVersion)\nインストールするとアプリを再起動します。"
        alert.addButton(withTitle: "更新")
        alert.addButton(withTitle: "リリースページを開く")
        alert.addButton(withTitle: "キャンセル")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            performUpdate(release)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlUrl) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    private func performUpdate(_ release: ReleaseInfo) {
        isUpdating = true
        Task { @MainActor in
            do {
                // 成功すると selfUpdater 内でアプリが終了するため戻らない。
                try await selfUpdater.performUpdate(to: release)
            } catch {
                isUpdating = false
                showAlert(title: "アップデートに失敗しました", message: error.localizedDescription)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
