import AppKit
import SwiftUI
import DailyWordCore

/// 菜单栏图标控制器
/// - 单击：弹出/收起学习面板
/// - 双击 / 右键：弹出菜单（词库、引导、退出等）
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let session: StudySession
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    /// 学习面板弹窗窗口（未打开时为 nil），供设置窗口定位用
    var popoverWindow: NSWindow? {
        popover.isShown ? popover.contentViewController?.view.window : nil
    }

    init(session: StudySession) {
        self.session = session
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "character.book.closed.fill",
                                   accessibilityDescription: "DailyWord")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "DailyWord · 单击背词，双击/右键更多"
        }
        statusItem = item

        // 菜单栏应用从不激活，transient/semitransient 都无法可靠自动关闭。
        // 使用 .applicationDefined（不自动关闭）+ 手动监控 keyWindow 变化：
        // 本应用还有其他 key 窗口（设置/浮动/测试面板）时保持打开；
        // 无任何 key 窗口（点击了其他应用/桌面）时自动收起。
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: StudyView(onClose: { [weak self] in
                self?.closePopover()
            }).environmentObject(session)
        )

        // 监听 keyWindow 变化：本应用无 key 窗口时关闭学习面板
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification, object: nil)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let resigned = notification.object as? NSWindow else { return }
        guard let popoverWindow = popover.contentViewController?.view.window else { return }
        // 仅关注学习面板窗口失去 key 的情况
        guard resigned == popoverWindow else { return }
        // 延迟稍久，等新的 key 窗口稳定（第一次打开设置窗口时可能稍后才 becomeKey，
        // 立即判断会误以为“无 key 窗口”而关掉学习面板）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.popover.isShown else { return }
            if let key = NSApp.keyWindow, NSApp.windows.contains(key), key !== popoverWindow {
                // 本应用其他窗口是 key（设置框/浮动面板/测试面板）→ 保持打开
            } else {
                // 无本应用 key 窗口（点击了其他应用/桌面/空白区域）→ 自动收起
                self.popover.performClose(nil)
            }
        }
    }

    /// 更新角标：显示待复习数量
    func updateBadge(dueCount: Int) {
        statusItem?.button?.title = dueCount > 0 ? " \(dueCount)" : ""
    }

    /// 菜单栏按钮在屏幕上的真实位置（引导箭头锚定用）
    var buttonScreenFrame: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// 关闭学习面板（供三连击等外部调用）
    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    // MARK: - 点击处理

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        let isDoubleClick = (event?.clickCount ?? 1) >= 2

        if isRightClick || isDoubleClick {
            if popover.isShown { popover.performClose(nil) }
            showMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            session.start()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()

        let study = NSMenuItem(title: "开始背词", action: #selector(menuStudy), keyEquivalent: "")
        study.target = self
        menu.addItem(study)

        let quiz = NSMenuItem(title: "开始练习", action: #selector(menuQuiz), keyEquivalent: "")
        quiz.target = self
        menu.addItem(quiz)

        let game = NSMenuItem(title: "🗼 爬塔挑战", action: #selector(menuGame), keyEquivalent: "")
        game.target = self
        menu.addItem(game)

        let library = NSMenuItem(title: "词库与熟悉度…", action: #selector(menuLibrary), keyEquivalent: "")
        library.target = self
        menu.addItem(library)

        let settings = NSMenuItem(title: "设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let exportItem = NSMenuItem(title: "导出数据…", action: #selector(menuExport), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        let importItem = NSMenuItem(title: "导入数据…", action: #selector(menuImport), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(.separator())

        let guide = NSMenuItem(title: "重看上手引导", action: #selector(menuGuide), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 DailyWord", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 5),
                   in: button)
    }

    // MARK: - 菜单动作

    @objc private func menuStudy() {
        guard let button = statusItem?.button else { return }
        togglePopover(from: button)
    }

    @objc private func menuQuiz() {
        AppServices.shared.toggleQuizOverlay()
    }

    @objc private func menuGame() {
        AppServices.shared.showTowerGame()
    }

    @objc private func menuLibrary() {
        AppServices.shared.showLibrary()
    }

    @objc private func menuSettings() {
        AppServices.shared.showSettingsWindow()
    }

    @objc private func menuExport() {
        AppServices.shared.showExportDataDialog()
    }

    @objc private func menuImport() {
        AppServices.shared.showImportDataDialog()
    }

    @objc private func menuGuide() {
        AppServices.shared.showOnboarding()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        AppServices.shared.setStudyOpen(true)
    }

    func popoverDidClose(_ notification: Notification) {
        AppServices.shared.setStudyOpen(false)
    }
}
