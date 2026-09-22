import AppKit
import ApplicationServices
import DailyWordCore

/// 只在串行后台队列中使用；读取目标在手势发生时固定，不扫描其他应用或旧剪贴板。
enum SelectedTextReader {
    static let syntheticCopyTag: Int64 = 0x44575452414E53
    private static let copyLock = NSLock()
    nonisolated(unsafe) private static var copyingRequest: TranslationRequest?

    static func interruptCopy() {
        copyLock.lock()
        let current = copyingRequest
        copyLock.unlock()
        current?.cancel(preservingClipboard: true)
    }

    enum Result { case text(String), empty, unavailable }

    static func accessibility(pid: pid_t, request: TranslationRequest) -> Result {
        let deadline = Date().addingTimeInterval(1.2)
        func active() -> Bool { !request.isCancelled && Date() < deadline }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard active() else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.15)
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func text(_ value: CFTypeRef?) -> String? {
            let raw = (value as? String) ?? (value as? NSAttributedString)?.string
            guard let result = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else { return nil }
            return result
        }
        let app = AXUIElementCreateApplication(pid)
        let focused = element(attribute(app, kAXFocusedUIElementAttribute))
        let window = element(attribute(app, kAXFocusedWindowAttribute))
        if let focused, attribute(focused, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
            return .empty
        }
        var explicitlyEmpty = false
        func selection(in current: AXUIElement) -> String? {
            if let selected = text(attribute(current, kAXSelectedTextAttribute)) { return selected }
            var ranges: [CFTypeRef] = []
            if let range = attribute(current, kAXSelectedTextRangeAttribute) { ranges.append(range) }
            if let multiple = attribute(current, kAXSelectedTextRangesAttribute) as? [AXValue], !multiple.isEmpty {
                ranges = multiple   // 同时暴露单区间和多区间时不重复拼接同一选区。
            }
            var parts: [String] = []
            for range in ranges where active() {
                guard CFGetTypeID(range) == AXValueGetTypeID() else { continue }
                let value = range as! AXValue
                var selectedRange = CFRange()
                guard AXValueGetType(value) == .cfRange,
                      AXValueGetValue(value, .cfRange, &selectedRange), selectedRange.location >= 0 else { continue }
                if selectedRange.length == 0 {
                    if let focused, CFEqual(current, focused) { explicitlyEmpty = true }
                    continue
                }
                guard selectedRange.length > 0 else { continue }
                var selected: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(current, kAXStringForRangeParameterizedAttribute as CFString,
                                                               value, &selected) == .success,
                   let string = text(selected) {
                    parts.append(string)
                } else if let full = attribute(current, kAXValueAttribute) as? String {
                    let full = full as NSString
                    if selectedRange.location <= full.length, selectedRange.length <= full.length - selectedRange.location {
                        parts.append(full.substring(with: NSRange(location: selectedRange.location, length: selectedRange.length)))
                    }
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        var queue = [focused, window].compactMap { $0 }.map { ($0, 0) }
        var visited: [AXUIElement] = []
        while !queue.isEmpty, active(), visited.count < 48 {
            let (current, depth) = queue.removeFirst()
            if visited.contains(where: { CFEqual($0, current) }) { continue }
            visited.append(current)
            if let string = selection(in: current), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .text(string)
            }
            guard depth < 4 else { continue }
            if let parent = element(attribute(current, kAXParentAttribute)) { queue.append((parent, depth + 1)) }
            if let children = attribute(current, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(12).map { ($0, depth + 1) })
            }
        }
        return explicitlyEmpty ? .empty : .unavailable
    }

    /// 仅尝试本次选中后的复制变化；不清空剪贴板来检测选中，更不读取已有内容作为兜底。
    static func copySelection(pid: pid_t, request: TranslationRequest) -> String? {
        guard validTarget(pid, request: request), CGPreflightPostEventAccess(),
              let source = CGEventSource(stateID: .privateState) else { return nil }
        copyLock.lock()
        copyingRequest = request
        copyLock.unlock()
        defer {
            copyLock.lock()
            if copyingRequest === request { copyingRequest = nil }
            copyLock.unlock()
        }
        let pasteboard = NSPasteboard.general
        let initialCount = pasteboard.changeCount
        var saved: [[NSPasteboard.PasteboardType: Data]] = []
        var bytes = 0
        // 保存实际数据，不保留会在剪贴板换主后失效的 NSPasteboardItem。
        for item in pasteboard.pasteboardItems ?? [] {
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                bytes += data.count
                guard bytes <= 32 * 1024 * 1024 else { return nil }
                dataByType[type] = data
            }
            saved.append(dataByType)
        }
        guard pasteboard.changeCount == initialCount, validTarget(pid, request: request) else { return nil }
        // 等待用户松开翻译快捷键，避免残留修饰键影响源应用。
        for _ in 0..<10 {
            if CGEventSource.flagsState(.combinedSessionState).intersection([.maskAlternate, .maskControl, .maskShift, .maskCommand]).isEmpty { break }
            guard validTarget(pid, request: request) else { return nil }
            Thread.sleep(forTimeInterval: 0.03)
        }
        guard validTarget(pid, request: request), pasteboard.changeCount == initialCount,
              CGEventSource.flagsState(.combinedSessionState).intersection([.maskAlternate, .maskControl, .maskShift, .maskCommand]).isEmpty else { return nil }
        var transaction = ClipboardTransaction(initialCount: initialCount)
        defer {
            // 若用户期间主动复制或剪贴板再次变化，绝不恢复旧数据覆盖它。
            if request.allowsClipboardRestore, transaction.mayRestore(currentCount: pasteboard.changeCount) {
                let items = saved.map { contents -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in contents { item.setData(data, forType: type) }
                    return item
                }
                pasteboard.clearContents()
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: isDown)
            event?.flags = .maskCommand
            event?.setIntegerValueField(.eventSourceUserData, value: syntheticCopyTag)
            event?.postToPid(pid)
        }
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.05)
            let count = pasteboard.changeCount
            if transaction.observe(count) {
                guard validTarget(pid, request: request) else { return nil }
                if let text = clipboardText(pasteboard), pasteboard.changeCount == count {
                    return text
                }
            }
            if request.isCancelled { return nil }
        }
        return nil
    }

    static func validTarget(_ pid: pid_t, request: TranslationRequest) -> Bool {
        !request.isCancelled && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// 仅在观测到用户真实 ⌘C 后调用；初始计数相同即没有新复制。
    static func newlyCopiedText(after count: Int, pid: pid_t, request: TranslationRequest) -> String? {
        for _ in 0..<15 {
            guard validTarget(pid, request: request) else { return nil }
            let pasteboard = NSPasteboard.general
            let currentCount = pasteboard.changeCount
            if currentCount != count, let text = clipboardText(pasteboard), pasteboard.changeCount == currentCount {
                return text
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    private static func clipboardText(_ pasteboard: NSPasteboard) -> String? {
        func nonempty(_ text: String?) -> String? {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }
        if let text = nonempty(pasteboard.string(forType: .string)) { return text }
        if let data = pasteboard.data(forType: .rtf), let text = nonempty(NSAttributedString(rtf: data, documentAttributes: nil)?.string) { return text }
        if let data = pasteboard.data(forType: .rtfd), let text = nonempty(NSAttributedString(rtfd: data, documentAttributes: nil)?.string) { return text }
        if let data = pasteboard.data(forType: .html),
           let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
           let text = nonempty(ClipboardHTMLText.decode(html)) { return text }
        return nil
    }
}
