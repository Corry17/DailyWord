import SwiftUI
import AppKit

/// 拉伸光标集合（边缘/四角）
enum ResizeCursors {
    /// 边缘检测宽度（光标与手动 resize 共用，14px 便于抓取）
    static let resizeEdge: CGFloat = 14

    /// 容器视图：系统光标机制（静止时也生效）
    static func applyCursorRects(in view: NSView) {
        let b = view.bounds
        let e = resizeEdge
        view.addCursorRect(NSRect(x: 0, y: e, width: e, height: b.height - 2 * e), cursor: .resizeLeftRight)
        view.addCursorRect(NSRect(x: b.width - e, y: e, width: e, height: b.height - 2 * e), cursor: .resizeLeftRight)
        view.addCursorRect(NSRect(x: e, y: 0, width: b.width - 2 * e, height: e), cursor: .resizeUpDown)
        view.addCursorRect(NSRect(x: e, y: b.height - e, width: b.width - 2 * e, height: e), cursor: .resizeUpDown)
        view.addCursorRect(NSRect(x: 0, y: 0, width: e, height: e), cursor: .resizeLeftRight)
        view.addCursorRect(NSRect(x: b.width - e, y: b.height - e, width: e, height: e), cursor: .resizeLeftRight)
        view.addCursorRect(NSRect(x: b.width - e, y: 0, width: e, height: e), cursor: .resizeLeftRight)
        view.addCursorRect(NSRect(x: 0, y: b.height - e, width: e, height: e), cursor: .resizeLeftRight)
    }

    /// 点所在位置对应的拉伸光标（全部用系统标准光标，保证显示），非边缘返回 nil
    static func cursorFor(point: NSPoint, in bounds: NSRect) -> NSCursor? {
        let e = resizeEdge
        let nearLeft = point.x <= e
        let nearRight = point.x >= bounds.width - e
        let nearTop = point.y >= bounds.height - e
        let nearBottom = point.y <= e
        if nearLeft || nearRight {
            return .resizeLeftRight
        } else if nearTop || nearBottom {
            return .resizeUpDown
        }
        return nil
    }
}

/// 容器视图：为边缘/四角注册拉伸光标 rect（系统在鼠标移动/静止时自动生效）
final class ResizeCursorContainerView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        ResizeCursors.applyCursorRects(in: self)
    }

    /// 鼠标移动时立即设置边缘拉伸光标（弥补系统光标 rects 可能被覆盖的情况）
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        // .cursorUpdate 关键：让系统光标机制正规回调本视图的 cursorUpdate
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let cursor = ResizeCursors.cursorFor(point: point, in: bounds) {
            cursor.set()
        } else {
            // 移出边缘：恢复箭头（防止光标卡在拉伸形态）
            NSCursor.arrow.set()
        }
        super.mouseMoved(with: event)
    }

    /// 系统光标机制的最终入口：鼠标移动时系统调用视图链的 cursorUpdate，
    /// 在这里设置边缘拉伸光标（不会被后续机制覆盖）
    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let cursor = ResizeCursors.cursorFor(point: point, in: bounds) {
            cursor.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }
}

/// 不注册光标 rects 的文本视图：避免 NSTextView 的 I-beam 光标覆盖边缘拉伸光标
final class NoCursorTextView: NSTextView {
    override func resetCursorRects() {
        // 不调用 super：不注册 I-beam 光标，让容器视图的边缘拉伸光标生效
    }

    override func cursorUpdate(with event: NSEvent) {
        // 不设置 I-beam；手动冒泡到 next responder（NSTextView 默认实现不冒泡，
        // 会拦截容器视图的边缘拉伸光标）
        nextResponder?.cursorUpdate(with: event)
    }
}

