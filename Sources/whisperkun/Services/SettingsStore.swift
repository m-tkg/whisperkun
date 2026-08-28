import Foundation
import Observation
import whisperkunCore

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
    /// 録音に使う入力デバイスの UID。nil はシステム既定のマイクを使う（既定）。
    var inputDeviceUID: String? {
        didSet { Self.store(inputDeviceUID, forKey: Keys.inputDeviceUID, in: defaults) }
    }
    /// 選択中デバイスの表示名。未接続時に設定画面で名前を出すためだけに保持する。
    var inputDeviceName: String? {
        didSet { Self.store(inputDeviceName, forKey: Keys.inputDeviceName, in: defaults) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let hotkeyMode = "hotkeyMode"
        static let hotkeyModifier = "hotkeyModifier"     // 旧: 単一修飾キー（移行用）
        static let hotkeyModifiers = "hotkeyModifiers"   // 新: 修飾キー集合
        static let defaultLocaleID = "defaultLocaleID"
        static let aiFormattingEnabled = "aiFormattingEnabled"
        static let inputDeviceUID = "inputDeviceUID"
        static let inputDeviceName = "inputDeviceName"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkeyMode = (defaults.string(forKey: Keys.hotkeyMode)).flatMap(HotkeyMode.init) ?? .pushToTalk
        self.hotkeyModifiers = Self.loadModifiers(from: defaults)
        self.defaultLocaleID = defaults.string(forKey: Keys.defaultLocaleID) ?? "ja-JP"
        self.aiFormattingEnabled = defaults.object(forKey: Keys.aiFormattingEnabled) as? Bool ?? true
        self.inputDeviceUID = defaults.string(forKey: Keys.inputDeviceUID)
        self.inputDeviceName = defaults.string(forKey: Keys.inputDeviceName)
    }

    /// nil は「未設定」としてキーごと削除する（空文字を残さない）。
    private static func store(_ value: String?, forKey key: String, in defaults: UserDefaults) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// 修飾キー集合を読み込む。新キーが無ければ旧・単一キー設定から移行する。既定は空（未設定）。
    /// 生値からの解決（移行判定）は `HotkeyModifierMigration` に委譲し、ここは読み出しのみ。
    private static func loadModifiers(from defaults: UserDefaults) -> Set<HotkeyModifier> {
        HotkeyModifierMigration.resolve(
            newRawValues: defaults.stringArray(forKey: Keys.hotkeyModifiers),
            legacySingleRawValue: defaults.string(forKey: Keys.hotkeyModifier)
        )
    }
}
