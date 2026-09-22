import Foundation

/// 一次取词/翻译的取消令牌；后台取词、网络回调和主线程关闭窗口可安全共用。
public final class TranslationRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var restoreClipboard = true
    private var cancellations: [() -> Void] = []

    public init() {}

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public var allowsClipboardRestore: Bool {
        lock.lock(); defer { lock.unlock() }
        return restoreClipboard
    }

    public func onCancel(_ action: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            action()
        } else {
            cancellations.append(action)
            lock.unlock()
        }
    }

    /// 用户正在主动复制时，不允许后台事务再恢复旧剪贴板覆盖该操作。
    public func cancel(preservingClipboard: Bool = false) {
        lock.lock()
        if preservingClipboard { restoreClipboard = false }
        cancelled = true
        let actions = cancellations
        cancellations.removeAll()
        lock.unlock()
        actions.forEach { $0() }
    }
}

/// 仅在主动打开的会话中接受最新请求；A→B→A 也由令牌而非文本相等来区分。
public struct SelectionTranslationState {
    public private(set) var isOpen = false
    public private(set) var current: TranslationRequest?
    public init() {}

    public mutating func open() { close(); isOpen = true }

    public mutating func beginRequest(preservingClipboard: Bool = false) -> TranslationRequest? {
        guard isOpen else { return nil }
        current?.cancel(preservingClipboard: preservingClipboard)
        let request = TranslationRequest()
        current = request
        return request
    }

    public func accepts(_ request: TranslationRequest) -> Bool {
        isOpen && current === request && !request.isCancelled
    }

    public mutating func close() {
        current?.cancel()
        current = nil
        isOpen = false
    }
}

/// HTML 剪贴板的轻量纯文本兜底，不启动 WebKit、不加载网页资源。
public enum ClipboardHTMLText {
    public static func decode(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<(?:br\\s*/?|/?(?:p|div|li|tr|h[1-6]))\\b[^>]*>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);", options: .caseInsensitive) {
            let original = text as NSString
            let buffer = NSMutableString(string: text)
            for match in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
                let number = original.substring(with: match.range(at: 1))
                let hex = number.lowercased().hasPrefix("x")
                if let value = UInt32(hex ? String(number.dropFirst()) : number, radix: hex ? 16 : 10),
                   let scalar = UnicodeScalar(value) {
                    buffer.replaceCharacters(in: match.range, with: String(scalar))
                }
            }
            text = buffer as String
        }
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 新复制只能由本次操作后的 changeCount 变化证明，不能用“发现变化的时间”推断。
public struct ClipboardTransaction {
    public let initialCount: Int
    public private(set) var copiedCount: Int?
    public init(initialCount: Int) { self.initialCount = initialCount }

    public mutating func observe(_ count: Int) -> Bool {
        guard count != initialCount else { return false }
        if copiedCount == nil { copiedCount = count }
        return copiedCount == count
    }

    public func mayRestore(currentCount: Int) -> Bool {
        copiedCount != nil && copiedCount == currentCount
    }
}
