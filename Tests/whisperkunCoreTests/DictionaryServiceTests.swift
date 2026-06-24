import Testing
@testable import whisperkunCore

@Suite struct DictionaryServiceTests {
    let service = DictionaryService()

    @Test func 単一の用語を置換する() {
        let rules = [DictionaryRule(from: "ぎじゅつ", to: "技術")]
        #expect(service.apply("これはぎじゅつです", rules: rules) == "これは技術です")
    }

    @Test func 複数箇所を置換する() {
        let rules = [DictionaryRule(from: "猫", to: "ねこ")]
        #expect(service.apply("猫と猫", rules: rules) == "ねことねこ")
    }

    @Test func より長い一致を優先する() {
        // "機械" だけだと "機械学習" を壊すため、長い方を先に適用する。
        let rules = [
            DictionaryRule(from: "機械", to: "マシン"),
            DictionaryRule(from: "機械学習", to: "ML"),
        ]
        #expect(service.apply("機械学習が好き", rules: rules) == "MLが好き")
    }

    @Test func 空のfromは無視する() {
        #expect(service.apply("abc", rules: [DictionaryRule(from: "", to: "Z")]) == "abc")
    }

    @Test func 大文字小文字を無視して置換できる() {
        let rules = [DictionaryRule(from: "swift", to: "Swift", caseSensitive: false)]
        #expect(service.apply("I love SWIFT and swift", rules: rules) == "I love Swift and Swift")
    }

    @Test func 大文字小文字を区別する既定動作() {
        let rules = [DictionaryRule(from: "swift", to: "Swift")]
        #expect(service.apply("SWIFT swift", rules: rules) == "SWIFT Swift")
    }

    // MARK: - 単語単位の置換

    @Test func 独立した単語は置換する() {
        let rules = [DictionaryRule(from: "カルテ", to: "KARTE")]
        #expect(service.apply("カルテを記入する", rules: rules) == "KARTEを記入する")
    }

    @Test func 別の単語の一部は置換しない() {
        // "カルティエ" は1単語なので、その中の "カルテ" は置換しない。
        let rules = [DictionaryRule(from: "カルテ", to: "KARTE")]
        #expect(service.apply("カルティエの時計", rules: rules) == "カルティエの時計")
    }

    @Test func 漢字に続く単語も置換する() {
        let rules = [DictionaryRule(from: "カルテ", to: "KARTE")]
        #expect(service.apply("電子カルテ", rules: rules) == "電子KARTE")
    }

    @Test func 英単語は単語境界で置換し部分一致しない() {
        let rules = [DictionaryRule(from: "cat", to: "CAT")]
        #expect(service.apply("a cat and a category", rules: rules) == "a CAT and a category")
    }
}
