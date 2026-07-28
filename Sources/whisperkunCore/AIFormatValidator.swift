import Foundation

/// AI 整形出力の決定的検証。許可操作（フィラー除去・カタカナ語の英語化）で
/// 説明できない変換を検出する。違反時は呼び出し側が整形前テキストへフォールバックする。
///
/// 許可操作はどちらも「漢字に触れない」「かなを削除することはあっても挿入しない」ため、
/// 正当な出力は次の3条件を必ず満たす:
/// 1. 漢字シーケンスが入力と完全一致（漢字語の英語化・削除・追加・並べ替えを捕捉）
/// 2. 出力のひらがなシーケンスが入力の部分列（語尾書き換え・回答生成を捕捉）
/// 3. 出力のカタカナシーケンスが入力の部分列（カタカナ語の言い換えを捕捉）
///
/// 句読点・記号・空白・Latin・算用数字は意図的に検査対象外（軽微な揺れで
/// フォールバックが頻発すると整形自体が無意味になるため）。ひらがな語の英語化は
/// フィラー除去（削除）と区別できず素通しするが、内容語の大半を占める漢字語は条件1で捕捉される。
public enum AIFormatValidator {
    public enum Verdict: Equatable, Sendable {
        case valid
        /// 漢字シーケンス不一致（英語化・削除・追加・並べ替え）
        case hanMismatch
        /// 出力のひらがなが入力の部分列でない（挿入・書き換え）
        case hiraganaInserted
        /// 出力のカタカナが入力の部分列でない（挿入・言い換え）
        case katakanaInserted
    }

    /// - Parameters:
    ///   - original: AI 整形前（辞書適用済み）テキスト
    ///   - formatted: AI 出力
    public static func validate(original: String, formatted: String) -> Verdict {
        let source = original.precomposedStringWithCanonicalMapping.unicodeScalars
        let output = formatted.precomposedStringWithCanonicalMapping.unicodeScalars

        guard source.filter(isHan).elementsEqual(output.filter(isHan)) else {
            return .hanMismatch
        }
        guard isSubsequence(output.filter(isHiragana), of: source.filter(isHiragana)) else {
            return .hiraganaInserted
        }
        guard isSubsequence(output.filter(isKatakana), of: source.filter(isKatakana)) else {
            return .katakanaInserted
        }
        return .valid
    }

    /// 漢字。CJK 統合漢字・拡張・互換漢字に加え、踊り字「々」（Han だが isIdeographic 外）を含める。
    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isIdeographic || scalar.value == 0x3005
    }

    private static func isHiragana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x309F).contains(scalar.value)
    }

    /// カタカナ。長音「ー」(U+30FC)・小書き拡張・半角カナを含める。
    /// 長音をカタカナ扱いにすることで「あのー」の除去も「サーバー→server」も削除として通る。
    private static func isKatakana(_ scalar: Unicode.Scalar) -> Bool {
        (0x30A0...0x30FF).contains(scalar.value)
            || (0x31F0...0x31FF).contains(scalar.value)
            || (0xFF66...0xFF9F).contains(scalar.value)
    }

    private static func isSubsequence(_ needle: [Unicode.Scalar], of haystack: [Unicode.Scalar]) -> Bool {
        var index = needle.startIndex
        for scalar in haystack where index < needle.endIndex && needle[index] == scalar {
            index += 1
        }
        return index == needle.endIndex
    }
}
