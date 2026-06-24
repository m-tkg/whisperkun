import Foundation
import NaturalLanguage

/// 確定テキストへユーザー辞書のルールを適用して用語を置換する純ロジック。
///
/// 置換は「単語単位」で行う。`NLTokenizer` による単語分割の境界に一致する
/// 出現のみを置換するため、ある語が別の語の一部であるケース（例: "カルテ" は
/// "カルティエ" の中では置換しない）を避けつつ、"機械学習" のように複数トークンに
/// またがる登録語も正しく置換できる。
///
/// 性能のため、トークン化は1回だけ行い、全ルールを単一パスで適用する
/// （以前はルールごとに再トークン化していて辞書が増えると遅かった）。
public struct DictionaryService {
    public init() {}

    /// ルールを適用したテキストを返す。
    ///
    /// 各位置で長い `from` から順に試すことで、短い語が長い語の一部を壊すのを防ぐ
    /// （例: "機械" が "機械学習" を壊さない）。
    public func apply(_ text: String, rules: [DictionaryRule]) -> String {
        let active = rules
            .filter { !$0.from.isEmpty }
            .sorted { $0.from.count > $1.from.count }
        guard !active.isEmpty, !text.isEmpty else { return text }

        // 単語境界（各トークンの開始/終了の String.Index）。トークン化は1回だけ。
        let boundaries = wordBoundaries(of: text)

        var output = ""
        output.reserveCapacity(text.count)

        var index = text.startIndex
        while index < text.endIndex {
            var replaced = false
            // 単語境界の位置でのみ置換を試みる。
            if boundaries.contains(index) {
                for rule in active {
                    let options: String.CompareOptions = rule.caseSensitive
                        ? [.anchored]
                        : [.anchored, .caseInsensitive]
                    // `index` から始まる `from` の一致のみ（.anchored）。
                    if let matched = text.range(of: rule.from, options: options, range: index..<text.endIndex),
                       matched.lowerBound == index,
                       boundaries.contains(matched.upperBound) {
                        output += rule.to
                        index = matched.upperBound
                        replaced = true
                        break
                    }
                }
            }
            if !replaced {
                output.append(text[index])
                index = text.index(after: index)
            }
        }
        return output
    }

    /// 単語境界（各トークンの開始/終了）の String.Index 集合。文頭・文末も含む。
    private func wordBoundaries(of text: String) -> Set<String.Index> {
        var set: Set<String.Index> = [text.startIndex, text.endIndex]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            set.insert(range.lowerBound)
            set.insert(range.upperBound)
            return true
        }
        return set
    }
}