/// 可拉伸的划词翻译面板：仅顶栏可拖动位置，边缘/四角拉伸（硬性限制尺寸），到边界后完全固定
final class ResizableTranslatePanel: NSPanel {
    /// 尺寸限定（与 AppServices 的 minSize/maxSize 保持一致）
    static let minWidth: CGFloat = 340
    static let minHeight: CGFloat = 320
    static let maxWidth: CGFloat = 900
    static let maxHeight: CGFloat = 800

    /// 顶栏高度（仅顶栏可拖动移动位置）
    private let topBarHeight: CGFloat = 30

    /// 顶栏拖动状态
    private var dragStart: (windowOrigin: NSPoint, mouse: NSPoint)?

    /// 手动 resize 状态（边缘拖动改变窗口大小）
    private enum ResizeEdge {
        case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    }
    private var resizeState: (startFrame: NSRect, startMouse: NSPoint, edge: ResizeEdge)?

    /// 检测点所在的边缘（14px 宽，光标与手动 resize 共用）
    private func edgeAt(point: NSPoint, bounds: NSRect) -> ResizeEdge? {
        let e = ResizeCursors.resizeEdge
        let left = point.x <= e
        let right = point.x >= bounds.width - e
        let top = point.y >= bounds.height - e
        let bottom = point.y <= e
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left { return .left }
        if right { return .right }
        if top { return .top }
        if bottom { return .bottom }
        return nil
    }

    /// 按拖动方向计算新 frame（尺寸与位置都随鼠标；setFrame 会做最小/最大钳制）
    private func frameForResize(edge: ResizeEdge, startFrame: NSRect, mouse: NSPoint, startMouse: NSPoint) -> NSRect {
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        var f = startFrame
        switch edge {
        case .left:
            f.origin.x = startFrame.origin.x + dx
            f.size.width = startFrame.width - dx
        case .right:
            f.size.width = startFrame.width + dx
        case .bottom:
            f.origin.y = startFrame.origin.y + dy
            f.size.height = startFrame.height - dy
        case .top:
            f.size.height = startFrame.height + dy
        case .topLeft:
            f.origin.x = startFrame.origin.x + dx
            f.size.width = startFrame.width - dx
            f.size.height = startFrame.height + dy
        case .topRight:
            f.size.width = startFrame.width + dx
            f.size.height = startFrame.height + dy
        case .bottomLeft:
            f.origin.x = startFrame.origin.x + dx
            f.size.width = startFrame.width - dx
            f.origin.y = startFrame.origin.y + dy
            f.size.height = startFrame.height - dy
        case .bottomRight:
            f.size.width = startFrame.width + dx
            f.size.height = startFrame.height - dy
        }
        return f
    }

    // MARK: - 尺寸持久化（重新打开时恢复上一次大小）

    static func savedSize() -> NSSize? {
        let defaults = UserDefaults.standard
        let w = defaults.double(forKey: "translatePanelWidth")
        let h = defaults.double(forKey: "translatePanelHeight")
        guard w > 0, h > 0 else { return nil }
        return NSSize(width: w, height: h)
    }

    static func saveSize(_ size: NSSize) {
        UserDefaults.standard.set(size.width, forKey: "translatePanelWidth")
        UserDefaults.standard.set(size.height, forKey: "translatePanelHeight")
    }

