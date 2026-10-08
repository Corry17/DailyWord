import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import DailyWordCore

/// 全局服务容器：App 入口和 AppDelegate 共享数据库、会话与各窗口/浮层控制器
/// 单词详情窗口打开状态（@Published 驱动背词面板灯泡即时刷新）
final class WordDetailState: ObservableObject {
    static let shared = WordDetailState()
    @Published var headword: String?
    private init() {}
}

@MainActor
final class AppServices {
    static let shared = AppServices()

    static let hideOnboardingKey = "hideOnboarding"
    static let dailyNewLimitKey = "dailyNewLimit"

    let database: AppDatabase
    let session: StudySession
    let ambient: AmbientReviewController
    let quiz: QuizOverlayController
    let onboardingFlow = OnboardingFlow()
    private(set) var studyPanel: StudyPanelController!
    private(set) var statusItem: StatusItemController!

    private var onboardingWindow: NSWindow?
    private var libraryWindow: NSWindow?
    private var gameWindow: NSWindow?
    private var wordDetailWindow: NSWindow?
    /// 外部可查询当前详情窗口是否打开（用于 UI 图标状态切换）
    func isWordDetailOpen(for headword: String) -> Bool {
        WordDetailState.shared.headword == headword
    }

    private var cachedSentences: [String: [String]] = [:]
    
