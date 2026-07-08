// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "whisperkun",
    platforms: [
        .macOS("26.0")
    ],
    dependencies: [
        // kun シリーズ共通の共有ライブラリ。
        // - KunIntegrationBridge: kuntraykun 連携（プロトコル定数・Bridge・アイコン/メニュー書き出し）
        // - KunUpdateKit: 更新チェック（ETag 条件付き取得・ReleaseInfo/VersionComparator・チェック間隔・zip DL）
        // - KunSupport: 共通ユーティリティ（BundleIdentity ほか）
        // - KunAppKit: メニューバー常駐アプリ共通（SelfUpdater・多重起動ガード ほか）
        // 1.3.0: KunSupport / KunAppKit と ReleaseDownloader の追加。
        // Package.resolved を追跡していないため、必要な最低バージョンをここで保証する。
        .package(url: "https://github.com/m-tkg/kunkit.git", from: "1.3.0")
    ],
    targets: [
        // 純粋ロジック（テスト対象）: AppKit/AVFoundation/Speech/SwiftData に依存しない計算・モデル
        .target(
            name: "whisperkunCore"
        ),
        // 実行ファイル本体: メニューバー常駐・ホットキー・音声認識・後処理・設定UI
        .executableTarget(
            name: "whisperkun",
            dependencies: [
                "whisperkunCore",
                .product(name: "KunIntegrationBridge", package: "kunkit"),
                .product(name: "KunUpdateKit", package: "kunkit"),
                .product(name: "KunSupport", package: "kunkit"),
                .product(name: "KunAppKit", package: "kunkit"),
            ]
        ),
        .testTarget(
            name: "whisperkunCoreTests",
            dependencies: ["whisperkunCore"]
        ),
    ]
)
