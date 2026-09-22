import AppKit
import SwiftUI
import DailyWordCore

/// 浮动学习面板：由"隐藏/显示面板"快捷键控制，内容与菜单栏 Popover 一致
@MainActor
final class StudyPanelController {
    private static let originKey = "studyPanelOrigin"

    private let session: StudySession
    private var panel: KeyablePanel?
    var onVisibilityChanged: (() -> Void)?

    var isVisible: Bool { panel != nil }

    /// 面板在屏幕上的位置（引导气泡锚定用）
    var panelFrame: NSRect? { panel?.frame }

    /// 浮动面板窗口（供快捷键按焦点分派）
    var window: NSWindow? { panel }

    init(session: StudySession) {
        self.session = session
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        session.start()

        let view = StudyView(onClose: { [weak self] in self?.hide() })
            .environmentObject(session)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []   // 无边框面板：禁止 SwiftUI 接管窗口尺寸约束
        let size = NSSize(width: 340, height: 420)
        hosting.frame.size = size
        hosting.autoresizingMask = [.width, .height]

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let saved = UserDefaults.standard.string(forKey: Self.originKey),
           Self.isOriginOnScreen(NSPointFromString(saved), size: size) {
            panel.setFrameOrigin(NSPointFromString(saved))
        } else if let screen = NSScreen.screens.first {
            // 首次/保存位置已离屏：默认放主屏右上
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 24,
                                         y: vf.maxY - size.height - 24))
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            let origin = window.frame.origin
            Task { @MainActor in
                UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
            }
        }

        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
        onVisibilityChanged?()
    }

    /// 快捷键微移面板（限制在屏幕可见区内）并记住位置
    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let panel else {
            NSLog("[移动] nudge: panel 为 nil")
            return
        }
        var origin = panel.frame.origin
        origin.x += dx
        origin.y += dy
        if let screen = panel.screen ?? NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = min(max(vf.minX, origin.x), vf.maxX - panel.frame.width)
            origin.y = min(max(vf.minY, origin.y), vf.maxY - panel.frame.height)
        }
        NSLog("[移动] nudge 前=\(panel.frame.origin) 后=\(origin)")
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
    }

    /// 保存的位置是否仍落在某块屏幕内（副屏拔掉后防止面板消失）
    static func isOriginOnScreen(_ origin: NSPoint, size: NSSize) -> Bool {
        let frame = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    /// 引导等场景：面板若不在主屏，拉回主屏默认位置
    func ensureOnPrimaryScreen() {
        guard let panel, let primary = NSScreen.screens.first,
              panel.screen != primary else { return }
        let vf = primary.visibleFrame
        let origin = NSPoint(x: vf.maxX - panel.frame.width - 24,
                             y: vf.maxY - panel.frame.height - 24)
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        onVisibilityChanged?()
    }
}
