import CoreGraphics
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

    @Test func keyCodeは仮想キーコードの逆引きになる() {
        #expect(HotkeyModifier.rightCommand.keyCode == 54)
        #expect(HotkeyModifier.leftCommand.keyCode == 55)
        #expect(HotkeyModifier.leftShift.keyCode == 56)
        #expect(HotkeyModifier.leftOption.keyCode == 58)
        #expect(HotkeyModifier.leftControl.keyCode == 59)
        #expect(HotkeyModifier.rightShift.keyCode == 60)
        #expect(HotkeyModifier.rightOption.keyCode == 61)
        #expect(HotkeyModifier.rightControl.keyCode == 62)
    }

    @Test func keyCodeとinitはラウンドトリップする() {
        for modifier in HotkeyModifier.allCases {
            #expect(HotkeyModifier(keyCode: modifier.keyCode) == modifier)
        }
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

    // classMask は CGEventFlags の写し（Core は CoreGraphics 非依存のため数値リテラル）。
    // 写し間違いを SDK 値との突き合わせで検出する。
    @Test func classMaskはCGEventFlagsのクラスマスクと一致する() {
        #expect(HotkeyModifier.leftControl.classMask == CGEventFlags.maskControl.rawValue)
        #expect(HotkeyModifier.rightControl.classMask == CGEventFlags.maskControl.rawValue)
        #expect(HotkeyModifier.leftShift.classMask == CGEventFlags.maskShift.rawValue)
        #expect(HotkeyModifier.rightShift.classMask == CGEventFlags.maskShift.rawValue)
        #expect(HotkeyModifier.leftOption.classMask == CGEventFlags.maskAlternate.rawValue)
        #expect(HotkeyModifier.rightOption.classMask == CGEventFlags.maskAlternate.rawValue)
        #expect(HotkeyModifier.leftCommand.classMask == CGEventFlags.maskCommand.rawValue)
        #expect(HotkeyModifier.rightCommand.classMask == CGEventFlags.maskCommand.rawValue)
    }

    @Test func classDeviceMaskは同クラス左右のdeviceMaskの論理和になる() {
        for modifier in HotkeyModifier.allCases {
            let siblings = HotkeyModifier.allCases.filter { $0.classMask == modifier.classMask }
            let expected = siblings.reduce(UInt64(0)) { $0 | $1.deviceMask }
            #expect(modifier.classDeviceMask == expected)
        }
    }

    @Test func 集合のクラスマスクは論理和になる() {
        #expect(HotkeyModifier.combinedClassMask([]) == 0)
        #expect(HotkeyModifier.combinedClassMask([.leftControl]) == 0x0004_0000)
        #expect(HotkeyModifier.combinedClassMask([.leftControl, .rightControl]) == 0x0004_0000)
        #expect(
            HotkeyModifier.combinedClassMask([.leftControl, .leftShift]) == 0x0004_0000 | 0x0002_0000)
    }

    @Test func rawValueはUserDefaults互換のまま() {
        // 保存済み設定（stringArray）と互換を保つため、rawValue は変えない。
        #expect(HotkeyModifier.leftControl.rawValue == "leftControl")
        #expect(HotkeyModifier.rightCommand.rawValue == "rightCommand")
        #expect(HotkeyMode.pushToTalk.rawValue == "pushToTalk")
        #expect(HotkeyMode.toggle.rawValue == "toggle")
    }
}

@Suite struct HotkeyFlagsEvaluatorTests {
    // CGEventFlags の写し（テスト内の可読性用）。
    private let maskControl: UInt64 = 0x0004_0000
    private let maskShift: UInt64 = 0x0002_0000
    private let maskAlphaShift: UInt64 = 0x0001_0000  // Caps Lock（LED 状態）
    private let leftControlDevice: UInt64 = 0x0000_0001
    private let rightControlDevice: UInt64 = 0x0000_2000
    private let leftShiftDevice: UInt64 = 0x0000_0002

