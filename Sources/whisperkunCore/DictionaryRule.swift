/// 用語置換の1ルール（from → to）。
///
/// M6でSwiftData `@Model` の `DictionaryEntry` から生成して `DictionaryService` に渡す。
public struct DictionaryRule: Sendable, Equatable {
    public let from: String
    public let to: String
    public var caseSensitive: Bool

    public init(from: String, to: String, caseSensitive: Bool = true) {
        self.from = from
        self.to = to
        self.caseSensitive = caseSensitive
    }
}
