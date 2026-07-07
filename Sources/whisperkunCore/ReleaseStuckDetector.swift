import Foundation

/// releaseWatch の1tick分のキー実状態の観測値。
///
/// - `flagsDown`: 集約フラグ（`CGEventSource.flagsState`）が押下を示すか。
/// - `sessionKeysDown`: 監視中の全キーの `keyState(.combinedSessionState)` が押下を示すか。
/// - `hidKeysDown`: 監視中の全キーの `keyState(.hidSystemState)` が押下を示すか。
public struct ReleaseTick: Sendable, Equatable {
    public var flagsDown: Bool
    public var sessionKeysDown: Bool
    public var hidKeysDown: Bool

    public init(flagsDown: Bool, sessionKeysDown: Bool, hidKeysDown: Bool) {
        self.flagsDown = flagsDown
        self.sessionKeysDown = sessionKeysDown
        self.hidKeysDown = hidKeysDown
    }
}

/// 「flagsState が幽霊的に down のまま張り付き、解放を検出できない」固着を検出する（純ロジック）。
///
/// 判定条件: flags は押下を示すのに、独立した2つの状態ストア（session/HID の keyState）が
/// **両方とも**解放を示す tick が、必要時間に相当する回数**連続**したら解放とみなす。
///
/// keyState は hold 中に稀に false を返すことがあり、単独・単発の判定に使うと誤発火する
/// （v1.0.23 regression, [[listening-stuck-keystate-regression]]）。2ストアの一致 × 連続性の
/// 要求で過渡ノイズを除外する。flags が解放を示す tick は通常の reconcile 経路が停止を
/// 担うため数えない。
public struct ReleaseStuckDetector: Sendable {
    /// 発火に必要な連続 tick 数（`requiredDuration ÷ tickInterval` の切り上げ、最低1）。
    public let requiredConsecutiveTicks: Int

    /// 発火時のログに載せる直近履歴の上限件数。
    public static let historyLimit = 16

    /// 固着シグネチャが連続している回数。
    public private(set) var consecutiveStuckTicks = 0
    /// この押下セッション中に、session/HID 両ストアが同 tick で押下を報告した実績があるか。
    public private(set) var hasConfirmedKeysDown = false
    /// 直近の観測履歴（新しいものが末尾）。
    public private(set) var recentTicks: [ReleaseTick] = []

    public init(requiredDuration: TimeInterval, tickInterval: TimeInterval) {
        self.requiredConsecutiveTicks = max(1, Int((requiredDuration / tickInterval).rounded(.up)))
    }

    /// 1tick分の観測を記録する。解放が確定したら true を返す。
    public mutating func record(_ tick: ReleaseTick) -> Bool {
        recentTicks.append(tick)
        if recentTicks.count > Self.historyLimit {
            recentTicks.removeFirst(recentTicks.count - Self.historyLimit)
        }

        let isStuckSignature = tick.flagsDown && !tick.sessionKeysDown && !tick.hidKeysDown
        guard isStuckSignature else {
            consecutiveStuckTicks = 0
            return false
        }
        consecutiveStuckTicks += 1
        guard consecutiveStuckTicks >= requiredConsecutiveTicks else { return false }
        consecutiveStuckTicks = 0
        return true
    }

    /// カウントと履歴を破棄する（押下セッションの開始/終了時に呼ぶ）。
    public mutating func reset() {
        consecutiveStuckTicks = 0
        recentTicks.removeAll()
    }
}
