import AppKit
import SwiftUI

/// 修飾キー（右 Command/Option/Control/Shift）を「押して記録」する NSView。
///
/// クリックで記録モードに入り、右側の修飾キーを押すと割り当てる。
/// push-to-talk の長押し/離す挙動を保つため、対象は単一の修飾キーに限定する。
/// Escape で記録をキャンセルする。
final class HotkeyRecorderNSView: NSView {
    var modifier: HotkeyModifier? { didSet { needsDisplay = true } }
    var onChange: ((HotkeyModifier) -> Void)?

    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 28) }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Escape で記録を中止（割り当ては変更しない）。
        if event.keyCode == 53 {
            recording = false
            return
        }
        // 修飾キー以外のキーは無視（記録は継続）。
        NSSound.beep()
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return }
        // flagsChanged の keyCode から右側修飾キーを判定する。左側や非対象キーは無視。
        guard let modifier = HotkeyModifier(keyCode: event.keyCode) else { return }
        self.modifier = modifier
        recording = false
        onChange?(modifier)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)

        let borderColor: NSColor = recording ? .controlAccentColor : .separatorColor
        NSColor.textBackgroundColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if recording {
            text = "キーを入力…（右の Command / Option / Control / Shift）"
            color = .controlAccentColor
        } else if let modifier {
            text = "\(modifier.symbol) \(modifier.displayName)"
            color = .labelColor
        } else {
            text = "未設定"
            color = .secondaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: recording ? 11 : 13),
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2,
                            y: (bounds.height - size.height) / 2)
        attributed.draw(at: point)
    }
}

/// `HotkeyRecorderNSView` の SwiftUI ラッパー。`HotkeyModifier?` をバインドする。
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var modifier: HotkeyModifier?

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.modifier = modifier
        view.onChange = { modifier = $0 }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.modifier = modifier
    }
}
