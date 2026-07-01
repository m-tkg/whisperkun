import Foundation

/// 確定テキストの後処理のうち、純ロジック部分（trim → 辞書置換）。
///
/// AI 整形（非同期・HUD 表示を伴う）はこの結果を入力として whisperkun 側で行う。
/// 「辞書 → AI」の順序（AI に正しい語を見せる）はこの型の出力を AI の入力とすることで固定される。
public enum TranscriptPostProcessor {
    /// 前後の空白・改行を除去し、空なら nil、そうでなければ辞書ルールを適用して返す。
    public static func prepare(_ text: String, rules: [DictionaryRule]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return DictionaryService().apply(trimmed, rules: rules)
    }
}
