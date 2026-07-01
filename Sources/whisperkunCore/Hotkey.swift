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
        fatalError("未実装")
    }

    /// `flagsChanged` イベントの仮想キーコードから修飾キーを判定する。非修飾キーは nil。
    public init?(keyCode: UInt16) {
        return nil
    }

    /// 表示順（⌃⌥⇧⌘ の慣習順。同種は左→右）。
    public var sortOrder: Int {
        fatalError("未実装")
    }

    /// 集合の device マスクの論理和。
    public static func combinedMask(_ set: Set<HotkeyModifier>) -> UInt64 {
        fatalError("未実装")
    }
}
