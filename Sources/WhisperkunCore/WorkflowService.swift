/// 前面アプリの bundle identifier に応じて適用するワークフローを選ぶ純ロジック。
public struct WorkflowService {
    public init() {}

    /// - Parameters:
    ///   - bundleID: 前面アプリの bundle identifier（取得できなければ nil）。
    ///   - workflows: 候補ワークフロー。
    /// - Returns: アプリ固有の一致を優先し、無ければグローバル既定、それも無ければ nil。
    public func select(for bundleID: String?, from workflows: [WorkflowRule]) -> WorkflowRule? {
        if let bundleID,
           let specific = workflows.first(where: { $0.bundleIDs.contains(bundleID) }) {
            return specific
        }
        return workflows.first(where: { $0.isGlobal })
    }
}
