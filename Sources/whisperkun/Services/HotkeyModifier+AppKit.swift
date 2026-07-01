import CoreGraphics
import Foundation
import whisperkunCore

/// `HotkeyModifier`（whisperkunCore）のプラットフォーム依存属性。
/// SDK 定数（`CGEventFlags`）とローカライズに依存するため Core には置かない。
extension HotkeyModifier {
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

    /// 修飾キー集合の表示名（例: "左 Shift + 右 Command"）。空なら空文字。
    static func displayName(for set: Set<HotkeyModifier>) -> String {
        set.sorted { $0.sortOrder < $1.sortOrder }.map(\.displayName).joined(separator: " + ")
    }

    /// 集合の device-independent クラスマスクの論理和（左右を畳んだもの）。
    static func combinedClassMask(_ set: Set<HotkeyModifier>) -> UInt64 {
        set.reduce(UInt64(0)) { $0 | $1.classMask }
    }
}
