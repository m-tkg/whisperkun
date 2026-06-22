import Testing

// M5 で辞書/スニペット/ワークフローの純ロジックを TDD で実装する土台。
// 現時点はテストターゲットがビルド可能であることの確認のみ。
@Suite struct PlaceholderTests {
    @Test func targetBuilds() {
        #expect(Bool(true))
    }
}
