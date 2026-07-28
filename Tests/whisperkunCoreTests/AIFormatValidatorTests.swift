import Testing
@testable import whisperkunCore

@Suite struct AIFormatValidatorTests {
    @Test func 同一テキストはvalid() {
        #expect(AIFormatValidator.validate(
            original: "今日の会議の資料を確認する",
            formatted: "今日の会議の資料を確認する") == .valid)
    }

    @Test func フィラー除去はvalid() {
        #expect(AIFormatValidator.validate(
            original: "えーと、今日の会議",
            formatted: "今日の会議") == .valid)
    }

    @Test func カタカナ語の英語化はvalid() {
        #expect(AIFormatValidator.validate(
            original: "今日のコミットをレビューしてほしい",
            formatted: "今日のcommitをreviewしてほしい") == .valid)
    }

    @Test func フィラー除去と英語化の複合はvalid() {
        #expect(AIFormatValidator.validate(
            original: "えーと、今日のコミットをレビューしてほしい",
            formatted: "今日のcommitをreviewしてほしい") == .valid)
    }

    @Test func 漢字語の英語化はhanMismatch() {
        // 再現バグ: カタカナ語でない「時間」「苦戦」が英語化される
        #expect(AIFormatValidator.validate(
            original: "結構時間がかかってるけど、何に苦戦してる？",
            formatted: "結構timeがかかってるけど、何にstruggleしてる？") == .hanMismatch)
    }

    @Test func 漢字語の削除はhanMismatch() {
        #expect(AIFormatValidator.validate(
            original: "今日の会議の資料を確認する",
            formatted: "会議の資料を確認する") == .hanMismatch)
    }

    @Test func 漢字語の追加はhanMismatch() {
        #expect(AIFormatValidator.validate(
            original: "今日は何曜日？",
            formatted: "今日は月曜日です") == .hanMismatch)
    }

    @Test func 漢字の語順入替はhanMismatch() {
        #expect(AIFormatValidator.validate(
            original: "資料を確認、会議に出席",
            formatted: "会議に出席、資料を確認") == .hanMismatch)
    }

    @Test func 漢数字の算用数字化はhanMismatch() {
        #expect(AIFormatValidator.validate(
            original: "三時に会議",
            formatted: "3時に会議") == .hanMismatch)
    }

    @Test func 々を含む漢字語の英語化はhanMismatch() {
        #expect(AIFormatValidator.validate(
            original: "日々の記録",
            formatted: "dailyの記録") == .hanMismatch)
    }

    @Test func 語尾書き換えはhiraganaInserted() {
        // 「してほしい」→「する」は「す」の後に「る」が挿入される
        #expect(AIFormatValidator.validate(
            original: "レビューしてほしい",
            formatted: "レビューする") == .hiraganaInserted)
    }

    @Test func カタカナ語の言い換えはkatakanaInserted() {
        #expect(AIFormatValidator.validate(
            original: "ミーティングの予定",
            formatted: "カンファレンスの予定") == .katakanaInserted)
    }

    @Test func 長音付きフィラー除去と英語化はvalid() {
        // 長音「ー」はカタカナ扱い。「あのー」の除去も「サーバー→server」も削除のみ
        #expect(AIFormatValidator.validate(
            original: "あのー、サーバーの確認",
            formatted: "serverの確認") == .valid)
    }

    @Test func 句読点のみの変更はvalid() {
        // 句読点・記号は意図的にスコープ外（軽微な揺れでフォールバックさせない）
        #expect(AIFormatValidator.validate(
            original: "今日は晴れです、明日は雨です",
            formatted: "今日は晴れです。明日は雨です。") == .valid)
    }

    @Test func NFC正規化で合成分解の揺れを同一視する() {
        // "か" + 結合濁点 (U+3099) と合成済み "が"
        #expect(AIFormatValidator.validate(
            original: "時間か\u{3099}かかる",
            formatted: "時間がかかる") == .valid)
    }

    @Test func 半角カタカナの英語化はvalid() {
        #expect(AIFormatValidator.validate(
            original: "ｺﾐｯﾄして",
            formatted: "commitして") == .valid)
    }

    @Test func 絵文字や改行は判定に影響しない() {
        #expect(AIFormatValidator.validate(
            original: "了解です👍\n次に進む",
            formatted: "了解です 次に進む") == .valid)
    }
}