    /// 加载本地 sentences.json（API 预下载的例句）
    func loadSentencesFromFile() {
        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("sentences.json")
        guard let data = try? Data(contentsOf: docURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]],
              !json.isEmpty
        else { return }
        cachedSentences = json
    }
    
    /// 查询例句：优先本地缓存，次之内置库（懒加载 sentences.json）
    func sentences(for word: String) -> [String] {
        if cachedSentences.isEmpty {
            loadSentencesFromFile()
        }
        let key = word.lowercased()
        if let ss = cachedSentences[key], !ss.isEmpty { return Array(ss.prefix(3)) }
        return WordMemoryService.shared.sentences(for: word).map { Array($0.prefix(3)) } ?? []
    }
    private var wordDetailHeadword: String?
    private var settingsWindow: NSPanel?
    private var coachPanel: NSPanel?
    private var hotKeys: [GlobalHotKey] = []
    private var badgeCancellable: AnyCancellable?

    // 无感弹卡抑制来源（任一为 true 时暂停弹卡）
    private var isStudyOpen = false
    private var isOnboardingOpen = false
    private var isGameOpen = false

    private init() {
        // 数据库初始化失败属于不可恢复错误（词库缺失/磁盘异常），直接崩溃并留下日志
        let database = try! AppDatabase.makeShared()
        self.database = database
        let storedLimit = UserDefaults.standard.integer(forKey: Self.dailyNewLimitKey)
        self.session = StudySession(database: database,
                                    dailyNewLimit: storedLimit > 0 ? storedLimit : 20)
        session.collectionKey = AppSettings.shared.currentCollectionKey
        let ambient = AmbientReviewController(database: database, scheduler: EbbinghausScheduler())
        self.ambient = ambient
        let engine = QuizEngine(database: database, scheduler: EbbinghausScheduler(), ambient: ambient)
        self.quiz = QuizOverlayController(engine: engine)
        self.quiz.onVisibilityChanged = { [weak self] in
            self?.updateAmbientSuppression()
        }
        self.onboardingFlow.onStepChanged = { [weak self] _ in
            guard let self, self.onboardingFlow.isActive else { return }
            self.presentCoachMark()
        }
        self.onboardingFlow.onCelebrate = { [weak self] praise in
            guard let self, self.onboardingFlow.isActive else { return }
            // 先把气泡切换为鼓励态，稍后自动进入下一步
            self.presentCoachMark(praise: praise)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.onboardingFlow.isActive,
                      self.onboardingFlow.celebrating else { return }
                self.onboardingFlow.advance()
            }
        }
        self.studyPanel = StudyPanelController(session: session)
        self.studyPanel.onVisibilityChanged = { [weak self] in
            guard let self else { return }
            self.setStudyOpen(self.studyPanel.isVisible)
        }
        self.statusItem = StatusItemController(session: session)
    }

    // MARK: - 词库切换

    /// 切换当前词库：保存选择、重建学习队列、刷新练习浮层与词库页
    func switchCollection(_ key: String) {
        guard AppSettings.shared.currentCollectionKey != key else { return }
        AppSettings.shared.currentCollectionKey = key
        session.collectionKey = key
        session.start()
        quiz.engine.reloadPool()
        NotificationCenter.default.post(name: .collectionDidChange, object: nil)
    }

    // MARK: - 启动

    func onLaunch() {
        statusItem.install()
        prewarmTowerPool()
        // 到期数变化时同步菜单栏角标
        badgeCancellable = ambient.$dueCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.statusItem.updateBadge(dueCount: count)
            }
        ambient.start()
        showOnboardingIfNeeded()
        // 应用持久化的发音口音设置
        SpeechService.shared.accent = AppSettings.shared.accent
        // 全局快捷键（可在设置中修改）
        registerHotKeys()
        // 记录最近点击的面板（快捷键按焦点/最近操作分派）
        observePanelClicks()
        // 重复启动第二个实例时，把第一个实例带到最前
        SingleInstance.listenForActivation { [weak self] in
            self?.bringToFront()
        }
    }

    /// 按设置（重新）注册全局热键。
    /// 只有带修饰键的绑定才注册为系统级；无修饰键（如空格）由面板内的
    /// SwiftUI 快捷键承接（见 StudyView），不会抢占其他 App 的按键。
    func registerHotKeys() {
        hotKeys = []
        for action in HotKeyAction.allCases {
            let binding = AppSettings.shared.hotKeys[action] ?? .none
            guard binding.isGlobal else { continue }
            // 移动面板与透明度调节支持长按重复（连续生效）
            let repeatInterval: TimeInterval?
            switch action {
            case .opacityUp, .opacityDown, .panelLeft, .panelRight, .panelUp, .panelDown:
                repeatInterval = 0.06
            default:
                repeatInterval = nil
            }
            if let hotKey = GlobalHotKey(id: action.hotKeyID, keyCode: binding.keyCode,
                                         modifiers: binding.modifiers,
                                         repeatInterval: repeatInterval,
                                         callback: { Task { @MainActor in AppServices.shared.perform(action) } }) {
                hotKeys.append(hotKey)
            } else {
                // 自查日志：注册失败（如与系统快捷键冲突）
                NSLog("[热键] 注册失败: \(action.rawValue) keyCode=\(binding.keyCode) mods=\(binding.modifiers)")
            }
        }
    }

    /// 执行快捷键动作
    func perform(_ action: HotKeyAction) {
        debugLog("快捷键触发: \(action.rawValue)")
        switch action {
        case .revealWord:
            session.toggleReveal()
        case .speak:
            // 测试浮层在前时读测试词，否则读学习卡当前词
            if quiz.isVisible, let word = quiz.engine.question?.item.word.headword {
                SpeechService.shared.speak(word)
            } else if let word = session.currentHeadword {
                SpeechService.shared.speak(word)
            }
        case .togglePanel:
            studyPanel.toggle()
        case .toggleQuiz:
            toggleQuizOverlay()
        case .opacityUp:
            adjustOpacity(by: 0.08)
        case .opacityDown:
            adjustOpacity(by: -0.08)
        case .panelLeft:
            movePanel(dx: -24, dy: 0)
        case .panelRight:
            movePanel(dx: 24, dy: 0)
        case .panelUp:
            movePanel(dx: 0, dy: 24)
        case .panelDown:
            movePanel(dx: 0, dy: -24)
        case .translateSelection:
            translateSelection()
        case .translateInput:
            showTranslateInput()
        case .showWordDetail:
            // toggle：详情窗口可见则关闭，否则打开当前词
            if let panel = wordDetailWindow, panel.isVisible {
                panel.orderOut(nil)
                wordDetailHeadword = nil
                WordDetailState.shared.headword = nil
            } else if let item = session.currentItem {
                showWordDetail(item)
            }
        case .toggleGame:
            toggleGameWindow()
        }
    }

    /// 快捷键开关修仙塔窗口：关闭时保存进度
    func toggleGameWindow() {
        if let window = gameWindow, window.isVisible {
            towerEngine.pauseBattleTimer()
            towerEngine.saveProgressNow()
            window.orderOut(nil)
        } else {
            showTowerGame()
        }
    }

    // MARK: - 翻译

    private var translateResultPanel: NSPanel?
    private var translateHostingController: NSHostingController<TranslateResultView>?
    private var translateInputPanel: TripleClickPanel?
    private var translateClickMonitor: Any?
    private var lastTranslatedText = ""

    /// 翻译窗口层级：输入翻译固定在基准层；划词结果窗在被呼出/操作时升到其上一层
    private static let translateBaseLevel = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 1)
    private static let translateActiveLevel = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 2)

    /// 当前操作的窗口在上层：呼出或点击划词窗 → 升到输入翻译之上；
    /// 打开/点击/关闭输入翻译 → 划词窗回落到基准层
    private func setTranslateResultPanelOnTop(_ onTop: Bool) {
        guard let panel = translateResultPanel else { return }
        // 只有与输入翻译同屏时才需要抢上层；单独使用时保持基准层，不压住其他窗口
        let raised = onTop && translateInputPanel != nil
        panel.level = raised ? Self.translateActiveLevel : .floating
        debugLog("划词结果窗层级切换 level=\(panel.level.rawValue)（置顶=\(raised)）")
        if raised { panel.orderFrontRegardless() }
    }

    /// 划词翻译：读取当前选中文本 → 翻译 → 浮窗显示；再次按快捷键隐藏
    private var lastTranslateSelectionCloseTime: TimeInterval = 0
    /// 划词结果窗是否保持置顶：由快捷键呼出或误判恢复发起，用户去操作输入翻译窗时交还
    private var translateResultShouldStayOnTop = false
    private func translateSelection() {
        // toggle：结果浮窗已显示 → 关闭
        if let panel = translateResultPanel {
            lastTranslateSelectionCloseTime = Date().timeIntervalSinceReferenceDate
            ResizableTranslatePanel.saveOrigin(panel.frame.origin)
            panel.orderOut(nil)
            translateResultPanel = nil
            translateHostingController = nil
            translateResultShouldStayOnTop = false
            stopTranslateSync()
            return
        }
        guard ensureAccessibilityPermission() else { return }
        showNetworkHintIfNeeded()
        // 快捷键呼出：结果窗为当前操作对象 → 浮到输入翻译之上
        translateResultShouldStayOnTop = true
        performSelectionTranslation()
    }

    /// 执行一次划词翻译（首次或点击同步共用）
    private func performSelectionTranslation() {
        // 优先 AX 读取（无副作用）；AX 失败才用剪贴板兜底（仅在用户主动点击时）
        guard let text = selectedTextViaAccessibility() ?? selectedTextViaCopyPaste(), !text.isEmpty else {
            updateTranslateResult(source: "未获取到选中文本",
                                  sourceLines: ["未获取到选中文本"],
                                  targetLines: ["请先在任意应用中选中单词或句子，再按快捷键"])
            // 尚未获取到文本：也要启动同步监听，用户随后选中时会自动更新
            startTranslateSync()
            return
        }
        lastTranslatedText = text
        translateSentencesWith(text: text)
    }

    /// 逐句翻译并更新浮窗（网络/翻译失败时显示对应提示）
    private func translateSentencesWith(text: String) {
        TranslationService.shared.translateSentences(text) { [weak self] translated, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let sourceLines = TranslationService.shared.splitSentences(text)
                if let translated, !translated.isEmpty {
                    self.updateTranslateResult(source: text,
                                               sourceLines: sourceLines,
                                               targetLines: translated)
                } else {
                    let message = (error == .noNetwork)
                        ? "网络未连接，请检查网络后重试"
                        : "翻译失败，请重试"
                    self.updateTranslateResult(source: text,
                                               sourceLines: sourceLines,
                                               targetLines: [message])
                }
                self.startTranslateSync()
            }
        }
    }

    /// 首次使用翻译功能时提醒需要联网（只提醒一次）
    private func showNetworkHintIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "translationNetworkHintShown") else { return }
        UserDefaults.standard.set(true, forKey: "translationNetworkHintShown")
        let alert = NSAlert()
        alert.messageText = "翻译需要联网"
        alert.informativeText = "划词翻译和输入翻译使用在线翻译服务，需要连接网络才能使用；网络不可用时请检查网络后重试。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    /// 同步机制：监听全局鼠标点击（选择文本后点击/松开即触发），不干扰键盘输入
    private func startTranslateSync() {
        stopTranslateSync()
        translateClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            Task { @MainActor in self?.syncSelection() }
        }
    }

    private func stopTranslateSync() {
        if let monitor = translateClickMonitor {
            NSEvent.removeMonitor(monitor)
            translateClickMonitor = nil
        }
    }

    private func syncSelection() {
        guard let panel = translateResultPanel else {
            stopTranslateSync()
            return
        }
        // 鼠标在浮窗内：用户在选中浮窗文本做对照，不重新翻译
        let mouse = NSEvent.mouseLocation
        if panel.frame.contains(mouse) { return }
        // 延迟等待选中完成；AX 优先，失败用剪贴板兜底（带选中检测：无选中不误触发）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.translateResultPanel != nil else { return }
            guard let text = self.selectedTextViaAccessibility() ?? self.selectedTextViaCopyPaste(),
                  !text.isEmpty, text != self.lastTranslatedText else { return }
            self.lastTranslatedText = text
            self.translateSentencesWith(text: text)
        }
    }

    /// 创建或更新划词翻译浮窗（双语对照，可拖动、可调大小）
    private func updateTranslateResult(source: String, sourceLines: [String], targetLines: [String]) {
        let view = TranslateResultView(source: source,
                                       sourceLines: sourceLines,
                                       targetLines: targetLines,
                                       onClose: { [weak self] in self?.closeTranslateResult() },
                                       onReset: { [weak self] in
            (self?.translateResultPanel as? ResizableTranslatePanel)?.resetToDefaultSize()
        })
        if let hosting = translateHostingController {
            // 复用面板：直接更新内容
            hosting.rootView = view
            if translateResultShouldStayOnTop { setTranslateResultPanelOnTop(true) }
            return
        }
        let hosting = NSHostingController(rootView: view)
        translateHostingController = hosting
        // 恢复上一次设置的窗口大小（钳制在合法范围内）
        let saved = ResizableTranslatePanel.savedSize() ?? NSSize(width: 340, height: 320)
        let savedSize = NSSize(width: min(max(saved.width, 340), 900),
                               height: min(max(saved.height, 320), 800))
        let panel = ResizableTranslatePanel(
            contentRect: NSRect(x: 0, y: 0, width: savedSize.width, height: savedSize.height),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 拉拽调整大小：最小保持原尺寸，最大限制在屏幕范围内
        panel.minSize = NSSize(width: 340, height: 320)
        panel.maxSize = NSSize(width: 900, height: 800)
        // 容器视图：边缘/四角注册拉伸光标（系统光标机制，静止时也生效）
        let container = ResizeCursorContainerView(frame: hosting.view.bounds)
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.addSubview(hosting.view)
        panel.contentView = container
        // 显示位置：恢复上一次的位置（仍在本机屏幕内）；否则鼠标所在屏正中间
        if let savedOrigin = ResizableTranslatePanel.savedOrigin() {
            let centerPoint = NSPoint(x: savedOrigin.x + savedSize.width / 2,
                                      y: savedOrigin.y + savedSize.height / 2)
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.contains(centerPoint) }
            if onScreen {
                panel.setFrameOrigin(savedOrigin)
            } else {
                centerPanel(panel, size: savedSize)
            }
        } else {
            centerPanel(panel, size: savedSize)
        }
        translateResultPanel = panel
        panel.onUserMouseDown = { [weak self] in
            self?.translateResultShouldStayOnTop = true
            self?.setTranslateResultPanelOnTop(true)
        }
        observeClose(of: panel) { [weak self] in
            ResizableTranslatePanel.saveOrigin(panel.frame.origin)
            self?.translateResultPanel = nil
            self?.translateHostingController = nil
            self?.stopTranslateSync()
        }
        panel.orderFrontRegardless()
        // 关键：激活应用——NSCursor.set() 只在应用激活时有效（nonactivating 面板默认不激活）
        NSApp.activate(ignoringOtherApps: true)
        // 快捷键呼出/误判恢复：刚出现的结果窗应压住输入翻译
        if translateResultShouldStayOnTop { setTranslateResultPanelOnTop(true) }
    }

    /// 导入数据后刷新会话与词库（重新开始、通知词库页）
    func refreshAfterImport() {
        session.start()
        NotificationCenter.default.post(name: .collectionDidChange, object: nil)
    }

    /// 将划词翻译面板置于鼠标所在屏幕的正中间
    private func centerPanel(_ panel: NSPanel, size: NSSize) {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                             y: screen.visibleFrame.midY - size.height / 2)
        panel.setFrameOrigin(origin)
    }

    private func closeTranslateResult() {
        translateResultShouldStayOnTop = false
        if let panel = translateResultPanel {
            ResizableTranslatePanel.saveOrigin(panel.frame.origin)
            panel.orderOut(nil)
        }
        translateResultPanel = nil
        translateHostingController = nil
        stopTranslateSync()
    }

    /// 输入翻译：弹出输入面板，回车翻译；再次按快捷键隐藏
    private var lastTranslateInputToggle: TimeInterval = 0
    private func showTranslateInput() {
        debugLog("showTranslateInput 调用")
        // 防抖：快速连按（或热键双触发）时只生效一次，避免"打开即被 toggle 关闭"
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastTranslateInputToggle < 0.3 {
            debugLog("输入翻译 toggle 防抖，忽略")
            return
        }
        lastTranslateInputToggle = now
        if translateInputPanel != nil {
            debugLog("toggle 分支：关闭现有输入翻译")
            closeTranslateInput()
            return
        }
        // 误判恢复：按 ⌥Z 时系统可能误触发 ⌃⌥Z 关掉划词翻译——
        // 若 0.5s 内划词翻译刚被关闭且此时打开了输入翻译 → 判定误判，恢复划词翻译
        if now - lastTranslateSelectionCloseTime < 0.5, !lastTranslatedText.isEmpty {
            debugLog("划词翻译疑似被误关，自动恢复")
            // 恢复的是用户本来想要的划词窗：保持置顶，不又被输入翻译盖住
            translateResultShouldStayOnTop = true
            translateSentencesWith(text: lastTranslatedText)
        } else {
            // 用户主动打开输入翻译：本次以输入翻译为当前操作对象
            translateResultShouldStayOnTop = false
        }
        showNetworkHintIfNeeded()
        debugLog("创建输入翻译面板")
        // 普通标题栏窗口（输入正常，接受点击别的程序被隐藏）
        let panel = TripleClickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.onTripleClick = { [weak self] in
            self?.closeTranslateInput()
        }
        // 点击输入翻译 = 它拿到焦点 → 划词结果窗回落到基准层
        panel.onUserMouseDown = { [weak self] in
            self?.translateResultShouldStayOnTop = false
            self?.setTranslateResultPanelOnTop(false)
        }
        panel.title = "输入翻译"
        // floating 层级：高于应用内普通窗口（不被覆盖），点击别的应用时变灰不消失
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = TranslateInputView(
            onClose: { [weak self] in self?.closeTranslateInput() },
            onSizeChange: { [weak panel] size in
                panel?.setContentSize(size)
            })
        panel.contentViewController = NSHostingController(rootView: view)
        panel.setContentSize(NSSize(width: 380, height: 140))
        panel.isReleasedWhenClosed = false
        // 置顶（高于菜单栏 popover 层级，不被背词面板遮挡）
        panel.level = Self.translateBaseLevel
        panel.center()
        translateInputPanel = panel
        // 输入翻译刚打开（并会成为 key）→ 划词结果窗回到基准层，不抢占最上层
        setTranslateResultPanelOnTop(false)
        observeClose(of: panel) { [weak self] in
            self?.translateInputPanel = nil
            self?.setTranslateResultPanelOnTop(false)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        debugLog("输入翻译显示 isVisible=\(panel.isVisible) frame=\(panel.frame) level=\(panel.level.rawValue)")
    }

    private func closeTranslateInput() {
        translateInputPanel?.orderOut(nil)
        translateInputPanel = nil
        // 输入翻译消失：划词结果窗不必再停留在置顶层
        setTranslateResultPanelOnTop(false)
    }

    /// 辅助功能权限检查（划词翻译需要）
    private func ensureAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if AXIsProcessTrusted() {
                    self?.translateSelection()
                }
            }
        }
        return trusted
    }

    /// 通过辅助功能 API 获取最前应用的选中文本
    private func selectedTextViaAccessibility() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard err == .success, let focusedElement = focused else { return nil }
        let element = focusedElement as! AXUIElement

        // 优先直接读取 kAXSelectedTextAttribute
        var selected: CFTypeRef?
        let err2 = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected)
        if err2 == .success, let text = selected as? String, !text.isEmpty {
            return text
        }
        // 部分应用（浏览器网页等）不支持直接读选中文本，改用选中范围 + 取值
        var range: CFTypeRef?
        let err3 = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &range)
        if err3 == .success, let rangeValue = range {
            let axValue = rangeValue as! AXValue
            if AXValueGetType(axValue) == .cfRange {
                var cfRange = CFRange()
                AXValueGetValue(axValue, .cfRange, &cfRange)
                var value: CFTypeRef?
                let err4 = AXUIElementCopyAttributeValue(
                    element, kAXValueAttribute as CFString, &value)
                if err4 == .success, let text = value as? String {
                    let start = max(0, cfRange.location)
                    let length = max(0, cfRange.length)
                    let nsText = text as NSString
                    if start + length <= nsText.length {
                        return nsText.substring(with: NSRange(location: start, length: length))
                    }
                }
            }
        }
        return nil
    }

    /// 兜底方案：模拟 ⌘C 复制选中文本到剪贴板，读回后恢复剪贴板（兼容更多应用）
    /// 先清空剪贴板再模拟复制：无选中时 ⌘C 无效、剪贴板保持为空 → 返回 nil（可区分"点击"与"选中"）
    private func selectedTextViaCopyPaste() -> String? {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return nil }
        let pasteboard = NSPasteboard.general
        let savedString = pasteboard.string(forType: .string)
        let savedData = pasteboard.data(forType: .string)

        // 清空剪贴板：只有真正发生复制（存在选中文本）后才会再次非空
        pasteboard.clearContents()

        // 模拟 ⌘C（virtualKey 8 = C 键）
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        // 等待剪贴板更新
        Thread.sleep(forTimeInterval: 0.2)
        let text = pasteboard.string(forType: .string)

        // 恢复剪贴板
        if let savedString {
            pasteboard.setString(savedString, forType: .string)
        } else if let savedData {
            pasteboard.setData(savedData, forType: .string)
        } else {
            pasteboard.clearContents()
        }
        // 剪贴板仍为空 = 没有选中内容（⌘C 无效），不视为选中
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// 快捷键操作目标：焦点（key window）在哪个面板就作用哪个面板
    private enum HotKeyTarget {
        case quiz       // 测试面板
        case study      // 学习面板（⌥W 浮动面板 / 菜单栏弹窗）
    }

    /// 用户最后点击/激活的面板（nonactivating 窗口不成为 key，需用点击记录兜底）
    private var lastHotKeyTarget: HotKeyTarget = .study

    /// 当前快捷键作用的面板：优先 key window 判断，其次最近点击的面板
    private var hotKeyTarget: HotKeyTarget {
        if let key = NSApp.keyWindow {
            if key === quiz.window { return .quiz }
            if key === studyPanel.window || key === statusItem.popoverWindow { return .study }
        }
        return lastHotKeyTarget
    }

    /// 记录鼠标点击落在哪个面板（快捷键按最近点击的面板执行）
    private func recordClickTarget() {
        let p = NSEvent.mouseLocation
        if let f = quiz.panelFrame, f.contains(p) {
            lastHotKeyTarget = .quiz
        } else if let f = studyPanel.panelFrame, f.contains(p) {
            lastHotKeyTarget = .study
        }
    }

    /// 注册面板点击监听：本地（应用内）+ 全局，用于记录最近操作的面板
    func observePanelClicks() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.recordClickTarget() }
            return event   // 不拦截，继续传递
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.recordClickTarget() }
        }
    }

    /// 移动当前焦点所在的浮动面板（测试面板或 ⌥W 学习面板）
    private func movePanel(dx: CGFloat, dy: CGFloat) {
        debugLog("移动: target=\(hotKeyTarget == .quiz ? "quiz" : "study") dx=\(dx) dy=\(dy)")
        switch hotKeyTarget {
        case .quiz: quiz.nudge(dx: dx, dy: dy)
        case .study: studyPanel.nudge(dx: dx, dy: dy)
        }
    }

    /// 调试日志：直接写文件（NSLog 在 nohup 下可能不落盘）
    private func debugLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: "/tmp/dailyword_debug.log") {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/dailyword_debug.log"))
        }
    }

    /// 透明度快捷键按焦点分派：焦点在哪个面板就调哪个面板的透明度
    private func adjustOpacity(by delta: Double) {
        debugLog("透明度: target=\(hotKeyTarget == .quiz ? "quiz" : "study") delta=\(delta)")
        switch hotKeyTarget {
        case .quiz: AppSettings.shared.adjustQuizOpacity(by: delta)
        case .study: AppSettings.shared.adjustStudyOpacity(by: delta)
        }
        // 引导互动步：调了透明度即鼓励并进入下一步
        onboardingFlow.notifyOpacityChanged()
    }

    /// 跳转顶层显示：激活 App 并弹出指引气泡
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        showOnboarding()
    }

    /// 独立设置窗口：避免系统颜色面板与 popover 的窗口层级冲突
    func showSettingsWindow() {
        if settingsWindow == nil {
            let view = SettingsPanelView(session: session)
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = []
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 540),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered, defer: false
            )
            panel.title = "设置"
            panel.contentView = hosting
            panel.isReleasedWhenClosed = false
            settingsWindow = panel
        }
        // 位置：学习面板（菜单栏弹窗或 ⌥W 浮动面板）打开时，显示在其左侧；否则居中
        if let window = settingsWindow {
            if let anchor = studyPanel.panelFrame {
                window.setFrameOrigin(NSPoint(x: anchor.minX - window.frame.width - 12,
                                              y: anchor.midY - window.frame.height / 2))
            } else if let popoverWin = statusItem.popoverWindow {
                window.setFrameOrigin(NSPoint(x: popoverWin.frame.minX - window.frame.width - 12,
                                              y: popoverWin.frame.midY - window.frame.height / 2))
            } else {
                window.center()
            }
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        // 仅打开时置顶（不改变常驻层级），确保不被学习面板等 floating 窗口遮挡
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeSettingsWindow() {
        settingsWindow?.orderOut(nil)
    }

    // MARK: - 无感弹卡抑制

    func setStudyOpen(_ open: Bool) {
        isStudyOpen = open
        updateAmbientSuppression()
        if !open { ambient.refreshDueCount() }
    }

    private func updateAmbientSuppression() {
        // 仅引导流程中抑制弹卡；学习面板/测试/游戏打开时照常弹卡（弹卡不抢焦点，不干扰其他界面）
        ambient.isSuppressed = isOnboardingOpen
    }

    // MARK: - 箭头式上手指引

    /// 首次启动显示指引，除非用户点过"不再显示"
    func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hideOnboardingKey) else { return }
        showOnboarding()
    }

    func showOnboarding() {
        onboardingFlow.reset()
        onboardingFlow.isActive = true
        isOnboardingOpen = true
        updateAmbientSuppression()
        presentCoachMark()
    }

    private func finishOnboarding(rememberSkip: Bool) {
        if rememberSkip {
            UserDefaults.standard.set(true, forKey: Self.hideOnboardingKey)
        }
        onboardingFlow.isActive = false
        isOnboardingOpen = false
        updateAmbientSuppression()
        coachPanel?.orderOut(nil)
        coachPanel = nil
        // 收尾：关掉引导过程中自动打开的界面
        quiz.hide()
        libraryWindow?.close()
    }

    /// 展示/更新当前步骤的指引气泡，并把焦点带到被指引的界面
    private func presentCoachMark(praise: String? = nil) {
        let step = onboardingFlow.step

        // 每一步先把对应界面展开，让指引真正“手把手”；面板统一拉回主屏
        switch step {
        case .welcome, .menubar:
            studyPanel.hide()
            quiz.hide()
            libraryWindow?.close()
        case .study:
            quiz.hide()
            libraryWindow?.close()
            studyPanel.show()
            studyPanel.ensureOnPrimaryScreen()
        case .library:
            studyPanel.hide()
            quiz.hide()
            showLibrary()
        case .quiz:
            libraryWindow?.close()
            studyPanel.hide()
            quiz.show()
            quiz.ensureOnPrimaryScreen()
        case .appearance:
            quiz.hide()
            studyPanel.show()
            studyPanel.ensureOnPrimaryScreen()
            // 稍等面板就绪后自动弹开设置
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(name: .openStudySettings, object: nil)
            }
        case .opacityDemo, .tripleClose:
            quiz.hide()
            libraryWindow?.close()
            studyPanel.show()
            studyPanel.ensureOnPrimaryScreen()
            // 收起上一步可能打开的设置/奖励弹窗，让用户专注互动
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .closeStudyPopovers, object: nil)
            }
        case .rewards:
            studyPanel.show()
            studyPanel.ensureOnPrimaryScreen()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(name: .openStudyRewards, object: nil)
            }
        }

        let arrow = coachArrow(for: step)
        // 菜单栏步：箭头需水平对准图标（气泡被屏边限制时箭头单独偏移）
        var arrowXOffset: CGFloat = 0
        if step == .menubar, let vf = primaryScreen?.visibleFrame,
           let targetMid = menubarTargetMidX() {
            let width = estimatedCoachWidth(for: step)
            let bubbleX = min(max(vf.minX + 8, targetMid - width / 2), vf.maxX - width - 8)
            let rawOffset = targetMid - (bubbleX + width / 2)
            arrowXOffset = max(-(width / 2 - 24), min(width / 2 - 24, rawOffset))
        }
        let view = CoachMarkView(
            step: step,
            arrow: arrow,
            arrowXOffset: arrowXOffset,
            praise: praise,
            stepIndex: step.rawValue,
            totalSteps: OnboardingFlow.Step.allCases.count,
            onNext: { [weak self] in
                guard let self else { return }
                if step == OnboardingFlow.Step.allCases.last {
                    self.finishOnboarding(rememberSkip: true)
                } else {
                    self.onboardingFlow.advance()
                }
            },
            onBack: { [weak self] in self?.onboardingFlow.back() },
            onSkip: { [weak self] in self?.finishOnboarding(rememberSkip: true) }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.frame.size = hosting.fittingSize

        let panel: NSPanel
        if let existing = coachPanel {
            panel = existing
            panel.contentView = hosting
            panel.setContentSize(hosting.frame.size)
        } else {
            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: hosting.frame.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.contentView = hosting
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            coachPanel = panel
        }

        panel.setFrameOrigin(coachOrigin(for: step, size: panel.frame.size, arrow: arrow))
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    /// 引导使用的屏幕：固定主屏（外接副屏时不会飘到副屏）
    private var primaryScreen: NSScreen? { NSScreen.screens.first }

    /// 估算气泡宽度（含内边距），用于在创建视图前先判断箭头方向
    private func estimatedCoachWidth(for step: OnboardingFlow.Step) -> CGFloat {
        (step == .welcome ? 330 : 268) + 22
    }

    /// 箭头方向：根据气泡实际会落在锚点哪一侧决定，保证箭头永远指向目标
    private func coachArrow(for step: OnboardingFlow.Step) -> OnboardingFlow.ArrowDirection {
        guard let vf = primaryScreen?.visibleFrame else { return .none }

        func sideArrow(_ anchor: NSRect?) -> OnboardingFlow.ArrowDirection {
            guard let anchor else { return .none }
            let width = estimatedCoachWidth(for: step)
            // 能放左侧 → 气泡在目标左边，箭头指右；否则气泡在右，箭头指左
            return anchor.minX - width - 14 >= vf.minX + 12 ? .right : .left
        }

        switch step {
        case .welcome: return .none
        case .menubar: return .up
        case .study, .appearance, .rewards, .opacityDemo, .tripleClose:
            return sideArrow(studyPanel.panelFrame)
        case .library: return sideArrow(libraryWindow?.frame)
        case .quiz: return sideArrow(quiz.panelFrame)
        }
    }

    /// 菜单栏图标在主屏菜单栏上的水平中心：
    /// 图标可能被取到副屏坐标（每块屏都有菜单栏），按“距右侧边缘的距离”映射回主屏
    private func menubarTargetMidX() -> CGFloat? {
        guard let iconFrame = statusItem.buttonScreenFrame,
              let primary = primaryScreen else { return nil }
        guard let iconScreen = NSScreen.screens.first(where: { $0.frame.intersects(iconFrame) }),
              iconScreen != primary else {
            return iconFrame.midX   // 本来就在主屏
        }
        let distanceFromRight = iconScreen.frame.maxX - iconFrame.midX
        return primary.frame.maxX - distanceFromRight
    }

    /// 气泡位置：贴近当前步骤要指引的元素（均限制在主屏内）
    private func coachOrigin(for step: OnboardingFlow.Step, size: NSSize,
                             arrow: OnboardingFlow.ArrowDirection) -> NSPoint {
        guard let screen = primaryScreen else { return .zero }
        let vf = screen.visibleFrame

        func besides(_ anchor: NSRect?) -> NSPoint {
            guard let anchor else {
                return NSPoint(x: vf.midX - size.width / 2, y: vf.midY)
            }
            let x: CGFloat = arrow == .right
                ? anchor.minX - size.width - 6
                : min(anchor.maxX + 6, vf.maxX - size.width - 12)
            let y = min(max(vf.minY + 12, anchor.maxY - size.height), vf.maxY - size.height - 12)
            return NSPoint(x: max(vf.minX + 12, x), y: y)
        }

        switch step {
        case .welcome:
            // 主屏正中间：先告知用户入口在菜单栏
            return NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        case .menubar:
            // 图标位置映射到主屏后居中对齐（箭头另有水平偏移兼顾贴边情况）
            if let targetMid = menubarTargetMidX() {
                let x = min(max(vf.minX + 8, targetMid - size.width / 2),
                            vf.maxX - size.width - 8)
                return NSPoint(x: x, y: vf.maxY - size.height - 4)
            }
            return NSPoint(x: vf.maxX - size.width - 30, y: vf.maxY - size.height - 6)
        case .study, .appearance, .rewards, .opacityDemo, .tripleClose:
            return besides(studyPanel.panelFrame)
        case .library:
            return besides(libraryWindow?.frame)
        case .quiz:
            return besides(quiz.panelFrame)
        }
    }

    // MARK: - 词详情

    /// 双击词库词条弹出详情窗口（独立窗口，比 sheet 更稳定）
    func showWordDetail(_ item: StudyItem) {
        // 同一单词已打开：聚焦已有窗口，不重复创建
        if wordDetailHeadword == item.word.headword, let panel = wordDetailWindow {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        // 每次双击创建新窗口（不重用 contentViewController，避免替换时释放冲突导致的崩溃）
        let panel = TripleClickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = item.word.headword
        // 标题栏/顶栏三连击关闭详情
        panel.onTripleClick = { [weak panel] in
            panel?.orderOut(nil)
            WordDetailState.shared.headword = nil
        }
        panel.contentViewController = NSHostingController(
            rootView: WordDetailView(item: item, onClose: { [weak panel] in
                panel?.orderOut(nil)
                WordDetailState.shared.headword = nil
            }))
        panel.isReleasedWhenClosed = false
        // 置顶（高于菜单栏 popover 层级，不被背词面板遮挡）
        panel.level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 1)
        panel.center()
        wordDetailWindow = panel
        wordDetailHeadword = item.word.headword
        observeClose(of: panel) { [weak self] in
            // 仅当关闭的是当前记录窗口时清空（避免误清其他窗口的引用）
            if self?.wordDetailWindow === panel {
                self?.wordDetailWindow = nil
                self?.wordDetailHeadword = nil
            }
            WordDetailState.shared.headword = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        WordDetailState.shared.headword = item.word.headword
    }

    // MARK: - 词库页

    func showLibrary() {
        // 已打开则不重复创建，直接置顶
        if let window = libraryWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        // TripleClickPanel：顶栏三击关闭（与游戏窗口一致）
        let window = TripleClickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "词库 · 熟悉度"
        window.contentViewController = NSHostingController(rootView: LibraryView(database: database))
        window.isReleasedWhenClosed = false
        window.onTripleClick = { [weak window] in
            window?.orderOut(nil)
        }
        // 固定在主屏居中（外接副屏时不飘走）
        if let vf = primaryScreen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: vf.midX - 310, y: vf.midY - 280))
        } else {
            window.center()
        }
        libraryWindow = window
        observeClose(of: window) { [weak self] in
            self?.libraryWindow = nil
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 爬塔小游戏

    private lazy var towerEngine = TowerGameEngine(database: database)

    /// 启动时后台预热修仙塔词库（避免首次进入游戏/继续修仙路卡顿）
    private func prewarmTowerPool() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self, let db = self.database as? AppDatabase else { return }
            let items = (try? db.allItems()) ?? []
            let sorted = items.sorted { a, b in
                let sa = a.card != nil ? 0 : 1
                let sb = b.card != nil ? 0 : 1
                if sa != sb { return sa < sb }
                let fa = a.word.frequency ?? Int.max
                let fb = b.word.frequency ?? Int.max
                return fa < fb
            }
            let words = sorted.map(\.word)
            var counts: [String: Int] = [:]
            var catWords: [String: [Word]] = [:]
            for word in words {
                let lower = word.definitionCn.lowercased()
                for category in WordCategory.all where category.matches(definitionLowercased: lower) {
                    counts[category.id, default: 0] += 1
                    catWords[category.id, default: []].append(word)
                }
            }
            await MainActor.run {
                self.towerEngine.injectPool(words, counts: counts, categoryWords: catWords)
            }
        }
    }

    func showTowerGame() {
        // 已打开则直接置顶
        if let window = gameWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        towerEngine.openGame()
        towerEngine.grantAllItemsIfNeeded()
        towerEngine.ensureDemon()
        towerEngine.resumeBattleTimer()
        // TripleClickPanel：顶栏三击关闭，关闭时保存进度
        let window = TripleClickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "爬塔挑战 · 遗忘之塔"
        window.contentViewController = NSHostingController(rootView: TowerGameView(engine: towerEngine))
        window.isReleasedWhenClosed = false
        // 顶栏三连击：保存进度后关闭
        window.onTripleClick = { [weak window] in
            self.towerEngine.saveProgressNow()
            window?.orderOut(nil)
        }
        if let vf = primaryScreen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: vf.midX - 240, y: vf.midY - 300))
        } else {
            window.center()
        }
        gameWindow = window
        isGameOpen = true
        updateAmbientSuppression()
        observeClose(of: window) { [weak self] in
            self?.towerEngine.pauseBattleTimer()
            self?.gameWindow = nil
            self?.isGameOpen = false
            self?.updateAmbientSuppression()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 练习浮层

    func toggleQuizOverlay() {
        quiz.toggle()
    }

    // MARK: - 工具

    
    // MARK: - 数据导出/导入

    /// 导出：先弹勾选对话框 → 保存面板 → 写 JSON
    func showExportDataDialog() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "选择要导出的数据"
        let settingsBox = NSButton(checkboxWithTitle: "设置", target: nil, action: nil)
        let vocabBox = NSButton(checkboxWithTitle: "词库熟练度与成就", target: nil, action: nil)
        let rewardsBox = NSButton(checkboxWithTitle: "目标与自我激励", target: nil, action: nil)
        let gameBox = NSButton(checkboxWithTitle: "游戏进度", target: nil, action: nil)
        let boxes = [settingsBox, vocabBox, rewardsBox, gameBox]
        boxes.forEach { $0.state = .on }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: CGFloat(boxes.count) * 24 + 3 * 8)
        alert.accessoryView = stack
        alert.addButton(withTitle: "导出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSApp.activate(ignoringOtherApps: true)

        do {
            let data = try DataTransferManager.shared.exportData(
                includeSettings: settingsBox.state == .on,
                includeVocabulary: vocabBox.state == .on,
                includeRewards: rewardsBox.state == .on,
                includeGame: gameBox.state == .on)
            let panel = NSSavePanel()
            panel.title = "导出 DailyWord 数据"
            let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            panel.nameFieldStringValue = "DailyWord备份-\(stamp).json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                debugLog("导出成功: \(url.path)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.showInfoAlert(title: "导出成功", message: "数据已保存到 \(url.lastPathComponent)")
                }
            } catch {
                debugLog("导出失败: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.showInfoAlert(title: "导出失败", message: error.localizedDescription)
                }
            }
        } catch {
            debugLog("导出组装失败: \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showInfoAlert(title: "导出失败", message: error.localizedDescription)
            }
        }
    }

    /// 导入：确认覆盖 → 打开面板 → 读取 JSON → 应用 → 提示
    func showImportDataDialog() {
        NSApp.activate(ignoringOtherApps: true)
        if !UserDefaults.standard.bool(forKey: "importConfirmDismissed") {
            let confirm = NSAlert()
            confirm.messageText = "导入将覆盖现有数据"
            confirm.informativeText = "词库熟练度使用取并集方式（不覆盖本地已有熟练度）；设置、成就、游戏进度等将完全覆盖。是否继续？"
            let checkbox = NSButton(checkboxWithTitle: "不再提示", target: nil, action: nil)
            checkbox.state = .off
            confirm.accessoryView = checkbox
            confirm.addButton(withTitle: "导入")
            confirm.addButton(withTitle: "取消")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
            if checkbox.state == .on {
                UserDefaults.standard.set(true, forKey: "importConfirmDismissed")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        let panel = NSOpenPanel()
        panel.title = "导入 DailyWord 数据"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try DataTransferManager.shared.importData(data)
            if imported.contains("设置") {
                let oldKey = AppSettings.shared.currentCollectionKey
                AppSettings.shared.reloadFromDefaults()
                registerHotKeys()
                if AppSettings.shared.currentCollectionKey != oldKey {
                    session.collectionKey = AppSettings.shared.currentCollectionKey
                    session.start()
                    quiz.engine.reloadPool()
                }
                ambient.checkNow()
            }
            refreshAfterImport()
            var message = imported.isEmpty ? "文件为空或格式不符" : "已导入：" + imported.joined(separator: "、")
            if imported.contains("游戏进度") {
                message += "\n游戏进度将在重启应用后完全生效"
            }
            if imported.contains("目标与自我激励") && !imported.contains("词库熟练度与成就") {
                message += "\n提示：等级/经验/成就进度来自词库熟练度与成就数据（复习记录），需同时导入该项才能完整恢复"
            }
            showInfoAlert(title: "导入成功", message: message)
        } catch {
            showInfoAlert(title: "导入失败", message: "文件格式不正确或数据损坏")
        }
    }

    private func showInfoAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }



    /// 联网查单词例句（FreeDictionary API），结果缓存到 UserDefaults
    func fetchSentences(for word: String) async -> [String] {
        let key = word.lowercased()
        // 读缓存
        if let data = UserDefaults.standard.data(forKey: "sentences_\(key)"),
           let cached = try? JSONSerialization.jsonObject(with: data) as? [String],
           !cached.isEmpty {
            return cached
        }
        // 联网
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(key)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                var sentences: [String] = []
                for entry in json {
                    if let meanings = entry["meanings"] as? [[String: Any]] {
                        for m in meanings {
                            if let defs = m["definitions"] as? [[String: Any]] {
                                for d in defs {
                                    if let ex = d["example"] as? String {
                                        sentences.append(ex)
                                    }
                                }
                            }
                        }
                    }
                }
                let unique = Array(Set(sentences)).prefix(5).map { $0 }
                // 缓存
                if !unique.isEmpty, let d = try? JSONSerialization.data(withJSONObject: unique) {
                    UserDefaults.standard.set(d, forKey: "sentences_\(key)")
                }
                return unique
            }
        } catch {}
        return []
    }

    /// 高频不规则动词变形表（例句词 → 原形）
    private static let irregularForms: [String: String] = [
        "went": "go", "gone": "go", "did": "do", "done": "do", "was": "be", "were": "be", "been": "be",
        "had": "have", "has": "have", "made": "make", "took": "take", "taken": "take", "gave": "give",
        "given": "give", "came": "come", "saw": "see", "seen": "see", "said": "say", "got": "get",
        "gotten": "get", "found": "find", "thought": "think", "knew": "know", "known": "know",
        "left": "leave", "felt": "feel", "kept": "keep", "met": "meet", "told": "tell", "spoke": "speak",
        "spoken": "speak", "wrote": "write", "written": "write", "brought": "bring", "bought": "buy",
        "caught": "catch", "taught": "teach", "heard": "hear", "held": "hold", "stood": "stand",
        "understood": "understand", "sat": "sit", "ran": "run", "began": "begin", "begun": "begin",
        "broke": "break", "broken": "break", "chose": "choose", "chosen": "choose", "drove": "drive",
        "driven": "drive", "ate": "eat", "eaten": "eat", "fell": "fall", "fallen": "fall",
        "forgot": "forget", "forgotten": "forget", "flew": "fly", "flown": "fly", "grew": "grow",
        "grown": "grow", "hid": "hide", "hidden": "hide", "lost": "lose", "paid": "pay", "rose": "rise",
        "risen": "rise", "sent": "send", "shook": "shake", "shaken": "shake", "shot": "shoot",
        "slept": "sleep", "spent": "spend", "threw": "throw", "thrown": "throw", "woke": "wake",
        "woken": "wake", "wore": "wear", "worn": "wear", "won": "win", "drank": "drink", "drunk": "drink",
        "sang": "sing", "sung": "sing", "swam": "swim", "swum": "swim", "rode": "ride", "ridden": "ride",
        "froze": "freeze", "frozen": "freeze", "stole": "steal", "stolen": "steal", "built": "build",
        "learnt": "learn", "learned": "learn", "spelt": "spell", "spelled": "spell", "hung": "hang",
        "lit": "light", "meant": "mean", "sold": "sell", "fed": "feed", "led": "lead", "read": "read",
        "wept": "weep", "bred": "breed", "tore": "tear", "torn": "tear",
        "bore": "bear", "borne": "bear", "swore": "swear", "sworn": "swear", "forbade": "forbid",
        "forbidden": "forbid", "shone": "shine", "sank": "sink", "sunk": "sink", "struck": "strike",
        "withdrew": "withdraw", "withdrawn": "withdraw",
    ]

    /// 判断例句单词是否与目标词匹配（精确或变形）
    static func isWordMatch(_ candidate: String, word: String) -> Bool {
        let c = candidate.lowercased()
        let t = word.lowercased()
        if c == t { return true }
        // 不规则变形
        if let base = irregularForms[c] { return base == t }
        // 规则后缀变形（abandon → abandoned/abandons/abandoning）
        if c.hasPrefix(t) {
            let suffix = String(c.dropFirst(t.count))
            let suffixes: Set<String> = ["s", "es", "ed", "d", "ing", "er", "est", "ly",
                                         "ment", "ness", "tion", "sion", "ful", "less",
                                         "ous", "ive", "able", "ible", "al", "ial", "ity", "ies"]
            if suffixes.contains(suffix) { return true }
            // 双写辅音 + ing/ed（run → running）
            if suffix.hasSuffix("ing") || suffix.hasSuffix("ed") {
                let cut = suffix.hasSuffix("ing") ? 3 : 2
                let stem = String(c.dropLast(cut))
                if stem.count >= 2 && String(stem.dropLast()) == t { return true }
            }
        }
        // y → ies（study → studies）
        if c.hasSuffix("ies") {
            let stem = String(c.dropLast(3)) + "y"
            if stem == t { return true }
        }
        return false
    }

    /// 例句高亮显示（精确或变形匹配，加粗橙色）
    static func highlightedSentence(_ sentence: String, word: String) -> Text {
        var result = Text("")
        guard let regex = try? NSRegularExpression(pattern: "[a-zA-Z']+") else {
            return Text(sentence)
        }
        let ns = NSRange(sentence.startIndex..., in: sentence)
        let matches = regex.matches(in: sentence, range: ns)
        var lastEnd = sentence.startIndex
        for m in matches {
            guard let range = Range(m.range, in: sentence) else { continue }
            result = result + Text(String(sentence[lastEnd..<range.lowerBound]))
            let candidate = String(sentence[range])
            if isWordMatch(candidate, word: word) {
                result = result + Text(candidate).bold().foregroundColor(.orange)
            } else {
                result = result + Text(candidate)
            }
            lastEnd = range.upperBound
        }
        if lastEnd < sentence.endIndex {
            result = result + Text(String(sentence[lastEnd...]))
        }
        return result
    }


        private func makeWindow<V: View>(title: String, rootView: V) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    private func observeClose(of window: NSWindow, handler: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in handler() }
        }
    }
}
