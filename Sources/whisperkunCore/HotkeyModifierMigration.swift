/// ホットキー修飾キー設定の読み込み判定（旧・単一キー設定からの移行を含む）。
///
/// UserDefaults の読み出し自体は `SettingsStore` が担い、生の値からの解決だけをここで行う。
public enum HotkeyModifierMigration {
    /// 修飾キー集合を解決する。
    /// - Parameters:
    ///   - newRawValues: 新キー（修飾キー集合）の生値。キー自体が無ければ nil。
    ///   - legacySingleRawValue: 旧キー（単一修飾キー）の生値。無ければ nil。
    /// - Returns: 新キーがあればそれを採用（不正な生値は無視）。無ければ旧キーから移行。どちらも無ければ空。
    public static func resolve(newRawValues: [String]?, legacySingleRawValue: String?) -> Set<HotkeyModifier> {
        if let newRawValues {
            return Set(newRawValues.compactMap(HotkeyModifier.init(rawValue:)))
        }
        if let single = legacySingleRawValue.flatMap(HotkeyModifier.init(rawValue:)) {
            return [single]
        }
        return []
    }
}
