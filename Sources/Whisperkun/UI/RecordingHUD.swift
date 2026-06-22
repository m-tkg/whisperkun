import AppKit
import Observation
import SwiftUI

/// HUD 固有の表示状態（録音以外の進行表示）。AI整形中などに使う。
@MainActor
@Observable
final class HUDState {
    /// AI整形が進行中か。true の間はスピナーを表示する。
    var isFormatting = false
}

/// 録音中に画面下部へ浮かぶフローティングインジケータの内容。
struct RecordingHUDView: View {
    @Bindable var transcription: TranscriptionService
    @Bindable var state: HUDState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
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
        if state.isFormatting { return "AIで整形中" }
        switch transcription.phase {
        case .preparing: return "準備中"
        case .listening: return "認識中"
        case .failed: return "エラー"
        case .idle: return ""
        }
    }

    /// 状態ごとに色を変えて一目で区別できるようにする。
    private var statusColor: Color {
        if state.isFormatting { return .purple }
        switch transcription.phase {
        case .listening: return .green
        case .preparing: return .secondary
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        // 整形中は録音フェーズに関わらず AI 整形アイコンを優先表示する（認識中と区別）。
        if state.isFormatting {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(.purple)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        } else {
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
}

/// フローティングHUD用の `NSPanel` を管理する。全 Space・全アプリ上に表示する。
@MainActor
final class HUDController {
    private var panel: NSPanel?

    /// HUD の表示状態。AI整形中フラグなどを保持する（録音状態は TranscriptionService）。
    let state = HUDState()

    func show(_ transcription: TranscriptionService) {
        if panel != nil { return }

        let hosting = NSHostingController(rootView: RecordingHUDView(transcription: transcription, state: state))
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
        state.isFormatting = false
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
