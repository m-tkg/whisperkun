// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "whisperkun",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        // 純粋ロジック（テスト対象）: AppKit/AVFoundation/Speech/SwiftData に依存しない計算・モデル
        .target(
            name: "whisperkunCore"
        ),
        // 実行ファイル本体: メニューバー常駐・ホットキー・音声認識・後処理・設定UI
        .executableTarget(
            name: "whisperkun",
            dependencies: ["whisperkunCore"]
        ),
        .testTarget(
            name: "whisperkunCoreTests",
            dependencies: ["whisperkunCore"]
        ),
    ]
)
