import AppKit
import SwiftUI

/// 録音中に画面下部へ浮かぶフローティングインジケータの内容。
struct RecordingHUDView: View {
    @Bindable var transcription: TranscriptionService

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(transcription.liveText.isEmpty ? "…" : transcription.liveText)
                    .font(.title3)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        )
    }

    private var statusLabel: String {
        switch transcription.phase {
        case .preparing: return "準備中"
        case .listening: return "認識中"
        case .failed: return "エラー"
        case .idle: return ""
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch transcription.phase {
        case .listening:
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(.green)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        case .preparing:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.red)
        case .idle:
            Image(systemName: "mic").font(.title).foregroundStyle(.secondary)
        }
    }
}

/// フローティングHUD用の `NSPanel` を管理する。全 Space・全アプリ上に表示する。
@MainActor
final class HUDController {
    private var panel: NSPanel?

    func show(_ transcription: TranscriptionService) {
        if panel != nil { return }

        let hosting = NSHostingController(rootView: RecordingHUDView(transcription: transcription))
        // SwiftUIビューにパネルサイズを追従させない（制約更新ループの回避）。
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting

        positionAtBottomCenter(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func positionAtBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 120
        )
        panel.setFrameOrigin(origin)
    }
}