    static func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "translatePanelOriginSaved") else { return nil }
        return NSPoint(x: defaults.double(forKey: "translatePanelOriginX"),
                       y: defaults.double(forKey: "translatePanelOriginY"))
    }

    static func saveOrigin(_ origin: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "translatePanelOriginSaved")
        defaults.set(origin.x, forKey: "translatePanelOriginX")
        defaults.set(origin.y, forKey: "translatePanelOriginY")
    }

    /// 重置为初始大小（以右上角为不变点）
    func resetToDefaultSize() {
        let defaultSize = NSSize(width: Self.minWidth, height: Self.minHeight)
        Self.saveSize(defaultSize)
        // macOS 坐标原点在左下：保持右上角 (maxX, maxY) 不动
        let newOrigin = NSPoint(x: frame.maxX - defaultSize.width,
                                y: frame.maxY - defaultSize.height)
        Self.saveOrigin(newOrigin)
        setFrame(NSRect(origin: newOrigin, size: defaultSize), display: true)
    }

    // MARK: - 鼠标光标监控（边缘拉伸光标）

    private var mouseMonitor: Any?
    private var cursorTimer: Timer?
    private var cursorLogCounter = 0

    /// 调试日志（写入 /tmp/dailyword_cursor.log）
    private func logCursor(_ msg: String) {
        let line = "[光标] \(Date()) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: "/tmp/dailyword_cursor.log") {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/dailyword_cursor.log"))
        }
    }

    /// 首次显示时启动监控：local monitor（窗口事件）+ Timer 轮询（拖动/任何时刻兜底）
    override func orderFrontRegardless() {
        startMouseMonitor()
        super.orderFrontRegardless()
    }

    private func startMouseMonitor() {
        logCursor("启动监控")
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, event.window === self, self.isVisible else { return event }
            let point = event.locationInWindow
            let bounds = self.contentView?.bounds ?? .zero
            // 鼠标移到边缘（用户要调整大小）：若应用未激活则激活——
            // NSCursor.set() 只在应用激活时有效（点击别的程序后失活会导致光标失效）
            if !NSApp.isActive, ResizeCursors.cursorFor(point: point, in: bounds) != nil {
                NSApp.activate(ignoringOtherApps: true)
            }
            if let cursor = ResizeCursors.cursorFor(point: point, in: bounds) {
                cursor.set()
                // 吞掉事件：阻止视图层 cursorUpdate 覆盖拉伸光标（用户验证有效的版本）
                return nil
            } else if self.frame.contains(NSEvent.mouseLocation) {
                // 窗口内非边缘：恢复默认光标（防止拉伸光标卡住）
                NSCursor.arrow.set()
            }
            return event
        }
        // Timer 轮询兜底：不依赖事件分发，任何时刻（含拖动 resize 循环）都持续生效
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateCursorByPosition()
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    private func stopMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    deinit {
        stopMouseMonitor()
    }

    /// 按鼠标屏幕坐标更新光标（轮询兜底）：边缘/四角 → 拉伸；窗口内 → 箭头
    private func updateCursorByPosition() {
        guard isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let tolerance: CGFloat = 4
        let expanded = frame.insetBy(dx: -tolerance, dy: -tolerance)
        guard expanded.contains(mouse) else { return }
        let p = NSPoint(x: mouse.x - frame.origin.x,
                        y: mouse.y - frame.origin.y)
        cursorLogCounter += 1
        if cursorLogCounter % 100 == 1 {
            logCursor("轮询: 鼠标=\(Int(mouse.x)),\(Int(mouse.y)) 窗口=\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height)) 内点=\(Int(p.x)),\(Int(p.y))")
        }
        if let cursor = ResizeCursors.cursorFor(point: p, in: contentView?.bounds ?? .zero) {
            cursor.set()
        } else if frame.contains(mouse) {
            NSCursor.arrow.set()
        }
    }

    /// 强制限制尺寸范围；已在极限时尺寸与位置都固定不动；设置后保存大小
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var clamped = frameRect
        clamped.size.width = min(max(clamped.size.width, Self.minWidth), Self.maxWidth)
        clamped.size.height = min(max(clamped.size.height, Self.minHeight), Self.maxHeight)
        let overLimit = clamped.size != frameRect.size   // 本次拖动试图超出边界
        if overLimit && clamped.size == frame.size {
            // 尺寸已到极限且仍想超出：位置也保持不动
            return
        }
        super.setFrame(clamped, display: flag)
        Self.saveSize(clamped.size)
    }

    /// 事件处理：顶栏拖动移动窗口；边缘显示拉伸光标（双保险，防止失去焦点后光标失效）
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let p = event.locationInWindow
            let bounds = contentView?.bounds ?? .zero
            // 边缘（14px）：启动手动 resize（吞掉事件，避免与系统 resize 冲突）
            if let edge = edgeAt(point: p, bounds: bounds) {
                resizeState = (frame, NSEvent.mouseLocation, edge)
                return
            }
            let inTopBar = p.y >= bounds.height - topBarHeight
            // 顶栏（且不在拉伸边缘）按住可拖动移动位置
            if inTopBar {
                dragStart = (frame.origin, NSEvent.mouseLocation)
            } else {
                dragStart = nil
            }
        case .leftMouseDragged:
            if let resizeState {
                let mouse = NSEvent.mouseLocation
                let newFrame = frameForResize(edge: resizeState.edge,
                                              startFrame: resizeState.startFrame,
                                              mouse: mouse,
                                              startMouse: resizeState.startMouse)
                setFrame(newFrame, display: true)
                return
            }
            if let dragStart {
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - dragStart.mouse.x
                let dy = mouse.y - dragStart.mouse.y
                setFrameOrigin(NSPoint(x: dragStart.windowOrigin.x + dx,
                                       y: dragStart.windowOrigin.y + dy))
            }
        case .leftMouseUp:
            dragStart = nil
            resizeState = nil
            // 拖动/移动结束：保存位置（重开时恢复）
            Self.saveOrigin(frame.origin)
        case .mouseMoved:
            // 边缘/四角光标：在 sendEvent 层设置并吞掉（用户验证有效的版本）
            let p = event.locationInWindow
            if let cursor = ResizeCursors.cursorFor(point: p, in: contentView?.bounds ?? .zero) {
                cursor.set()
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// 支持三连击关闭的普通面板（输入翻译用）：仅在顶栏区域快速点击三次触发回调
final class TripleClickPanel: NSWindow {
    var onTripleClick: (() -> Void)?
    /// 顶栏高度（仅此区域三击关闭，避免输入框/结果区域误触）
    private let tripleClickBarHeight: CGFloat = 40
    /// 双击放大的延迟任务：350ms 内出现第三击则取消（三击只关闭不放大）
    private var pendingZoomWork: DispatchWorkItem?
    /// 第二击 mouseDown 被吞后，对应的 mouseUp 也要吞（防止系统误判双击 zoom）
    private var suppressingMouseUp = false

    /// 关闭来源日志（写 /tmp/dailyword_panel.log）：定位"点击外部被关闭"的元凶
    private func logPanelEvent(_ msg: String) {
        let line = "[面板] \(Date()) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: "/tmp/dailyword_panel.log") {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/dailyword_panel.log"))
        }
    }

    override func orderOut(_ sender: Any?) {
        logPanelEvent("orderOut 被调用（栈:\(Thread.callStackSymbols.prefix(4).joined(separator: " | "))")
        super.orderOut(sender)
    }

    override func close() {
        logPanelEvent("close 被调用")
        super.close()
    }

    override func performClose(_ sender: Any?) {
        logPanelEvent("performClose 被调用")
        super.performClose(sender)
    }

    /// 普通窗口：失去焦点时不额外操作（系统默认行为：变灰，不消失）
    override func resignKey() {
        super.resignKey()
    }

    /// 最小高度保护：SwiftUI hosting view 布局后会把窗口缩到内容高度（~76），
    /// 强制拉回初始高度，避免面板缩到看不见
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var f = frameRect
        if f.height < 100 {
            f.size.height = 140
        }
        super.setFrame(f, display: flag)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            // 手动激活：nonactivating 面板的 becomesKeyOnlyIfNeeded 不生效，
            // 点击时主动成为 key，输入框才能聚焦输入
            if !isKeyWindow {
                makeKey()
            }
            let point = event.locationInWindow
            // 顶栏 40pt：覆盖系统标题栏 + 内容顶部。
            // 单击放行（拖拽移动）；双击吞掉第二击、延迟放大（350ms 内第三击则取消，纯关闭）；
            // 三击：取消放大 → 直接关闭
            let barTop = frame.height - tripleClickBarHeight
            if point.y >= barTop {
                if event.clickCount >= 3 {
                    pendingZoomWork?.cancel()
                    pendingZoomWork = nil
                    suppressingMouseUp = false
                    onTripleClick?()
                    return
                }
                if event.clickCount == 2 {
                    pendingZoomWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        self?.performZoom(nil)
                        self?.suppressingMouseUp = false
                    }
                    pendingZoomWork = work
                    suppressingMouseUp = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
                    return
                }
                super.sendEvent(event)
                return
            }
            super.sendEvent(event)
            return
        }
        if event.type == .leftMouseUp, suppressingMouseUp {
            // 第二击的 mouseUp 一并吞掉：系统完全看不到第二击，不会重复 zoom
            return
        }
        super.sendEvent(event)
    }
}

