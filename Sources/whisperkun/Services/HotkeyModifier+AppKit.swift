import Foundation
import whisperkunCore

/// `HotkeyModifier`（whisperkunCore）のプラットフォーム依存属性（ローカライズ）。
/// マスク定数（`classMask` / `combinedClassMask` 等）は Core 側にある。
extension HotkeyModifier {
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
}
