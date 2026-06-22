import AppKit
import CoreGraphics

/// ホットキーの起動方式。
enum HotkeyMode: String, CaseIterable, Codable {
    case pushToTalk  // 押している間だけ録音、離すと確定
    case toggle      // 押すたびに開始/停止を切り替え
}

/// 監視対象の修飾キー（左右を区別するため device-dependent マスクで判定する）。
enum HotkeyModifier: String, CaseIterable, Codable {
    case rightCommand
    case rightOption
    case rightControl
    case rightShift

    /// CGEventFlags 内の device-dependent マスク（IOKit の NX_DEVICER*KEYMASK）。
    var deviceMask: UInt64 {
        switch self {
        case .rightCommand: return 0x0000_0010
        case .rightOption: return 0x0000_0040
        case .rightControl: return 0x0000_2000
        case .rightShift: return 0x0000_0004
        }
    }

    var displayName: String {
        switch self {
        case .rightCommand: return "右 Command"
        case .rightOption: return "右 Option"
        case .rightControl: return "右 Control"
        case .rightShift: return "右 Shift"
        }
    }

    /// 記号表記（レコーダ表示用）。
    var symbol: String {
        switch self {
        case .rightCommand: return "⌘"
        case .rightOption: return "⌥"
        case .rightControl: return "⌃"
        case .rightShift: return "⇧"
        }
    }

    /// `flagsChanged` イベントの仮想キーコードから右側修飾キーを判定する。
    /// 左側のキーや非修飾キーは nil。
    init?(keyCode: UInt16) {
        switch keyCode {
        case 54: self = .rightCommand
        case 61: self = .rightOption
        case 62: self = .rightControl
        case 60: self = .rightShift
        default: return nil
        }
    }
}

/// グローバルな修飾キーを監視してディクテーションを起動する。
///
/// `CGEventTap` で `flagsChanged` を監視し、設定された修飾キーの押下/解放を検出する。
/// イベントは消費せず（listenOnly）通常の入力を妨げない。アクセシビリティ権限が前提。
@MainActor
final class HotkeyService {
    var mode: HotkeyMode = .pushToTalk
    /// 監視する修飾キー。`nil` は未設定（ホットキー無効）。
    var modifier: HotkeyModifier?

    /// PTTで押下開始 / トグルで開始したいとき。
    var onStart: (() -> Void)?
    /// PTTで解放 / トグルで停止したいとき。
    var onStop: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifierIsDown = false
    private var toggledOn = false

    var isInstalled: Bool { eventTap != nil }

    /// イベントタップを開始する。アクセシビリティ未許可だと nil が返り失敗する。
    /// 修飾キーが未設定（nil）の場合は監視せず false を返す。
    @discardableResult
    func install() -> Bool {
        guard modifier != nil else { return false }
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
        guard let modifier else { return }
        let isDown = (flags & modifier.deviceMask) != 0
        guard isDown != modifierIsDown else { return }
        modifierIsDown = isDown

        switch mode {
        case .pushToTalk:
            if isDown { onStart?() } else { onStop?() }
        case .toggle:
            // 押下の立ち上がりでのみトグルする。
            if isDown {
                toggledOn.toggle()
                if toggledOn { onStart?() } else { onStop?() }
            }
        }
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
