import AppKit

/// フォーカス中のアプリへテキストを挿入する。
///
/// クリップボードへ一時的に書き込み、Cmd+V を合成して貼り付けた後、
/// 元のクリップボード内容を復元する。アクセシビリティ権限が前提。
@MainActor
final class TextInsertionService {
    /// 貼り付け後にクリップボードを復元するまでの待ち時間。
    /// 貼り付け先アプリが Cmd+V を処理し終える猶予を与える。
    private let restoreDelay: Duration = .milliseconds(250)

    func insert(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let saved = savedItems(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        postPasteShortcut()

        // 復元は貼り付け完了を待ってから行う。
        Task { [restoreDelay] in
            try? await Task.sleep(for: restoreDelay)
            restore(saved, to: pasteboard)
        }
    }

    /// 既存のクリップボード項目を型ごと退避する（テキスト以外も極力保持）。
    private func savedItems(from pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    private func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    /// Cmd+V のキーイベントを合成して送出する。
    private func postPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // "v"

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
