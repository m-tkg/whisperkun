import Testing
@testable import whisperkunCore

@Suite("AudioInputDeviceSelection")
struct AudioInputDeviceSelectionTests {
    private let builtIn = AudioInputDevice(uid: "BuiltInMic", name: "MacBook Pro のマイク")
    private let usb = AudioInputDevice(uid: "USB-Mic-0001", name: "USB Microphone")

    @Test("未設定（nil）はシステム既定を意味する")
    func resolveNil() {
        #expect(AudioInputDeviceSelection.resolve(preferredUID: nil, available: [builtIn, usb]) == nil)
    }

    @Test("空文字はシステム既定にフォールバックする")
    func resolveEmpty() {
        #expect(AudioInputDeviceSelection.resolve(preferredUID: "", available: [builtIn, usb]) == nil)
    }

    @Test("接続中のデバイスはそのまま使う")
    func resolveConnected() {
        #expect(AudioInputDeviceSelection.resolve(preferredUID: usb.uid, available: [builtIn, usb]) == usb.uid)
    }

    @Test("未接続のデバイスはシステム既定にフォールバックする")
    func resolveDisconnected() {
        #expect(AudioInputDeviceSelection.resolve(preferredUID: usb.uid, available: [builtIn]) == nil)
    }

    @Test("接続中・未設定なら未接続デバイスは無い")
    func missingPreferredNone() {
        #expect(AudioInputDeviceSelection.missingPreferred(
            available: [builtIn, usb], preferredUID: usb.uid, preferredName: usb.name) == nil)
        #expect(AudioInputDeviceSelection.missingPreferred(
            available: [builtIn], preferredUID: nil, preferredName: nil) == nil)
    }

    @Test("未接続の保存デバイスは選択肢として保持する（再接続で選択が戻る）")
    func missingPreferredPresent() {
        let missing = AudioInputDeviceSelection.missingPreferred(
            available: [builtIn], preferredUID: usb.uid, preferredName: usb.name)
        #expect(missing == usb)
    }

    @Test("名前未保存の未接続デバイスは UID を表示名に使う")
    func missingPreferredWithoutName() {
        let missing = AudioInputDeviceSelection.missingPreferred(
            available: [builtIn], preferredUID: usb.uid, preferredName: nil)
        #expect(missing == AudioInputDevice(uid: usb.uid, name: usb.uid))
    }
}
