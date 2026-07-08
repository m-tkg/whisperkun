import Foundation
import KunUpdateKit

/// 公開 GitHub API（api.github.com）から最新リリース情報を取得する。
/// public リポジトリのため認証は不要。zip のダウンロードは kunkit の `SelfUpdater`
/// （内部で `ReleaseDownloader`）が担うため、ここは取得のみを持つ。
struct UpdateService {
    static let repoFullName = "m-tkg/whisperkun"
    private static let userAgent = "whisperkun"

    enum ServiceError: LocalizedError {
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .decodeFailed:
                return String(localized: "リリース情報の解析に失敗しました。")
            }
        }
    }

    /// 最新リリース情報を取得する。
    /// HTTP 部分は kunkit の ETag 条件付き取得（304 は GitHub のレート制限を消費しない）。
    /// レート制限時は `GitHubReleaseFetcher.RateLimitedError`（リセット時刻付き文言）が投げられる。
    func fetchLatestRelease() async throws -> ReleaseInfo {
        let fetcher = GitHubReleaseFetcher(repoFullName: Self.repoFullName, userAgent: Self.userAgent)
        let data = try await fetcher.fetchLatestReleaseData()
        guard let release = try? JSONDecoder().decode(ReleaseInfo.self, from: data) else {
            throw ServiceError.decodeFailed
        }
        return release
    }
}
