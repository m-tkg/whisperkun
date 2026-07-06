import OSLog

/// アプリ共通のロギング窓口。subsystem をここに一元化する。
///
/// subsystem は本番/ローカル検証ビルドで共通の固定値（`com.mtkg.whisperkun`）。
/// Console.app で両ビルドのログを同じ絞り込みで追えるよう、bundle ID とは連動させない。
/// `Resources/Info.plist` の `OSLogPreferences` はこの subsystem 名をキーに debug を
/// 永続化している。変更する場合は両方を揃えること（採取手順は docs/diagnostics.md）。
enum Log {
    static let subsystem = "com.mtkg.whisperkun"

    /// カテゴリ付き Logger を作る。各ファイルの `private let log = Log.logger(category: "...")` から使う。
    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
