import Foundation
import NaturalLanguage

/// 確定テキストへユーザー辞書のルールを適用して用語を置換する純ロジック。
///
/// 置換は「単語単位」で行う。`NLTokenizer` による単語分割の境界に一致する
/// 出現のみを置換するため、ある語が別の語の一部であるケース（例: "カルテ" は
/// "カルティエ" の中では置換しない）を避けつつ、"機械学習" のように複数トークンに
/// またがる登録語も正しく置換できる。
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
            result = replaceWords(
                in: result,
                from: rule.from,
                to: rule.to,
                caseSensitive: rule.caseSensitive
            )
        }
        return result
    }

    /// `from` を単語境界に一致する箇所だけ `to` へ置換する。
    private func replaceWords(in text: String, from: String, to: String, caseSensitive: Bool) -> String {
        let chars = Array(text)
        let fromChars = Array(from)
        let count = fromChars.count
        guard count > 0, count <= chars.count else { return text }

        let boundaries = wordBoundaries(of: text, totalCount: chars.count)
        let toChars = Array(to)

        var output: [Character] = []
        output.reserveCapacity(chars.count)

        var i = 0
        while i < chars.count {
            if i + count <= chars.count,
               boundaries.contains(i),
               boundaries.contains(i + count),
               matches(chars, at: i, fromChars, caseSensitive: caseSensitive) {
                output.append(contentsOf: toChars)
                i += count
            } else {
                output.append(chars[i])
                i += 1
            }
        }
        return String(output)
    }

    /// 単語境界（各トークンの開始/終了）の文字オフセット集合。文頭・文末も含む。
    private func wordBoundaries(of text: String, totalCount: Int) -> Set<Int> {
        var set: Set<Int> = [0, totalCount]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            set.insert(text.distance(from: text.startIndex, to: range.lowerBound))
            set.insert(text.distance(from: text.startIndex, to: range.upperBound))
            return true
        }
        return set
    }

    /// `chars` の位置 `index` から `pattern` に一致するか（大文字小文字オプション付き）。
    private func matches(_ chars: [Character], at index: Int, _ pattern: [Character], caseSensitive: Bool) -> Bool {
        for k in 0..<pattern.count {
            let a = chars[index + k]
            let b = pattern[k]
            if caseSensitive {
                if a != b { return false }
            } else if String(a).lowercased() != String(b).lowercased() {
                return false
            }
        }
        return true
    }
}
