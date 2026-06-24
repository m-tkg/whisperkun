import Foundation
import Testing
@testable import whisperkunCore

@Suite struct VersionComparatorTests {
    @Test func 新しいパッチは新しい() {
        #expect(VersionComparator.isNewer(tag: "v1.0.1", than: "1.0.0"))
    }

    @Test func 同一バージョンは新しくない() {
        #expect(!VersionComparator.isNewer(tag: "v1.0.0", than: "1.0.0"))
        #expect(!VersionComparator.isNewer(tag: "1.0.0", than: "1.0.0"))
    }

    @Test func 古いバージョンは新しくない() {
        #expect(!VersionComparator.isNewer(tag: "v1.0.0", than: "1.0.1"))
    }

    @Test func 辞書順ではなく数値で比較する() {
        #expect(VersionComparator.isNewer(tag: "v1.10.0", than: "1.2.0"))
        #expect(!VersionComparator.isNewer(tag: "v1.2.0", than: "1.10.0"))
    }

    @Test func 要素数が異なる場合() {
        #expect(VersionComparator.isNewer(tag: "v2.0", than: "1.9.9"))
        #expect(!VersionComparator.isNewer(tag: "v1.0", than: "1.0.0"))
    }

    @Test func プレリリース接尾辞は無視する() {
        #expect(!VersionComparator.isNewer(tag: "v1.0.0-beta", than: "1.0.0"))
        #expect(VersionComparator.isNewer(tag: "v1.1.0-beta", than: "1.0.0"))
    }

    @Test func GitHubのキーをデコードできる() throws {
        let json = Data("""
        {"tag_name":"v1.2.3","html_url":"https://example.com/r","extra":1}
        """.utf8)
        let info = try JSONDecoder().decode(ReleaseInfo.self, from: json)
        #expect(info.tagName == "v1.2.3")
        #expect(info.htmlUrl == "https://example.com/r")
        #expect(info.assets.isEmpty)
        #expect(info.zipAssetURL == nil)
    }

    @Test func アセットをデコードしzipを見つける() throws {
        let json = Data("""
        {
          "tag_name": "v1.1.0",
          "html_url": "https://example.com/r",
          "assets": [
            {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
            {"name": "Whisperkun.zip", "browser_download_url": "https://example.com/Whisperkun.zip"}
          ]
        }
        """.utf8)
        let info = try JSONDecoder().decode(ReleaseInfo.self, from: json)
        #expect(info.assets.count == 2)
        #expect(info.zipAssetURL == URL(string: "https://example.com/Whisperkun.zip"))
    }
}
