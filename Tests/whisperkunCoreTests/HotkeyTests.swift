import Testing
@testable import whisperkunCore

@Suite struct HotkeyModifierTests {
    // deviceMask は IOKit の NX_DEVICEL*/R*KEYMASK の写し。移設時の写し間違いを
    // 検出するため、期待値を数値リテラルで明示する。
    @Test func deviceMaskはIOKitのデバイスマスクと一致する() {
        #expect(HotkeyModifier.leftControl.deviceMask == 0x0000_0001)
        #expect(HotkeyModifier.leftShift.deviceMask == 0x0000_0002)
        #expect(HotkeyModifier.rightShift.deviceMask == 0x0000_0004)
        #expect(HotkeyModifier.leftCommand.deviceMask == 0x0000_0008)
        #expect(HotkeyModifier.rightCommand.deviceMask == 0x0000_0010)
        #expect(HotkeyModifier.leftOption.deviceMask == 0x0000_0020)
        #expect(HotkeyModifier.rightOption.deviceMask == 0x0000_0040)
        #expect(HotkeyModifier.rightControl.deviceMask == 0x0000_2000)
    }

    @Test func 仮想キーコードから修飾キーを判定する() {
        #expect(HotkeyModifier(keyCode: 54) == .rightCommand)
        #expect(HotkeyModifier(keyCode: 55) == .leftCommand)
        #expect(HotkeyModifier(keyCode: 56) == .leftShift)
        #expect(HotkeyModifier(keyCode: 58) == .leftOption)
        #expect(HotkeyModifier(keyCode: 59) == .leftControl)
        #expect(HotkeyModifier(keyCode: 60) == .rightShift)
        #expect(HotkeyModifier(keyCode: 61) == .rightOption)
        #expect(HotkeyModifier(keyCode: 62) == .rightControl)
    }

    @Test func 非修飾キーのキーコードはnil() {
        #expect(HotkeyModifier(keyCode: 0) == nil)    // A
        #expect(HotkeyModifier(keyCode: 53) == nil)   // Escape
        #expect(HotkeyModifier(keyCode: 57) == nil)   // Caps Lock（対象外）
        #expect(HotkeyModifier(keyCode: 63) == nil)   // Fn（対象外）
    }

    @Test func 表示順は修飾キーの慣習順で同種は左が先() {
        let sorted = HotkeyModifier.allCases.sorted { $0.sortOrder < $1.sortOrder }
        #expect(sorted == [
            .leftControl, .rightControl,
            .leftOption, .rightOption,
            .leftShift, .rightShift,
            .leftCommand, .rightCommand,
        ])
    }

    @Test func 集合のdeviceマスクは論理和になる() {
        #expect(HotkeyModifier.combinedMask([]) == 0)
        #expect(HotkeyModifier.combinedMask([.leftShift]) == 0x0000_0002)
        #expect(HotkeyModifier.combinedMask([.leftShift, .rightCommand]) == 0x0000_0012)
        #expect(HotkeyModifier.combinedMask(Set(HotkeyModifier.allCases)) == 0x0000_207F)
    }

    @Test func rawValueはUserDefaults互換のまま() {
        // 保存済み設定（stringArray）と互換を保つため、rawValue は変えない。
        #expect(HotkeyModifier.leftControl.rawValue == "leftControl")
        #expect(HotkeyModifier.rightCommand.rawValue == "rightCommand")
        #expect(HotkeyMode.pushToTalk.rawValue == "pushToTalk")
        #expect(HotkeyMode.toggle.rawValue == "toggle")
    }
}

@Suite struct HotkeyModifierMigrationTests {
    @Test func 新キーがあればそれを採用する() {
        let result = HotkeyModifierMigration.resolve(
            newRawValues: ["leftOption", "rightCommand"], legacySingleRawValue: nil)
        #expect(result == [.leftOption, .rightCommand])
    }

    @Test func 新キーの不正な生値は無視する() {
        let result = HotkeyModifierMigration.resolve(
            newRawValues: ["leftOption", "flux"], legacySingleRawValue: nil)
        #expect(result == [.leftOption])
    }

    @Test func 新キーがあれば旧キーは見ない() {
        let result = HotkeyModifierMigration.resolve(
            newRawValues: ["leftShift"], legacySingleRawValue: "rightCommand")
        #expect(result == [.leftShift])
    }

    @Test func 新キーが空配列でも採用し旧キーへは戻らない() {
        // 「明示的に空を保存した」状態。旧キーへフォールバックすると設定解除が効かなくなる。
        let result = HotkeyModifierMigration.resolve(
            newRawValues: [], legacySingleRawValue: "rightCommand")
        #expect(result.isEmpty)
    }

    @Test func 旧・単一キー設定から移行する() {
        let result = HotkeyModifierMigration.resolve(
            newRawValues: nil, legacySingleRawValue: "leftOption")
        #expect(result == [.leftOption])
    }

    @Test func 旧キーが不正なら空() {
        let result = HotkeyModifierMigration.resolve(
            newRawValues: nil, legacySingleRawValue: "flux")
        #expect(result.isEmpty)
    }

    @Test func どちらも無ければ空() {
        let result = HotkeyModifierMigration.resolve(newRawValues: nil, legacySingleRawValue: nil)
        #expect(result.isEmpty)
    }
}
