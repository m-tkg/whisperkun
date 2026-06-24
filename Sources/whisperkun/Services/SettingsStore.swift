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
    /// 録音に使う修飾キーの組み合わせ。空は未設定（ホットキー無効。既定）。
    /// 複数指定時は「すべて同時押し」で発火する。
    var hotkeyModifiers: Set<HotkeyModifier> {
        didSet {
            if hotkeyModifiers.isEmpty {
                defaults.removeObject(forKey: Keys.hotkeyModifiers)
            } else {
                defaults.set(hotkeyModifiers.map(\.rawValue), forKey: Keys.hotkeyModifiers)
            }
        }
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
        static let hotkeyModifier = "hotkeyModifier"     // 旧: 単一修飾キー（移行用）
        static let hotkeyModifiers = "hotkeyModifiers"   // 新: 修飾キー集合
        static let defaultLocaleID = "defaultLocaleID"
        static let aiFormattingEnabled = "aiFormattingEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkeyMode = (defaults.string(forKey: Keys.hotkeyMode)).flatMap(HotkeyMode.init) ?? .pushToTalk
        self.hotkeyModifiers = Self.loadModifiers(from: defaults)
        self.defaultLocaleID = defaults.string(forKey: Keys.defaultLocaleID) ?? "ja-JP"
        self.aiFormattingEnabled = defaults.object(forKey: Keys.aiFormattingEnabled) as? Bool ?? true
    }

    /// 修飾キー集合を読み込む。新キーが無ければ旧・単一キー設定から移行する。既定は空（未設定）。
    private static func loadModifiers(from defaults: UserDefaults) -> Set<HotkeyModifier> {
        if let raws = defaults.stringArray(forKey: Keys.hotkeyModifiers) {
            return Set(raws.compactMap(HotkeyModifier.init(rawValue:)))
        }
        // 旧バージョンの単一修飾キー設定を移行。
        if let single = defaults.string(forKey: Keys.hotkeyModifier).flatMap(HotkeyModifier.init(rawValue:)) {
            return [single]
        }
        return []
    }
}
