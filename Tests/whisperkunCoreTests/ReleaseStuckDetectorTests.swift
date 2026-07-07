import Testing
@testable import whisperkunCore

@Suite struct ReleaseStuckDetectorTests {
    /// 3秒 ÷ 250ms = 12 tick で発火する設定（実機の releaseWatch と同じ比率）。
    private func makeDetector() -> ReleaseStuckDetector {
        ReleaseStuckDetector(requiredDuration: 3.0, tickInterval: 0.25)
    }

    /// flags は幽霊的に down のまま、両ストアの keyState は解放済み（固着シグネチャ）。
    private let stuck = ReleaseTick(flagsDown: true, sessionKeysDown: false, hidKeysDown: false)
    /// 正常な押下継続。
    private let held = ReleaseTick(flagsDown: true, sessionKeysDown: true, hidKeysDown: true)

    @Test func 必要tick数はrequiredDurationとtickIntervalから導出する() {
        #expect(makeDetector().requiredConsecutiveTicks == 12)
        #expect(ReleaseStuckDetector(requiredDuration: 1.0, tickInterval: 0.4).requiredConsecutiveTicks == 3)
    }

    @Test func 正常な押下継続では発火しない() {
        var detector = makeDetector()
        for _ in 0..<100 {
            #expect(detector.record(held) == false)
        }
    }

    @Test func 幽霊状態が連続したらちょうどNtick目に発火する() {
        var detector = makeDetector()
        // 押下実績（両ストアが down を報告）を確立してから幽霊状態に入る。
        #expect(detector.record(held) == false)
        for _ in 0..<11 {
            #expect(detector.record(stuck) == false)
        }
        #expect(detector.record(stuck) == true)
    }

    @Test func 押下実績がなければ幽霊シグネチャが連続しても発火しない() {
        // keyState が hold 中も一度も down を報告しないキー/キーボードでは、
        // 「解放」報告に情報量がなく、正常な長押しが固着シグネチャに一致してしまう
        // （右 Shift keycode 60 での誤停止事例）。実績なしでは発火させない。
        var detector = makeDetector()
        for _ in 0..<100 {
            #expect(detector.record(stuck) == false)
        }
    }

    @Test func 片ストアのみの押下報告は実績とみなさない() {
        var detector = makeDetector()
        let sessionOnlyHeld = ReleaseTick(flagsDown: true, sessionKeysDown: true, hidKeysDown: false)
        for _ in 0..<3 {
            _ = detector.record(sessionOnlyHeld)
        }
        for _ in 0..<50 {
            #expect(detector.record(stuck) == false)
        }
    }

    @Test func resetで押下実績も消える() {
        var detector = makeDetector()
        _ = detector.record(held)
        detector.reset()
        for _ in 0..<50 {
            #expect(detector.record(stuck) == false)
        }
    }

    @Test func 押下実績なしでも連続カウントと実績フラグは観測できる() {
        // 抑止時に呼び出し側が「シグネチャ充足だが実績なし」を1回だけログするための公開情報。
        var detector = makeDetector()
        for _ in 0..<12 {
            _ = detector.record(stuck)
        }
        #expect(detector.hasConfirmedKeysDown == false)
        #expect(detector.consecutiveStuckTicks == 12)
        _ = detector.record(held)
        #expect(detector.hasConfirmedKeysDown == true)
        #expect(detector.consecutiveStuckTicks == 0)
    }

    @Test func 途中に押下tickが混ざるとカウントはリセットされる() {
        var detector = makeDetector()
        for _ in 0..<11 {
            _ = detector.record(stuck)
        }
        #expect(detector.record(held) == false)  // リセット
        for _ in 0..<11 {
            #expect(detector.record(stuck) == false)  // 再カウント中は発火しない
        }
        #expect(detector.record(stuck) == true)
    }

    @Test func 片ストアだけ解放では発火しない() {
        // keyState は hold 中に稀に false を返す（過去 regression の原因）。
        // 独立した2ストアの一致を要求し、片方だけの false では数えない。
        var detector = makeDetector()
        let sessionOnly = ReleaseTick(flagsDown: true, sessionKeysDown: false, hidKeysDown: true)
        let hidOnly = ReleaseTick(flagsDown: true, sessionKeysDown: true, hidKeysDown: false)
        for _ in 0..<50 {
            #expect(detector.record(sessionOnly) == false)
        }
        for _ in 0..<50 {
            #expect(detector.record(hidOnly) == false)
        }
    }

    @Test func flagsが解放を示すtickは数えない() {
        // flags が up なら通常の reconcile 経路が stop するので、検出器の出番ではない。
        var detector = makeDetector()
        let flagsUp = ReleaseTick(flagsDown: false, sessionKeysDown: false, hidKeysDown: false)
        for _ in 0..<50 {
            #expect(detector.record(flagsUp) == false)
        }
    }

    @Test func resetでカウントが消える() {
        var detector = makeDetector()
        _ = detector.record(held)
        for _ in 0..<11 {
            _ = detector.record(stuck)
        }
        detector.reset()
        // reset 後は押下実績を確立し直してから再カウント。
        _ = detector.record(held)
        for _ in 0..<11 {
            #expect(detector.record(stuck) == false)
        }
        #expect(detector.record(stuck) == true)
    }

    @Test func 直近tick履歴を上限件数まで保持する() {
        var detector = makeDetector()
        for _ in 0..<3 {
            _ = detector.record(held)
        }
        #expect(detector.recentTicks.count == 3)
        for _ in 0..<100 {
            _ = detector.record(stuck)
        }
        #expect(detector.recentTicks.count == ReleaseStuckDetector.historyLimit)
        // 新しい tick が末尾（古いものから捨てる）。
        #expect(detector.recentTicks.last?.sessionKeysDown == false)
    }

    @Test func resetで履歴も消える() {
        var detector = makeDetector()
        for _ in 0..<5 {
            _ = detector.record(held)
        }
        detector.reset()
        #expect(detector.recentTicks.isEmpty)
    }
}
