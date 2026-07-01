import Foundation

/// アプリ自身のバンドル情報。
enum AppInfo {
    /// 現在のアプリバージョン（CFBundleShortVersionString）。
    /// フォールバック "0" は VersionComparator でどのリリースよりも古い扱いになる値。
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
