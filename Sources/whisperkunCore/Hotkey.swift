/// ホットキーの起動方式。
public enum HotkeyMode: String, CaseIterable, Codable, Sendable {
    case pushToTalk  // 押している間だけ録音、離すと確定
    case toggle      // 押すたびに開始/停止を切り替え
}

/// 監視対象の修飾キー（左右を区別するため device-dependent マスクで判定する）。
///
/// `CGEventFlags` の device-independent マスク（左右を畳んだもの）や表示名など、
/// プラットフォーム SDK・ローカライズに依存する属性は whisperkun 側の extension で足す。
public enum HotkeyModifier: String, CaseIterable, Codable, Sendable {
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftShift
    case rightShift
    case leftCommand
    case rightCommand

    /// CGEventFlags 内の device-dependent マスク（IOKit の NX_DEVICEL*/R*KEYMASK）。
    public var deviceMask: UInt64 {
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

    /// `flagsChanged` イベントの仮想キーコードから修飾キーを判定する。非修飾キーは nil。
    public init?(keyCode: UInt16) {
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

    /// `flagsChanged` イベントの仮想キーコード（`init?(keyCode:)` の逆引き）。
    /// `CGEventSource.keyState` での物理キー状態の観測に使う。
    public var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .leftCommand: return 55
        case .leftShift: return 56
        case .leftOption: return 58
        case .leftControl: return 59
        case .rightShift: return 60
        case .rightOption: return 61
        case .rightControl: return 62
        }
    }

    /// 表示順（⌃⌥⇧⌘ の慣習順。同種は左→右）。
    public var sortOrder: Int {
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

    /// 集合の device マスクの論理和。
    public static func combinedMask(_ set: Set<HotkeyModifier>) -> UInt64 {
        set.reduce(UInt64(0)) { $0 | $1.deviceMask }
    }
}