/// 双语对照文本视图：只读可选，按行显示；选中某行时通知外部，外部可让另一栏滚动到对应行
struct BilingualTextView: NSViewRepresentable {
    let lines: [String]
    /// 需要高亮（黄色背景）的行号（整句模式：整行高亮）
    let highlightIndex: Int?
    /// 需要滚动到可见位置的行号（联动滚动：选中一侧时另一侧滚动到对应行）
    var scrollToLine: Int?
    /// 用户选中某行（nil = 取消选择）
    var onSelectLine: ((Int?) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectLine: onSelectLine)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let tv = NoCursorTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.delegate = context.coordinator
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        // 右键菜单：复制
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "复制",
                                  action: #selector(NSTextView.copy(_:)),
                                  keyEquivalent: "c")
        copyItem.target = tv
        menu.addItem(copyItem)
        tv.menu = menu

        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.onSelectLine = onSelectLine
        let attributed = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
            attributed.append(NSAttributedString(string: line, attributes: attrs))
            if index < lines.count - 1 {
                attributed.append(NSAttributedString(string: "\n"))
            }
        }
        // 整句模式：整行高亮
        if let highlightIndex, highlightIndex < lines.count {
            let range = rangeOfLine(in: attributed, line: highlightIndex)
            if range.location != NSNotFound {
                attributed.addAttribute(.foregroundColor, value: NSColor.systemYellow, range: range)
                attributed.addAttribute(.backgroundColor,
                                        value: NSColor.systemYellow.withAlphaComponent(0.35),
                                        range: range)
            }
        }
        tv.textStorage?.setAttributedString(attributed)
        // 联动滚动
        if let scrollToLine, scrollToLine < lines.count {
            let range = rangeOfLine(in: attributed, line: scrollToLine)
            if range.location != NSNotFound {
                tv.scrollRangeToVisible(range)
            }
        }
    }

    /// 计算第 line 行的字符范围
    private func rangeOfLine(in attr: NSAttributedString, line: Int) -> NSRange {
        let text = attr.string as NSString
        var currentLine = 0
        var location = 0
        while location < text.length {
            let newlineRange = text.range(of: "\n", options: [], range: NSRange(location: location, length: text.length - location))
            let lineEnd = newlineRange.location == NSNotFound ? text.length : newlineRange.location
            if currentLine == line {
                return NSRange(location: location, length: lineEnd - location)
            }
            currentLine += 1
            if newlineRange.location == NSNotFound { break }
            location = newlineRange.location + 1
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectLine: ((Int?) -> Void)?
        weak var textView: NSTextView?
        init(onSelectLine: ((Int?) -> Void)?) {
            self.onSelectLine = onSelectLine
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            let selected = tv.selectedRange()
            guard selected.length > 0 else { onSelectLine?(nil); return }
            let text = storage.string as NSString
            let location = selected.location
            var line = 0
            var cursor = 0
            while cursor < text.length {
                let newlineRange = text.range(of: "\n", options: [], range: NSRange(location: cursor, length: text.length - cursor))
                let lineEnd = newlineRange.location == NSNotFound ? text.length : newlineRange.location
                if location <= lineEnd {
                    onSelectLine?(line)
                    return
                }
                line += 1
                if newlineRange.location == NSNotFound { break }
                cursor = newlineRange.location + 1
            }
            onSelectLine?(line)
        }
    }
}

