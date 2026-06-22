import Foundation
import Observation

/// スカラなユーザー設定を UserDefaults に保持する。
/// コレクション（辞書/スニペット/ワークフロー/履歴）は SwiftData 側で管理する。
@MainActor
@Observable
final class SettingsStore {
    var hotkeyMode: HotkeyMode {
        didSet { defaults.set(hotkeyMode.rawValue, forKey: Keys.hotkeyMode) }
    }
    var hotkeyModifier: HotkeyModifier {
        didSet { defaults.set(hotkeyModifier.rawValue, forKey: Keys.hotkeyModifier) }
    }
    var defaultLocaleID: String {
        didSet { defaults.set(defaultLocaleID, forKey: Keys.defaultLocaleID) }
    }
    var aiFormattingEnabled: Bool {
        didSet { defaults.set(aiFormattingEnabled, forKey: Keys.aiFormattingEnabled) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let hotkeyMode = "hotkeyMode"
        static let hotkeyModifier = "hotkeyModifier"
        static let defaultLocaleID = "defaultLocaleID"
        static let aiFormattingEnabled = "aiFormattingEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkeyMode = (defaults.string(forKey: Keys.hotkeyMode)).flatMap(HotkeyMode.init) ?? .pushToTalk
        self.hotkeyModifier = (defaults.string(forKey: Keys.hotkeyModifier)).flatMap(HotkeyModifier.init) ?? .rightCommand
        self.defaultLocaleID = defaults.string(forKey: Keys.defaultLocaleID) ?? "ja-JP"
        self.aiFormattingEnabled = defaults.object(forKey: Keys.aiFormattingEnabled) as? Bool ?? true
    }
}
