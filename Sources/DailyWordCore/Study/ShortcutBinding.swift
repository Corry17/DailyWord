import Foundation

/// 可测试的按键值；修饰键采用 Carbon 的四个核心位，避免无效导入值进入系统 API。
public struct ShortcutBinding: Equatable {
    public static let modifierMask = 0x0100 | 0x0200 | 0x0800 | 0x1000
    public static let none = ShortcutBinding(keyCode: -1, modifiers: 0)
    public var keyCode: Int
    public var modifiers: Int

    public init(keyCode: Int, modifiers: Int) {
        if keyCode == -1 && modifiers == 0 || (0...127).contains(keyCode) && modifiers >= 0 && modifiers & ~Self.modifierMask == 0 {
            self.keyCode = keyCode
            self.modifiers = modifiers
        } else {
            self.keyCode = -1
            self.modifiers = 0
        }
    }

    public init?(storage: String) {
        let parts = storage.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let key = Int(parts[0]), let mods = Int(parts[1]) else { return nil }
        self.init(keyCode: key, modifiers: mods)
        guard keyCode == key, modifiers == mods else { return nil }
    }

    public var isSet: Bool { (0...127).contains(keyCode) && modifiers >= 0 && modifiers & ~Self.modifierMask == 0 }
    public var storage: String { "\(keyCode):\(modifiers)" }
    public func matches(keyCode: Int, modifiers: Int) -> Bool {
        isSet && self.keyCode == keyCode && self.modifiers == modifiers
    }

    /// 缺失条目沿用默认值，用户保存的条目优先；历史重复绑定按固定顺序消除。
    public static func restoring<Action: Hashable>(defaults: [Action: Self], stored: [Action: String],
                                                   order: [Action]) -> [Action: Self] {
        var result = defaults
        for action in order {
            guard let value = stored[action], let binding = Self(storage: value) else { continue }
            result = assigning(binding, to: action, in: result)
        }
        return result
    }

    /// 冲突动作保留显式“未设置”，不能删键，否则重启时会被默认值恢复。
    public static func assigning<Action: Hashable>(_ binding: Self, to action: Action,
                                                   in existing: [Action: Self]) -> [Action: Self] {
        var result = existing
        if binding.isSet {
            for (other, value) in existing where other != action && value == binding {
                result[other] = Self.none
            }
        }
        result[action] = binding
        return result
    }
}