/// 翻译结果浮窗：双语对照（原文/译文），选中一侧时另一侧滚动到对应行
struct TranslateResultView: View {
    let source: String
    let sourceLines: [String]
    let targetLines: [String]
    var onClose: () -> Void
    var onReset: (() -> Void)?

    @State private var selectedSourceLine: Int?
    @State private var selectedTargetLine: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("划词翻译", systemImage: "character.bubble")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                // 重置为初始大小
                Button(action: { onReset?() }) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("重置为初始大小")
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // 原文（上）：选中上层 → 两层同位置高亮；下层选中同理
            BilingualTextView(lines: sourceLines,
                              highlightIndex: selectedSourceLine,
                              scrollToLine: selectedTargetLine,
                              onSelectLine: { line in
                selectedSourceLine = line
                selectedTargetLine = line
            })
            .frame(maxHeight: .infinity)

            Divider()

            // 译文（下）
            BilingualTextView(lines: targetLines,
                              highlightIndex: selectedTargetLine,
                              scrollToLine: selectedSourceLine,
                              onSelectLine: { line in
                selectedTargetLine = line
                selectedSourceLine = line
            })
            .frame(maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        // 顶栏三次点击快捷关闭（挂在外层，避开按钮手势竞争）
        .onTapGesture(count: 3) { onClose() }
    }
}

