import AppKit
import CoreGraphics
import OSLog

private let hkLog = Log.logger(category: "hotkey")

/// ホットキーの起動方式。
enum HotkeyMode: String, CaseIterable, Codable {
    case pushToTalk  // 押している間だけ録音、離すと確定
    case toggle      // 押すたびに開始/停止を切り替え
}

/// 監視対象の修飾キー（左右を区別するため device-dependent マスクで判定する）。
enum HotkeyModifier: String, CaseIterable, Codable {
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftShift
    case rightShift
    case leftCommand
    case rightCommand

    /// CGEventFlags 内の device-dependent マスク（IOKit の NX_DEVICEL*/R*KEYMASK）。
    var deviceMask: UInt64 {
        switch self {
        case .leftControl: return 0x0000_0001
        case .leftShift: return 0x0000_0002
        case .rightShift: return 0x0000_0004
        case .leftCommand: return 0x0000_0008
        case .rightCommand: return 0x0000_0010
        case .leftOption: return 0x0000_0020
        case .rightOption: return 0x0000_0040
        case .rightControl: return 0x0000_2000
        }
    }

    /// device-independent な修飾クラスのマスク（左右を区別しない）。
    /// タップ再有効化時に `CGEventSource.flagsState` から現在状態を読み直す際に使う。
    /// `flagsState` は device-dependent ビットを返さないことがあるため、再同期では
    /// 左右を畳んだこのマスクで「押下中か」を判定する。
    var classMask: UInt64 {
        switch self {
        case .leftControl, .rightControl: return CGEventFlags.maskControl.rawValue
        case .leftShift, .rightShift: return CGEventFlags.maskShift.rawValue
        case .leftOption, .rightOption: return CGEventFlags.maskAlternate.rawValue
        case .leftCommand, .rightCommand: return CGEventFlags.maskCommand.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .leftControl: return String(localized: "左 Control")
        case .rightControl: return String(localized: "右 Control")
        case .leftOption: return String(localized: "左 Option")
        case .rightOption: return String(localized: "右 Option")
        case .leftShift: return String(localized: "左 Shift")
        case .rightShift: return String(localized: "右 Shift")
        case .leftCommand: return String(localized: "左 Command")
        case .rightCommand: return String(localized: "右 Command")
        }
    }

    /// `flagsChanged` イベントの仮想キーコードから修飾キーを判定する。非修飾キーは nil。
    init?(keyCode: UInt16) {
        switch keyCode {
        case 54: self = .rightCommand
        case 55: self = .leftCommand
        case 56: self = .leftShift
        case 58: self = .leftOption
        case 59: self = .leftControl
        case 60: self = .rightShift
        case 61: self = .rightOption
        case 62: self = .rightControl
        default: return nil
        }
    }

    /// 表示順（⌃⌥⇧⌘ の慣習順。同種は左→右）。
    var sortOrder: Int {
        switch self {
        case .leftControl: return 0
        case .rightControl: return 1
        case .leftOption: return 2
        case .rightOption: return 3
        case .leftShift: return 4
        case .rightShift: return 5
        case .leftCommand: return 6
        case .rightCommand: return 7
        }
    }

    /// 修飾キー集合の表示名（例: "左 Shift + 右 Command"）。空なら空文字。
    static func displayName(for set: Set<HotkeyModifier>) -> String {
        set.sorted { $0.sortOrder < $1.sortOrder }.map(\.displayName).joined(separator: " + ")
    }

    /// 集合の device マスクの論理和。
    static func combinedMask(_ set: Set<HotkeyModifier>) -> UInt64 {
        set.reduce(UInt64(0)) { $0 | $1.deviceMask }
    }

    /// 集合の device-independent クラスマスクの論理和（左右を畳んだもの）。
    static func combinedClassMask(_ set: Set<HotkeyModifier>) -> UInt64 {
        set.reduce(UInt64(0)) { $0 | $1.classMask }
    }
}

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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierIsDown = false
    private var toggledOn = false

    /// PTT 押下中に実状態を定期確認する監視タスク。解放イベントを取りこぼしても固着しないための保険。
    private var releaseWatchTask: Task<Void, Never>?
    /// 解放取りこぼし監視の間隔。
    private let releaseWatchInterval = Duration.milliseconds(250)

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
        let current = CGEventSource.flagsState(.combinedSessionState).rawValue
        let classMask = HotkeyModifier.combinedClassMask(modifiers)
        let isDown = (current & classMask) == classMask
        hkLog.debug("reconcile: flags=\(current, privacy: .public) classMask=\(classMask, privacy: .public) isDown=\(isDown, privacy: .public) modifierIsDown=\(self.modifierIsDown, privacy: .public)")
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
        releaseWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.releaseWatchInterval ?? .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                // @MainActor を継承。差分があれば applyDownState 経由で onStop が走り、監視も止まる。
                self.reconcileModifierState()
            }
        }
    }

    private func stopReleaseWatch() {
        releaseWatchTask?.cancel()
        releaseWatchTask = nil
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
