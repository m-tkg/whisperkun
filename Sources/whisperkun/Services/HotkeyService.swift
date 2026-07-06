import AppKit
import CoreGraphics
import OSLog
import whisperkunCore

private let hkLog = Log.logger(category: "hotkey")

/// グローバルな修飾キーを監視してディクテーションを起動する。
///
/// `CGEventTap` で `flagsChanged` を監視し、設定された修飾キーの押下/解放を検出する。
/// イベントは消費せず（listenOnly）通常の入力を妨げない。アクセシビリティ権限が前提。
@MainActor
final class HotkeyService {
    var mode: HotkeyMode = .pushToTalk
    /// 監視する修飾キーの組み合わせ。空は未設定（ホットキー無効）。
    /// 複数指定時は「すべて同時に押されている」間だけ押下とみなす。
    var modifiers: Set<HotkeyModifier> = []

    /// PTTで押下開始 / トグルで開始したいとき。
    var onStart: (() -> Void)?
    /// PTTで解放 / トグルで停止したいとき。
    var onStop: (() -> Void)?
    /// 診断スナップショットに載せる外部状態（coordinator の phase 等）の提供元。
    var stateSnapshotProvider: (() -> String)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierIsDown = false
    private var toggledOn = false

    /// PTT 押下中に実状態を定期確認する監視タスク。解放イベントを取りこぼしても固着しないための保険。
    private var releaseWatchTask: Task<Void, Never>?
    /// 解放取りこぼし監視の間隔。
    private let releaseWatchInterval = Duration.milliseconds(250)
    /// releaseWatch の開始時刻と経過 tick 数（長時間押下スナップショットの基準）。
    private var releaseWatchStartedAt: Date?
    private var releaseWatchTickCount = 0
    /// 押下がこの時間を超えて続いたら、固着診断用のスナップショットを定期的に残す。
    private let longHoldSnapshotThreshold: TimeInterval = 15
    /// スナップショットを出す間隔（tick 数）。250ms × 8 = 2秒ごと。
    private let longHoldSnapshotStride = 8

    var isInstalled: Bool { eventTap != nil }

    /// イベントタップを開始する。アクセシビリティ未許可だと nil が返り失敗する。
    /// 修飾キーが未設定（nil）の場合は監視せず false を返す。
    @discardableResult
    func install() -> Bool {
        guard !modifiers.isEmpty else { return false }
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func uninstall() {
        stopReleaseWatch()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// C コールバックから呼ばれる。修飾キーの状態変化を解釈してハンドラを発火する。
    fileprivate func handleFlagsChanged(_ flags: UInt64) {
        guard !modifiers.isEmpty else { return }
        // 設定したすべての修飾キーが同時に押されている間だけ「押下」とみなす（device ビットで左右判定）。
        let combined = HotkeyModifier.combinedMask(modifiers)
        applyDownState((flags & combined) == combined)
    }

    /// タップ無効化中に取りこぼした押下/解放を回復する。
    ///
    /// `tapDisabledByTimeout` / `tapDisabledByUserInput` で無効化されている間に
    /// 修飾キーを解放すると、その `flagsChanged` が届かず `modifierIsDown` が押下のまま
    /// 固着し、PTT で「認識中のまま止まらない」状態になる。再有効化の直後に現在の
    /// 修飾キー実状態を読み直し、押下状態の差分があればハンドラを発火して同期する。
    fileprivate func reconcileModifierState() {
        guard !modifiers.isEmpty else { return }
        // `CGEventSource.flagsState` は device-dependent ビットを返さないことがあるため、
        // 左右を畳んだクラスマスクで「今も押されているか」を判定する（固着の確実な解消を優先）。
        //
        // NOTE: 一度 keyState(.combinedSessionState) ベースに切替えたが、PTT で押下継続中にも
        // 稀に false を返し releaseWatch から onStop を誤発火（喋っている途中でウィンドウが閉じる）
        // したため flagsState 判定へ戻した。keyState 化を再挑戦する場合は実機で hold 中の
        // 挙動を必ず検証すること（[[listening-stuck-keystate-regression]]）。
        let observation = observeKeyStates()
        let classMask = HotkeyModifier.combinedClassMask(modifiers)
        let isDown = (observation.flags & classMask) == classMask
        hkLog.debug("reconcile: flags=\(observation.flags, privacy: .public) classMask=\(classMask, privacy: .public) isDown=\(isDown, privacy: .public) modifierIsDown=\(self.modifierIsDown, privacy: .public) keys=[\(observation.keysDescription, privacy: .public)]")
        applyDownState(isDown)
    }

    /// 押下状態の遷移を反映し、必要ならハンドラを発火する。
    private func applyDownState(_ isDown: Bool) {
        guard isDown != modifierIsDown else { return }
        modifierIsDown = isDown

        switch mode {
        case .pushToTalk:
            if isDown {
                hkLog.debug("applyDownState: down -> onStart (ptt)")
                onStart?()
                // 押下中は解放取りこぼしに備えて実状態を定期確認する。
                startReleaseWatch()
            } else {
                hkLog.debug("applyDownState: up -> onStop (ptt)")
                stopReleaseWatch()
                onStop?()
            }
        case .toggle:
            // 押下の立ち上がりでのみトグルする。
            if isDown {
                toggledOn.toggle()
                hkLog.debug("applyDownState: toggle -> \(self.toggledOn ? "onStart" : "onStop", privacy: .public)")
                if toggledOn { onStart?() } else { onStop?() }
            }
        }
    }

    /// PTT 押下中、実状態を一定間隔で確認する。タップ無効化イベントが届かない経路で
    /// 解放を取りこぼしても（特に重い準備中）、ここで実状態に追従して確実に停止させる。
    private func startReleaseWatch() {
        releaseWatchTask?.cancel()
        releaseWatchStartedAt = Date()
        releaseWatchTickCount = 0
        releaseWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.releaseWatchInterval ?? .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                // @MainActor を継承。差分があれば applyDownState 経由で onStop が走り、監視も止まる。
                self.releaseWatchTickCount += 1
                self.logLongHoldSnapshotIfNeeded()
                self.reconcileModifierState()
            }
        }
    }

