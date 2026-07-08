import AppKit
import Observation
import KunAppKit
import KunUpdateKit
import whisperkunCore

/// アップデートの統括: 起動時/定期/スリープ復帰のサイレントチェック、手動チェック、
/// 新版有無の一元管理、インストール実行。
@MainActor
@Observable
final class UpdateCoordinator {
    @ObservationIgnored private let updateService = UpdateService()
    // 自己更新は kunkit 共通実装（zip DL は KunUpdateKit の ReleaseDownloader / URLSession）。
    @ObservationIgnored private lazy var selfUpdater = SelfUpdater(appName: "whisperkun")
    /// 利用可能な新バージョン（無ければ nil）。メニュー表示に使う。
    private(set) var availableRelease: ReleaseInfo?
    /// アップデート確認/インストールが進行中か。
    private(set) var isUpdating = false
    /// 新版の有無が変わったときに呼ぶ（引数: 新版あり=true）。メニューバーの赤バッジ同期に使う。
    @ObservationIgnored var onUpdateAvailabilityChanged: ((Bool) -> Void)?
    /// 定期サイレントチェック用タイマー。
    @ObservationIgnored private var updateCheckTimer: Timer?
    /// スリープ復帰通知の購読トークン。
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// 起動時のサイレントチェックと、定期＋スリープ復帰チェックの配線を開始する。
    func start() {
        // 起動時にサイレントでアップデートを確認（結果はメニュー/バッジに反映）。
        startUpdateCheck(interactive: false)
        // 起動後も定期＋スリープ復帰でサイレントチェックする。
        scheduleUpdateChecks()
    }

    /// メニューの「アップデートを確認」から呼ぶ（結果をダイアログ表示）。
    func checkForUpdates() {
        startUpdateCheck(interactive: true)
    }

    /// 新版の有無を一元管理する（base の setUpdateAvailable/clearUpdateAvailable 相当）。
    /// availableRelease 更新とバッジ/メニュー同期通知をここに集約し、全チェック経路から必ず通す。
    private func setAvailableRelease(_ release: ReleaseInfo?) {
        availableRelease = release
        onUpdateAvailabilityChanged?(release != nil)
    }

    /// 定期サイレントチェック（Timer）とスリープ復帰時チェックを配線する。
    /// Timer はスリープ中に発火しないため、`didWakeNotification` で復帰時にも即チェックする
    /// （ノート PC で「閉じている間に新版」に対応）。
    private func scheduleUpdateChecks() {
        // チェック間隔は kun シリーズ共通定数（6時間）。未認証 GitHub API のレート制限（60回/時）に
        // 十分収まり、ETag 条件付き取得（304 は消費しない）と併せて枯渇を避ける。
        let timer = Timer.scheduledTimer(withTimeInterval: KunUpdateSchedule.checkInterval, repeats: true) { [weak self] _ in
            // Timer のブロックはメインスレッドで呼ばれるが非隔離なので assumeIsolated で @MainActor 文脈に乗せる。
            MainActor.assumeIsolated {
                self?.startUpdateCheck(interactive: false)
            }
        }
        // 省電力のためコアレッシングを許可（間隔の 10%）。
        timer.tolerance = KunUpdateSchedule.checkIntervalTolerance
        updateCheckTimer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startUpdateCheck(interactive: false)
            }
        }
    }

    /// 最新リリースを確認する。`interactive` 時は結果（最新/更新あり/エラー）をダイアログ表示する。
    private func startUpdateCheck(interactive: Bool) {
        guard !isUpdating else { return }
        Task { @MainActor in
            do {
                let release = try await updateService.fetchLatestRelease()
                if VersionComparator.isNewer(tag: release.tagName, than: AppInfo.version) {
                    setAvailableRelease(release)
                    if interactive { promptInstall(release) }
                } else {
                    setAvailableRelease(nil)
                    if interactive {
                        AppAlert.show(title: String(localized: "最新です"),
                                      message: String(localized: "現在のバージョン \(AppInfo.version) が最新です。"))
                    }
                }
            } catch {
                if interactive {
                    AppAlert.show(title: String(localized: "アップデートの確認に失敗しました"),
                                  message: error.localizedDescription)
                }
            }
        }
    }

    /// 更新インストールの確認ダイアログを表示し、承認されたら入れ替えを実行する。
    private func promptInstall(_ release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = String(localized: "新しいバージョン \(release.tagName) があります")
        alert.informativeText = String(localized: "現在のバージョン: \(AppInfo.version)\nインストールするとアプリを再起動します。")
        alert.addButton(withTitle: String(localized: "更新"))
        alert.addButton(withTitle: String(localized: "リリースページを開く"))
        alert.addButton(withTitle: String(localized: "キャンセル"))

        switch AppAlert.runModal(alert) {
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
                AppAlert.show(title: String(localized: "アップデートに失敗しました"), message: error.localizedDescription)
            }
        }
    }
}
