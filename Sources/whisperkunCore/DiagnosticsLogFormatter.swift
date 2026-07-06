import Foundation

/// 診断ログ書き出し用の1エントリ（OSLog のエントリから変換して渡す）。
public struct DiagnosticsLogEntry: Sendable {
    public var date: Date
    public var category: String
    public var level: String
    public var message: String

    public init(date: Date, category: String, level: String, message: String) {
        self.date = date
        self.category = category
        self.level = level
        self.message = message
    }
}

/// 診断ログをプレーンテキストへ整形する（純ロジック）。
///
/// 1エントリを `2026-07-06 12:34:56.789 [hotkey] debug: message` 形式の1行にする。
public enum DiagnosticsLogFormatter {
    public static func format(_ entries: [DiagnosticsLogEntry], timeZone: TimeZone = .current) -> String {
        guard !entries.isEmpty else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { entry in
            "\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.level): \(entry.message)\n"
        }.joined()
    }
}
