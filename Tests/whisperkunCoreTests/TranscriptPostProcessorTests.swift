import Testing
@testable import whisperkunCore

@Suite struct TranscriptPostProcessorTests {
    @Test func 前後の空白と改行を除去する() {
        #expect(TranscriptPostProcessor.prepare("  こんにちは \n", rules: []) == "こんにちは")
    }

    @Test func 空白のみならnil() {
        #expect(TranscriptPostProcessor.prepare("", rules: []) == nil)
        #expect(TranscriptPostProcessor.prepare("  \n\t ", rules: []) == nil)
    }

    @Test func 辞書ルールを適用する() {
        let rules = [DictionaryRule(from: "うぃすぱーくん", to: "whisperkun")]
        #expect(TranscriptPostProcessor.prepare("うぃすぱーくん を起動", rules: rules) == "whisperkun を起動")
    }

    @Test func trimしてから辞書を適用する() {
        let rules = [DictionaryRule(from: "カルテ", to: "karte")]
        #expect(TranscriptPostProcessor.prepare("\n カルテ を開く ", rules: rules) == "karte を開く")
    }

    @Test func ルールが空ならtrimのみ() {
        #expect(TranscriptPostProcessor.prepare(" text ", rules: []) == "text")
    }
}
