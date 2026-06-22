import Testing
@testable import WhisperkunCore

@Suite struct WorkflowServiceTests {
    let service = WorkflowService()

    private let global = WorkflowRule(name: "default", bundleIDs: [], instructions: nil, localeID: nil)
    private let slack = WorkflowRule(name: "slack", bundleIDs: ["com.tinyspeck.slackmacgap"], instructions: "カジュアルに", localeID: "ja-JP")

    @Test func 前面アプリに一致するワークフローを選ぶ() {
        let selected = service.select(for: "com.tinyspeck.slackmacgap", from: [global, slack])
        #expect(selected?.name == "slack")
    }

    @Test func 一致がなければグローバル既定にフォールバックする() {
        let selected = service.select(for: "com.apple.Notes", from: [global, slack])
        #expect(selected?.name == "default")
    }

    @Test func グローバル既定もなければnilを返す() {
        let selected = service.select(for: "com.apple.Notes", from: [slack])
        #expect(selected == nil)
    }

    @Test func bundleIDがnilのときはグローバル既定を使う() {
        let selected = service.select(for: nil, from: [global, slack])
        #expect(selected?.name == "default")
    }

    @Test func アプリ固有がグローバルより優先される() {
        // 順序に依らずアプリ固有を優先する。
        let selected = service.select(for: "com.tinyspeck.slackmacgap", from: [slack, global])
        #expect(selected?.name == "slack")
    }
}
