import AppKit
import SwiftUI

/// 修飾キー（右 Command/Option/Control/Shift）の組み合わせを「押して記録」する NSView。
///
/// クリックで記録モードに入り、右側の修飾キーを（複数同時でも）押す。
/// 同時に押された組み合わせの「最大集合」を捉え、すべて離した時点で確定する。
/// push-to-talk の長押し/離す挙動を保つため、対象は右側の修飾キーに限定する。
/// Escape で記録をキャンセルする。
final class HotkeyRecorderNSView: NSView {
    var modifiers: Set<HotkeyModifier> = [] { didSet { needsDisplay = true } }
    var onChange: ((Set<HotkeyModifier>) -> Void)?

    private var recording = false { didSet { needsDisplay = true } }
    /// 記録中に現在押されている右修飾キー。
    private var currentlyDown: Set<HotkeyModifier> = []
    /// 記録中に同時押しされた最大の組み合わせ。
    private var peak: Set<HotkeyModifier> = []

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 240, height: 28) }

    override func mouseDown(with event: NSEvent) {
        recording = true
        currentlyDown = []
        peak = []
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Escape で記録を中止（割り当ては変更しない）。
        if event.keyCode == 53 {
            cancelRecording()
            return
        }
        // 修飾キー以外のキーは無視（記録は継続）。
        NSSound.beep()
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return }
        // 対象は右側の修飾キーのみ。左側・非対象キーは無視。
        guard let modifier = HotkeyModifier(keyCode: event.keyCode) else { return }

        // flagsChanged は押下/解放のどちらかの遷移。現在の集合に含まれていれば解放、無ければ押下。
        if currentlyDown.contains(modifier) {
            currentlyDown.remove(modifier)
        } else {
            currentlyDown.insert(modifier)
            if currentlyDown.count > peak.count { peak = currentlyDown }
        }

        // すべて離したら、その時点の最大集合を確定する。
        if currentlyDown.isEmpty, !peak.isEmpty {
            modifiers = peak
            recording = false
            onChange?(peak)
        }
    }

    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        recording = false
        currentlyDown = []
        peak = []
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
            // 記録中に押している組み合わせを随時表示（未押下なら案内文）。
            if currentlyDown.isEmpty {
                text = "右の修飾キーを押す（複数同時可）…"
            } else {
                text = HotkeyModifier.symbols(for: currentlyDown)
            }
            color = .controlAccentColor
        } else if !modifiers.isEmpty {
            text = "\(HotkeyModifier.symbols(for: modifiers))  \(HotkeyModifier.displayName(for: modifiers))"
            color = .labelColor
        } else {
            text = "未設定"
            color = .secondaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: recording ? 12 : 13),
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let point = NSPoint(x: (bounds.width - size.width) / 2,
                            y: (bounds.height - size.height) / 2)
        attributed.draw(at: point)
    }
}

/// `HotkeyRecorderNSView` の SwiftUI ラッパー。`Set<HotkeyModifier>` をバインドする。
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var modifiers: Set<HotkeyModifier>

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.modifiers = modifiers
        view.onChange = { modifiers = $0 }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.modifiers = modifiers
    }
}
