import Foundation
import Testing
@testable import WhisperkunCore

@Suite struct TimeoutTests {
    @Test("期限内に終わればその結果を返す")
    func returnsResultWithinDeadline() async {
        let result = await withTimeout(seconds: 1.0) { 42 }
        #expect(result == 42)
    }

    @Test("期限を超過したら nil を返す")
    func returnsNilOnTimeout() async {
        // sleep はキャンセルに応答するが、ここでは超過挙動そのものを確認する。
        let result = await withTimeout(seconds: 0.05) { () -> Int in
            try? await Task.sleep(for: .seconds(10))
            return 42
        }
        #expect(result == nil)
    }

    @Test("キャンセルに応答せず返らない処理でも期限内に nil を返す")
    func returnsNilEvenWhenOperationHangs() async {
        // 一度も resume されない継続＝決して返らず、かつキャンセルにも応答しない operation。
        // これが finalizeAndFinishThroughEndOfInput のハングを模した最重要ケース。
        let start = Date()
        let result: Int? = await withTimeout(seconds: 0.1) {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
                // 故意に resume しない（永久に返らない）。
            }
            return 42
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(result == nil)
        // ハングする operation を待たず、期限付近で確実に返ること（固着しない）。
        #expect(elapsed < 2.0)
    }
}
