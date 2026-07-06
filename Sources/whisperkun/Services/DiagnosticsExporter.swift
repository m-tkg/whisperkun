import AppKit
import OSLog
import UniformTypeIdentifiers
import whisperkunCore

/// 診断ログ（自 subsystem の OSLog エントリ）をテキストファイルへ書き出す。
///
/// 「認識中」固着など稀な事象の発生直後に、ユーザーがその場でログを採取するための窓口。
/// `OSLogStore(scope: .currentProcessIdentifier)` は現プロセスのエントリのみ読めるため、
/// 固着中（アプリ生存中）の採取に向く。アプリ再起動後の事後採取は `log show`
/// （docs/diagnostics.md）が受け持つ。
@MainActor
enum DiagnosticsExporter {
    /// 書き出し対象の期間（現在からさかのぼる秒数）。
    private static let exportWindow: TimeInterval = 3600

    /// 直近のログを収集し、保存先を尋ねて書き出す。失敗したらアラートを表示する。
    static func export() {
        do {
            let text = try collectLogText()

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "whisperkun-diagnostics.log"
            // メニューバー常駐（accessory）では前面化しないとパネルが背面に出ることがある。
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try Data(text.utf8).write(to: url)
        } catch {
            AppAlert.show(
                title: String(localized: "エラー"),
                message: String(localized: "診断ログを書き出せませんでした。") + "\n" + error.localizedDescription
            )
        }
    }

    /// 現プロセスの OSLog から自 subsystem のエントリを集めて整形する。
    private static func collectLogText() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: Date(timeIntervalSinceNow: -exportWindow))
        let entries = try store.getEntries(at: position)
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == Log.subsystem }
            .map {
                DiagnosticsLogEntry(
                    date: $0.date,
                    category: $0.category,
                    level: levelName($0.level),
                    message: $0.composedMessage
                )
            }
        return DiagnosticsLogFormatter.format(entries)
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        case .undefined: return "undefined"
        @unknown default: return "unknown"
        }
    }
}
