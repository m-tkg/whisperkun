import SwiftUI

/// 権限状態の UI 表現（SF Symbol / 色）。設定・オンボーディングで共通に使う。
extension PermissionState {
    var symbolName: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle"
        case .notDetermined: return "questionmark.circle"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        }
    }
}
