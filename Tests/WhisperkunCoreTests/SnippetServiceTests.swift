import Foundation
import Testing
@testable import WhisperkunCore

@Suite struct SnippetServiceTests {
    let service = SnippetService()
    let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    /// 2026-06-22 09:05:00 JST の固定日時。
    private var fixedDate: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 22
        c.hour = 9; c.minute = 5; c.second = 0
        c.timeZone = timeZone
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test func 日付トークンを展開する() {
        let result = service.expand("今日は{{DATE}}", snippets: [:], now: fixedDate, timeZone: timeZone)
        #expect(result == "今日は2026-06-22")
    }

    @Test func 時刻トークンを展開する() {
        let result = service.expand("now {{TIME}}", snippets: [:], now: fixedDate, timeZone: timeZone)
        #expect(result == "now 09:05")
    }

    @Test func 日時トークンを展開する() {
        let result = service.expand("{{DATETIME}}", snippets: [:], now: fixedDate, timeZone: timeZone)
        #expect(result == "2026-06-22 09:05")
    }

    @Test func カスタムスニペットを展開する() {
        let result = service.expand("署名: {{sig}}", snippets: ["sig": "高木"], now: fixedDate, timeZone: timeZone)
        #expect(result == "署名: 高木")
    }

    @Test func 未知のトークンはそのまま残す() {
        let result = service.expand("{{XYZ}}", snippets: [:], now: fixedDate, timeZone: timeZone)
        #expect(result == "{{XYZ}}")
    }
}