    private func stopReleaseWatch() {
        releaseWatchTask?.cancel()
        releaseWatchTask = nil
        releaseWatchStartedAt = nil
        releaseWatchTickCount = 0
    }

    // MARK: - 固着診断

    /// 診断用のキー実状態の観測値。判定には使わず、ログにのみ載せる。
    ///
    /// `flagsState`（集約フラグ）が解放後も幽霊的に down を返して「認識中」固着する事象の
    /// 事後診断のため、`keyState` の session/HID 両ストアの物理キー状態を併記する。
    /// keyState は hold 中に稀に false を返すことがあるため判定には使わない
    /// （[[listening-stuck-keystate-regression]]）。
    private struct KeyStateObservation {
        var flags: UInt64
        /// 監視中の各修飾キーの (keyCode, session ストア, HID ストア) の押下状態。
        var perKey: [(keyCode: UInt16, session: Bool, hid: Bool)]

        /// 例: `59:s1h1 54:s0h0`（s=combinedSessionState, h=hidSystemState, 1=down）。
        var keysDescription: String {
            perKey
                .map { "\($0.keyCode):s\($0.session ? 1 : 0)h\($0.hid ? 1 : 0)" }
                .joined(separator: " ")
        }
    }

    private func observeKeyStates() -> KeyStateObservation {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        let perKey = modifiers.sorted { $0.sortOrder < $1.sortOrder }.map { modifier in
            let key = CGKeyCode(modifier.keyCode)
            return (
                keyCode: modifier.keyCode,
                session: CGEventSource.keyState(.combinedSessionState, key: key),
                hid: CGEventSource.keyState(.hidSystemState, key: key)
            )
        }
        return KeyStateObservation(flags: flags, perKey: perKey)
    }

    /// 押下が長く続いているとき、固着診断用のスナップショットを定期的に残す。
    /// 「認識中」固着が起きた時間帯の flags/keyState/コーディネータ状態を事後に確定できる。
    private func logLongHoldSnapshotIfNeeded() {
        guard let startedAt = releaseWatchStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed >= longHoldSnapshotThreshold,
              releaseWatchTickCount % longHoldSnapshotStride == 0 else { return }
        let observation = observeKeyStates()
        let external = stateSnapshotProvider?() ?? "-"
        hkLog.info("long-hold: tick=\(self.releaseWatchTickCount, privacy: .public) elapsed=\(Int(elapsed), privacy: .public)s flags=\(observation.flags, privacy: .public) keys=[\(observation.keysDescription, privacy: .public)] modifierIsDown=\(self.modifierIsDown, privacy: .public) \(external, privacy: .public)")
    }
}

/// `CGEventTap` のコールバック。メインスレッド上の CFRunLoop から呼ばれる。
///
/// この CFRunLoop コールバック文脈で `MainActor.assumeIsolated` を直接呼ぶと、
/// Swift コンカレンシの executor 判定（`swift_task_isCurrentExecutor`）が
/// 成立せず EXC_BAD_ACCESS でクラッシュする（macOS 26 / Swift 6）。
/// `DispatchQueue.main.async` でメインキュー文脈に乗せてから isolation を確定する。
/// 非Sendableな `HotkeyService` をクロージャへ捕捉しないよう、Sendable な
/// `refcon` ポインタを渡して内部で復元する。
private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // タップが無効化された場合（タイムアウト等）は再有効化する。
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        hkLog.debug("tap disabled (type=\(type.rawValue, privacy: .public)) -> re-enable & reconcile")
        if let refcon {
            // 生ポインタは region isolation を跨げないため UInt(bitPattern:) で渡す。
            let address = UInt(bitPattern: refcon)
            DispatchQueue.main.async {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
                let service = Unmanaged<HotkeyService>.fromOpaque(pointer).takeUnretainedValue()
                MainActor.assumeIsolated {
                    if let tap = service.eventTapForReenable {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    // 無効化中に取りこぼしたキー解放/押下を、現在の実状態から回復する。
                    service.reconcileModifierState()
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .flagsChanged, let refcon {
        let flags = event.flags.rawValue
        let address = UInt(bitPattern: refcon)
        DispatchQueue.main.async {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let service = Unmanaged<HotkeyService>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated {
                service.handleFlagsChanged(flags)
            }
        }
    }
    return Unmanaged.passUnretained(event)
}

extension HotkeyService {
    /// コールバックからの再有効化用にタップを公開する。
    fileprivate var eventTapForReenable: CFMachPort? { eventTap }
}
