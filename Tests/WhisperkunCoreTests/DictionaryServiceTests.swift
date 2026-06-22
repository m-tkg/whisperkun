import Testing
@testable import WhisperkunCore

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
}
