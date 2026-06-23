import ServiceManagement

/// ログイン時の自動起動を管理する。状態の真実の源はシステム（`SMAppService`）側に置き、
/// UserDefaults などへ二重に保持しない。ユーザーがシステム設定から手動で変更しても齟齬が出ない。
///
/// 注意: `SMAppService.mainApp` は署名済みの `.app` バンドルでのみ機能する。
/// `swift run` での直接実行では登録できない（`bundle.sh` で生成した .app で検証する）。
enum LaunchAtLoginService {
    /// 現在ログイン項目として有効かどうか。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// ログイン項目への登録/解除を切り替える。失敗時は例外を投げる。
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
