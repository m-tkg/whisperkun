import Foundation

/// 確定テキストへユーザー辞書のルールを適用して用語を置換する純ロジック。
public struct DictionaryService {
    public init() {}

    /// ルールを適用したテキストを返す。
    ///
    /// 長い `from` を先に適用することで、短い語が長い語の一部を壊すのを防ぐ
    /// （例: "機械" が "機械学習" を壊さない）。
    public func apply(_ text: String, rules: [DictionaryRule]) -> String {
        let sorted = rules
            .filter { !$0.from.isEmpty }
            .sorted { $0.from.count > $1.from.count }

        var result = text
        for rule in sorted {
            if rule.caseSensitive {
                result = result.replacingOccurrences(of: rule.from, with: rule.to)
            } else {
                result = result.replacingOccurrences(
                    of: rule.from,
                    with: rule.to,
                    options: [.caseInsensitive]
                )
            }
        }
        return result
    }
}
