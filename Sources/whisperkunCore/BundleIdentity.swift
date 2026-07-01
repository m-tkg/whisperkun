/// バンドル ID の基底名（ローカル検証ビルドの `.local` サフィックスを除いた ID）を扱う。
///
/// ローカル検証ビルド（`com.mtkg.whisperkun.local`）と本番（`com.mtkg.whisperkun`）を
/// 同一アプリとして扱いたい場面（自己更新のID検証・kuntraykun 連携・ローカル表示判定）で使う。
public enum BundleIdentity {
    /// `.local` サフィックスを除いた基底バンドル ID。nil は nil のまま返す。
    public static func baseID(_ id: String?) -> String? {
        fatalError("未実装")
    }

    /// ローカル検証ビルド（`.local` 終端）の ID かどうか。nil は false。
    public static func isLocal(_ id: String?) -> Bool {
        fatalError("未実装")
    }
}
