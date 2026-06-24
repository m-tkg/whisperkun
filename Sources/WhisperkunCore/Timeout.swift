import Foundation

/// `operation` を最大 `seconds` 秒待ち、間に合えば結果を、超過すれば `nil` を返す。
///
/// 重要: `operation` がキャンセルに応答せず返らない場合でも、**必ず `seconds` 後に返る**。
/// 構造化タスク（`withTaskGroup`）は body 終了時にすべての子タスクの完了を待つため、
/// キャンセルを無視してハングする `operation` があると task group 自体が抜けられず固着する。
/// ここでは非構造化タスクと継続で「先に終わった方」を採用し、遅れた方は待たない。
/// 超過時は `operation` のタスクへ `cancel()` を投げるが、応答しなくても呼び出し元は進む。
public func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async -> T
) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let resumer = SingleResume(continuation)
        let work = Task {
            let value = await operation()
            resumer.resume(value)
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            resumer.resume(nil)
            work.cancel()
        }
    }
}

/// 継続を「最初の1回だけ」再開する。複数経路（完了 / タイムアウト）から競合的に
/// 呼ばれても二重 resume しないよう排他する。
private final class SingleResume<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
