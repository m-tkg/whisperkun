/// アプリ別ワークフローの1ルール。
///
/// `bundleIDs` が空のものはグローバル既定（どのアプリでも一致）。
/// `instructions` は AI整形のワークフロー固有プロンプト、`localeID` は文字起こしロケール。
/// M6でSwiftData `@Model` の `Workflow` から生成する。
public struct WorkflowRule: Sendable, Equatable {
    public let name: String
    public let bundleIDs: [String]
    public let instructions: String?
    public let localeID: String?

    public init(name: String, bundleIDs: [String], instructions: String?, localeID: String?) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.instructions = instructions
        self.localeID = localeID
    }

    public var isGlobal: Bool { bundleIDs.isEmpty }
}
