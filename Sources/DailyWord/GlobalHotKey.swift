import Carbon.HIToolbox
import Foundation

// 全局热键最近触发时间戳（主线程访问，Carbon 回调与 NSView keyDown 均在主线程）
private var hotKeyFireTimes: [UInt32: Date] = [:]

/// 记录某热键刚被全局触发（同步调用，须先于面板内 keyDown 检查）
func markHotKeyFired(_ id: UInt32) {
    hotKeyFireTimes[id] = Date()
}

/// 该热键是否在近期（0.3s）被全局触发过
func hotKeyRecentlyFired(_ id: UInt32) -> Bool {
    guard let t = hotKeyFireTimes[id] else { return false }
    return Date().timeIntervalSince(t) < 0.3
}

/// Carbon 全局热键封装（RegisterEventHotKey 无需辅助功能权限）
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void
    private let id: UInt32
    /// 长按重复间隔（nil = 不重复，如开关类动作）
    private let repeatInterval: TimeInterval?
    private var repeatTimer: Timer?

    /// - Parameters:
    ///   - id: 热键唯一标识（同一进程内不可重复）
    ///   - keyCode: 虚拟键码，如 kVK_ANSI_D
    ///   - modifiers: Carbon 修饰键，如 optionKey
    ///   - repeatInterval: 长按时重复执行间隔（移动面板/透明度等连续动作）；nil 表示按下只执行一次
    init?(id: UInt32, keyCode: Int, modifiers: Int, repeatInterval: TimeInterval? = nil,
          callback: @escaping () -> Void) {
        self.callback = callback
        self.id = id
        self.repeatInterval = repeatInterval

        // 同时监听按下与松开，实现长按重复
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                // 注意：InstallEventHandler 回调签名是 (EventHandlerCallRef, EventRef, userData)
                // 第一个参数是调用引用，第二个参数才是事件（EventRef）！
                guard let userData, let event else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // 读取本次触发的事件热键 ID；仅 ID 匹配才执行回调，
                // 否则所有热键处理器都会响应同一个事件（表现为“按什么都触发某个动作”）
                var firedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &firedID
                )
                guard status == noErr, firedID.id == hotKey.id else {
                    // 未匹配：必须返回 eventNotHandledErr，让事件继续传递给下一个处理器。
                    // 若返回 noErr，Carbon 会认为事件已处理，后面的处理器（真正的匹配者）不再被调用。
                    return OSStatus(eventNotHandledErr)
                }
                let kind = GetEventKind(event)
                if kind == UInt32(kEventHotKeyPressed) {
                    markHotKeyFired(hotKey.id)   // 同步打标记，供面板内去重
                    hotKey.pressed()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    hotKey.released()
                }
                return noErr   // 已处理
            },
            2, &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4457_4448), id: id) // "DWHD"
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            return nil
        }
    }

    /// 按下：立即执行一次；若是可重复动作，先延迟 0.15s（区分单击）再开始快速重复
    private var lastNonRepeatFireTime: TimeInterval = 0

    private func pressed() {
        guard let repeatInterval else {
            // 非重复动作去重：同一热键 0.5s 内只触发一次（防系统重复回调导致"开→关"）
            let now = Date().timeIntervalSinceReferenceDate
            guard now - lastNonRepeatFireTime > 0.5 else { return }
            lastNonRepeatFireTime = now
            callback()
            return
        }
        callback()   // 单击：立即执行一次
        repeatTimer?.invalidate()
        // 首次延迟 0.15s：单击（<0.15s 松开）不会触发第二次，长按才开始重复
        let first = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.callback()
            self.repeatTimer?.invalidate()
            let fast = Timer(timeInterval: repeatInterval, repeats: true) { [weak self] _ in
                self?.callback()
            }
            RunLoop.main.add(fast, forMode: .common)
            self.repeatTimer = fast
        }
        RunLoop.main.add(first, forMode: .common)
        repeatTimer = first
    }

    /// 松开：停止重复
    private func released() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    deinit {
        repeatTimer?.invalidate()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
