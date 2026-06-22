import Foundation

/// テキスト中の `{{...}}` トークンを展開する純ロジック。
///
/// 組み込みトークン: `{{DATE}}` `{{TIME}}` `{{DATETIME}}`。
/// それ以外はユーザー定義スニペット（key→value）で置換し、未知のトークンは残す。
public struct SnippetService {
    public init() {}

    public func expand(
        _ text: String,
        snippets: [String: String],
        now: Date,
        timeZone: TimeZone = .current
    ) -> String {
        var result = text

        // ユーザー定義スニペットを先に展開する。
        for (key, value) in snippets {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        // 組み込みの日時トークン。
        result = result.replacingOccurrences(of: "{{DATE}}", with: format(now, "yyyy-MM-dd", timeZone))
        result = result.replacingOccurrences(of: "{{TIME}}", with: format(now, "HH:mm", timeZone))
        result = result.replacingOccurrences(of: "{{DATETIME}}", with: format(now, "yyyy-MM-dd HH:mm", timeZone))

        return result
    }

    private func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
