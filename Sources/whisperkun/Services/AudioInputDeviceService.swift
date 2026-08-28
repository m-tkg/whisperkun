import CoreAudio
import Foundation
import OSLog
import whisperkunCore

private let deviceLog = Log.logger(category: "audio-device")

/// CoreAudio の HAL から音声入力デバイスを列挙・解決する。
///
/// 設定には実行のたびに変わる `AudioDeviceID` ではなく永続的な UID を保存し、
/// 録音開始時にここで `AudioDeviceID` へ解決する。
enum AudioInputDeviceService {
    /// 入力チャンネルを持つデバイス（＝マイクとして選べるもの）を列挙する。
    static func availableInputDevices() -> [AudioInputDevice] {
        inputDevices().map(\.device)
    }

    /// UID から現在の `AudioDeviceID` を解決する。未接続なら `nil`。
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.device.uid == uid }?.id
    }

    // MARK: - CoreAudio

    private struct Entry {
        let id: AudioDeviceID
        let device: AudioInputDevice
    }

    private static func inputDevices() -> [Entry] {
        allDeviceIDs().compactMap { id in
            guard hasInputChannels(id), let uid = deviceUID(id) else { return nil }
            let name = deviceName(id) ?? uid
            return Entry(id: id, device: AudioInputDevice(uid: uid, name: name))
        }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard status == noErr, size > 0 else {
            deviceLog.warning("device list size query failed: \(status, privacy: .public)")
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        guard status == noErr else {
            deviceLog.warning("device list query failed: \(status, privacy: .public)")
            return []
        }
        return ids
    }

    /// 入力スコープのストリーム構成を見て、入力チャンネルが 1 つ以上あるかを判定する。
    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }

        // AudioBufferList は可変長（末尾に mNumberBuffers 個の AudioBuffer が続く）なので
        // 生バイト列で確保してから型付きポインタとして読む。
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return false }

        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        stringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        stringProperty(id, selector: kAudioObjectPropertyName)
    }

    private static func stringProperty(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}

/// 入力デバイスの抜き差しを監視し、設定 UI の一覧を最新に保つ。
/// 設定画面の表示中だけ購読する（`start` / `stop`）。
@MainActor
final class AudioInputDeviceMonitor {
    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// デバイス構成が変わったときに `onChange` を呼ぶ。二重購読はしない。
    func start(onChange: @escaping @MainActor () -> Void) {
        guard listener == nil else { return }
        // リスナーはメインキューで受け、MainActor 隔離を回復してから UI 側へ通知する。
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { onChange() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        guard status == noErr else {
            deviceLog.warning("device listener install failed: \(status, privacy: .public)")
            return
        }
        self.listener = listener
    }

    func stop() {
        guard let listener else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }

    /// 解放時に購読が残るとメインキューへ通知が飛び続けるため、明示的に外す。
    /// `stop()`（MainActor 隔離）を呼ぶため `isolated deinit` にする。
    isolated deinit {
        stop()
    }
}
