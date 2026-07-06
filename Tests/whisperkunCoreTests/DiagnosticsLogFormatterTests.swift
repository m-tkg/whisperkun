import Foundation
import Testing
@testable import whisperkunCore

@Suite struct DiagnosticsLogFormatterTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, ms: Int = 0) -> Date {
        var components = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
        components.nanosecond = ms * 1_000_000
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: components)!
    }

    @Test func エントリを時刻カテゴリレベル付きの1行に整形する() {
        let entries = [
            DiagnosticsLogEntry(
                date: date(2026, 7, 6, 12, 34, 56, ms: 789),
                category: "hotkey", level: "debug",
                message: "reconcile: flags=0 isDown=false"
            )
        ]
        let text = DiagnosticsLogFormatter.format(entries, timeZone: utc)
        #expect(text == "2026-07-06 12:34:56.789 [hotkey] debug: reconcile: flags=0 isDown=false\n")
    }

    @Test func 複数エントリは1行ずつ並ぶ() {
        let entries = [
            DiagnosticsLogEntry(
                date: date(2026, 7, 6, 12, 0, 0),
                category: "coordinator", level: "debug", message: "begin"
            ),
            DiagnosticsLogEntry(
                date: date(2026, 7, 6, 12, 0, 1),
                category: "transcription", level: "info", message: "phase: preparing -> listening gen=1"
            ),
        ]
        let text = DiagnosticsLogFormatter.format(entries, timeZone: utc)
        #expect(text == """
        2026-07-06 12:00:00.000 [coordinator] debug: begin
        2026-07-06 12:00:01.000 [transcription] info: phase: preparing -> listening gen=1

        """)
    }

    @Test func 空なら空文字列() {
        #expect(DiagnosticsLogFormatter.format([], timeZone: utc) == "")
    }

    @Test func タイムゾーン指定が時刻表記に反映される() {
        let entries = [
            DiagnosticsLogEntry(
                date: date(2026, 7, 6, 0, 0, 0),  // UTC 0時
                category: "hotkey", level: "debug", message: "m"
            )
        ]
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        let text = DiagnosticsLogFormatter.format(entries, timeZone: jst)
        #expect(text.hasPrefix("2026-07-06 09:00:00.000"))
    }
}