    @Test func 空集合は常にfalse() {
        #expect(!HotkeyFlagsEvaluator.isDown(flags: 0, modifiers: []))
        #expect(!HotkeyFlagsEvaluator.isDown(flags: .max, modifiers: []))
    }

    @Test func 物理キーの押下と解放を判定する() {
        let mods: Set<HotkeyModifier> = [.leftControl]
        #expect(HotkeyFlagsEvaluator.isDown(flags: maskControl | leftControlDevice, modifiers: mods))
        #expect(!HotkeyFlagsEvaluator.isDown(flags: 0, modifiers: mods))
        // device ビット単独でも従来どおり押下扱い（後方互換）。
        #expect(HotkeyFlagsEvaluator.isDown(flags: leftControlDevice, modifiers: mods))
    }

    @Test func 左右の誤検出を防ぐ() {
        // 左 Control 選択中に物理の右 Control → 右 device ビットが立つのでフォールバック不成立。
        #expect(!HotkeyFlagsEvaluator.isDown(
            flags: maskControl | rightControlDevice, modifiers: [.leftControl]))
        #expect(!HotkeyFlagsEvaluator.isDown(
            flags: maskControl | leftControlDevice, modifiers: [.rightControl]))
        // 左右同時押しは左選択でも成立。
        #expect(HotkeyFlagsEvaluator.isDown(
            flags: maskControl | leftControlDevice | rightControlDevice, modifiers: [.leftControl]))
    }

    @Test func リマップ由来のクラスマスクのみでも押下扱い() {
        // システム設定で Caps Lock→Control: maskControl だけ立ち device ビットが無い。
        #expect(HotkeyFlagsEvaluator.isDown(flags: maskControl, modifiers: [.leftControl]))
        #expect(HotkeyFlagsEvaluator.isDown(flags: maskControl, modifiers: [.rightControl]))
        // Caps Lock LED（maskAlphaShift）が同時に立っていても影響しない。
        #expect(HotkeyFlagsEvaluator.isDown(
            flags: maskControl | maskAlphaShift, modifiers: [.leftControl]))
        // 通常押下に余剰ビットが混ざっても影響しない。
        #expect(HotkeyFlagsEvaluator.isDown(
            flags: maskControl | leftControlDevice | maskAlphaShift, modifiers: [.leftControl]))
        // クラス違いは不成立（Shift 選択中に Control リマップ）。
        #expect(!HotkeyFlagsEvaluator.isDown(flags: maskControl, modifiers: [.leftShift]))
    }

    @Test func 複数修飾キーはANDで判定する() {
        let mods: Set<HotkeyModifier> = [.leftControl, .leftShift]
        #expect(HotkeyFlagsEvaluator.isDown(
            flags: maskControl | maskShift | leftControlDevice | leftShiftDevice, modifiers: mods))
        #expect(!HotkeyFlagsEvaluator.isDown(
            flags: maskControl | leftControlDevice, modifiers: mods))
        // Control はリマップ・Shift は物理の混在。
        #expect(HotkeyFlagsEvaluator.isDown(
            flags: maskControl | maskShift | leftShiftDevice, modifiers: mods))
        // 左 Shift 物理＋右 Control 物理（左 Control 選択）→ 不成立。
        #expect(!HotkeyFlagsEvaluator.isDown(
            flags: maskControl | maskShift | leftShiftDevice | rightControlDevice, modifiers: mods))
    }

    @Test func 同クラス左右両選択の挙動() {
        let mods: Set<HotkeyModifier> = [.leftControl, .rightControl]
        // 両 device ビット → 成立（従来どおり）。
        #expect(HotkeyFlagsEvaluator.isDown(
            flags: maskControl | leftControlDevice | rightControlDevice, modifiers: mods))
        // 片側のみ → 不成立（従来どおり AND）。
        #expect(!HotkeyFlagsEvaluator.isDown(
            flags: maskControl | leftControlDevice, modifiers: mods))
        // リマップ由来（クラスのみ）→ 左右区別不能のため押下扱い（仕様）。
        #expect(HotkeyFlagsEvaluator.isDown(flags: maskControl, modifiers: mods))
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