/// 原生 NSTextField 包装
struct NativeTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "输入单词或句子，回车翻译"
        field.font = .systemFont(ofSize: 13)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeTextField
        init(parent: NativeTextField) {
            self.parent = parent
        }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

/// 输入翻译面板：输入文本 → 回车翻译 → 显示结果
struct TranslateInputView: View {
    @State private var text = ""
    @State private var result: String?
    @State private var translating = false
    var onClose: () -> Void
    /// 内容尺寸变化通知（有结果时面板变高）
    var onSizeChange: ((CGSize) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("输入翻译", systemImage: "character.cursor.ibeam")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                // 原生 NSTextField：nonactivating 面板上点击时触发 becomesKeyOnlyIfNeeded 自动激活，可正常输入
                NativeTextField(text: $text, onSubmit: { doTranslate() })
                    .frame(height: 24)
                Button("翻译") { doTranslate() }
                    .controlSize(.small)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || translating)
            }

            if let result {
                Divider()
                ScrollView {
                    Text(result)
                        .font(.body)
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        // 无边框浮动面板：毛玻璃卡片承载内容（单层）
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .onChange(of: result != nil) { hasResult in
            onSizeChange?(CGSize(width: 380, height: hasResult ? 320 : 140))
        }
        // 顶栏/空白处三次点击快捷关闭（挂在外层，避开输入框与按钮手势竞争）
        .onTapGesture(count: 3) { onClose() }
    }

    private func doTranslate() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        translating = true
        result = "翻译中…"   // 先显示占位（原文已在输入框上方）
        var finished = false
        // 3 秒时限：无结果则报问题（翻译完成仍会更新）
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [self] in
            guard !finished else { return }
            self.result = "翻译超时，请检查网络后重试"
            self.translating = false
        }
        TranslationService.shared.translate(trimmed) { [self] translated, error in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                if let translated, !translated.isEmpty {
                    self.result = translated
                } else {
                    self.result = (error == .noNetwork)
                        ? "网络未连接，请检查网络后重试"
                        : "翻译失败，请重试"
                }
                self.translating = false
            }
        }
    }
}