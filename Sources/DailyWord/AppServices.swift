import AppKit
import Carbon.HIToolbox
import Combine
import ObjectiveC
import SwiftUI
import DailyWordCore

/// 全局服务容器：App 入口和 AppDelegate 共享数据库、会话与各窗口/浮层控制器
/// 单词详情窗口打开状态（@Published 驱动背词面板灯泡即时刷新）
final class WordDetailState: ObservableObject {
    static let shared = WordDetailState()
    @Published var headword: String?
    private init() {}
}

/// 观察者跟随窗口释放，不让关闭回调留在全局通知中心。
private final class WindowCloseObservation {
    private var token: NSObjectProtocol?
    @MainActor
    init(window: NSWindow, handler: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                       object: window, queue: .main) { _ in
            Task { @MainActor in handler() }
        }
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
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

    private var onboardingRewardsWindow: NSPanel?
    private var onboardingDemoWindow: NSPanel?
    private let onboardingDemo = OnboardingDemoModel()
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
    private var coachPanel: CoachMarkPanel?
    private var coachPresentationTask: Task<Void, Never>?
    private var coachAdvanceTask: Task<Void, Never>?
    private var coachObservers: [AnyCancellable] = []
    private weak var coachLastTargetWindow: NSWindow?
    private enum CoachSurface: Hashable { case study, quiz, library, settings, rewards }
    private var coachOwnedWindows: [CoachSurface: NSWindow] = [:]
    private var hotKeys: [GlobalHotKey] = []
    private var hotKeyRecordingOwner: UUID?
    private var localPanelClickMonitor: Any?
    private var globalPanelClickMonitor: Any?
    private static var closeObservationKey: UInt8 = 0
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
            self?.renderCoachMark()
        }
        self.onboardingFlow.onStepChanged = { [weak self] _ in
            self?.prepareOnboardingStep()
        }
        self.onboardingFlow.onCelebrate = { [weak self] _ in
            guard let self, self.onboardingFlow.isActive else { return }
            // 只刷新鼓励文案，不重新打开本步窗口，也不抢走输入焦点。
            self.renderCoachMark()
            self.coachAdvanceTask?.cancel()
            let token = self.onboardingFlow.revision
            self.coachAdvanceTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 1_600_000_000) } catch { return }
                guard let self, self.onboardingFlow.celebrating else { return }
                self.onboardingFlow.advance(ifCurrent: token)
            }
        }
        self.studyPanel = StudyPanelController(session: session)
        self.studyPanel.onVisibilityChanged = { [weak self] in
            guard let self else { return }
            self.setStudyOpen(self.studyPanel.isVisible)
            // 翻译监听只依赖翻译窗口，不由学习面板开启。
            self.refreshTranslateSync()
            self.renderCoachMark()
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
        #if DEBUG
        // 调试：DAILYWORD_ONBOARDING_STEP=study 等直接进入指定引导步骤，用于复现气泡定位。
        if let raw = ProcessInfo.processInfo.environment["DAILYWORD_ONBOARDING_STEP"]?.lowercased(),
           let target = OnboardingFlow.Step.allCases.first(where: { "\($0.rawValue)" == raw || String(describing: $0) == raw }) {
            showOnboarding()
            while onboardingFlow.step != target {
                onboardingFlow.advance(ifCurrent: onboardingFlow.revision)
            }
        } else {
            showOnboardingIfNeeded()
        }
        #else
        showOnboardingIfNeeded()
        #endif
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
    func beginHotKeyRecording(_ owner: UUID) {
        hotKeyRecordingOwner = owner
        hotKeys = []   // 已绑定的全局键也必须交给录制器，而不是执行原动作。
    }

    func endHotKeyRecording(_ owner: UUID) {
        guard hotKeyRecordingOwner == owner else { return }
        hotKeyRecordingOwner = nil
        registerHotKeys()
    }

    func registerHotKeys() {
        hotKeys = []
        guard hotKeyRecordingOwner == nil else { return }
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
                debugLog("热键注册成功: \(action.rawValue) key=\(binding.keyCode) mods=\(binding.modifiers)")
            } else {
                // 自查日志：注册失败（如与系统快捷键冲突）
                NSLog("[热键] 注册失败: \(action.rawValue) keyCode=\(binding.keyCode) mods=\(binding.modifiers)")
                debugLog("热键注册失败: \(action.rawValue) key=\(binding.keyCode) mods=\(binding.modifiers)")
            }
        }
    }

    /// 执行快捷键动作
    func perform(_ action: HotKeyAction) {
        guard hotKeyRecordingOwner == nil else { return }
        debugLog("快捷键触发: \(action.rawValue)")
        if performOnboardingAction(action) { return }
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
    private var selectionState = SelectionTranslationState()
    private var selectionReadTask: Task<Void, Never>?
    private let selectionReadQueue = DispatchQueue(label: "DailyWord.selectionReader", qos: .userInitiated)
    private var selectionSourcePID: pid_t?
    private var selectionIsReading = false
    private var translateKeyMonitor: Any?

    /// 划词翻译：读取当前选中文本 → 翻译 → 浮窗显示；再次按快捷键隐藏
    private func translateSelection() {
        if selectionState.isOpen {
            closeTranslateResult()
            return
        }
        guard ensureAccessibilityPermission() else { return }
        selectionSourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        selectionState.open()
        showNetworkHintIfNeeded()
        updateTranslateResult(source: "", sourceLines: ["等待选中文本"],
                              targetLines: ["窗口打开期间，选中文本会自动更新"])
        performSelectionTranslation()
    }

    /// 显式重试会回到上一次取词的应用，不读取翻译浮窗自己的文本。
    func retrySelectionTranslation() {
        guard selectionState.isOpen, let pid = selectionSourcePID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: .activateIgnoringOtherApps)
        requestSelection(pid: pid, explicit: true)
    }

    private func performSelectionTranslation() {
        guard let pid = selectionSourcePID, pid != ProcessInfo.processInfo.processIdentifier else { return }
        requestSelection(pid: pid, explicit: true)
    }

    /// 每个新选中产生独立令牌；去抖只合并同一轮连续事件，不丢弃快速选择的新词。
    private func requestSelection(pid: pid_t, explicit: Bool = false, copiedAfter: Int? = nil) {
        guard selectionState.isOpen, let request = selectionState.beginRequest(preservingClipboard: copiedAfter != nil) else { return }
        selectionReadTask?.cancel()
        selectionSourcePID = pid
        selectionIsReading = true
        selectionReadTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            guard let self, self.selectionState.accepts(request) else { return }
            self.selectionReadQueue.async { [weak self] in
                guard SelectedTextReader.validTarget(pid, request: request) else { return }
                var acquired: String?
                if let count = copiedAfter {
                    acquired = SelectedTextReader.newlyCopiedText(after: count, pid: pid, request: request)
                } else {
                    for attempt in 0..<2 where !request.isCancelled {
                        switch SelectedTextReader.accessibility(pid: pid, request: request) {
                        case .text(let text): acquired = text
                        case .empty: break
                        case .unavailable:
                            if attempt == 1 { acquired = SelectedTextReader.copySelection(pid: pid, request: request) }
                        }
                        if acquired != nil { break }
                        if attempt == 0 { Thread.sleep(forTimeInterval: 0.12) }
                    }
                }
                let text = acquired
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.selectionState.accepts(request) else { return }
                    self.selectionIsReading = false
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.handleAcquiredText(text, request: request)
                    } else if explicit || self.lastTranslatedText.isEmpty {
                        self.lastTranslatedText = ""
                        self.updateTranslateResult(source: "", sourceLines: ["未获取到选中文本"],
                                                   targetLines: ["请选中要翻译的文本，窗口会自动更新"])
                    } else {
                        self.updateTranslateResult(source: self.lastTranslatedText,
                                                   sourceLines: TranslationService.shared.splitSentences(self.lastTranslatedText),
                                                   targetLines: ["未读取到新的选区，已保留原文；可重新选中后重试"])
                    }
                }
            }
        }
    }

    private func handleAcquiredText(_ text: String, request: TranslationRequest) {
        guard selectionState.accepts(request) else { return }
        lastTranslatedText = text
        let sourceLines = TranslationService.shared.splitSentences(text)
        updateTranslateResult(source: text, sourceLines: sourceLines, targetLines: ["翻译中…"])
        TranslationService.shared.translateSentences(text, request: request) { [weak self] translated, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectionState.accepts(request), self.translateResultPanel != nil else { return }
                let message = error == .noNetwork ? "网络未连接，请检查网络后重试" : "翻译失败，请重试"
                self.updateTranslateResult(source: text, sourceLines: sourceLines, targetLines: translated ?? [message])
            }
        }
    }

    /// 首次使用翻译功能时提醒需要联网（只提醒一次）
    /// 注意：不能用 NSAlert.runModal()——菜单栏应用无主窗口时模态弹窗不显示却会阻塞主线程，
    /// 导致翻译窗口打不开、界面卡死。改为非阻塞（浮窗内已有网络错误提示兜底）。
    private func showNetworkHintIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "translationNetworkHintShown") else { return }
        UserDefaults.standard.set(true, forKey: "translationNetworkHintShown")
        debugLog("首次翻译：提示需要联网（非阻塞，不弹模态窗）")
    }

    /// 最近一次鼠标按下位置（全局坐标，用于区分"拖选"与"单击定位"）
    private var mouseDownLocation: NSPoint?
    /// 最近一次左键按下的 clickCount（全局 leftMouseDown 事件中可靠，用于检测双击/三击选词）
    private var mouseDownClickCount: Int = 0
    private var mouseDownPID: pid_t?
    private var mouseDownMonitor: Any?

    /// 监听仅存在于主动打开的翻译会话，内容刷新不重新安装监听器。
    private func startTranslateSync() {
        guard selectionState.isOpen, translateClickMonitor == nil else { return }
        // 按下时记录位置和点击次数——双击/三击是明确选词手势
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.mouseDownLocation = NSEvent.mouseLocation
            self?.mouseDownClickCount = event.clickCount
            self?.mouseDownPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            // 新点击使尚未完成的取词失效，但不取消已在翻译的当前文本。
            if self?.selectionIsReading == true { self?.selectionState.current?.cancel() }
        }
        translateClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            // 右键菜单 → 无选中意图，直接跳过
            let hasSelectionGesture: Bool
            if event.type == .rightMouseUp {
                hasSelectionGesture = false
            } else {
                let mouse = NSEvent.mouseLocation
                // 拖选距离（按下位置与松开位置差，>30pt 才算有效拖选，过滤 PDF/IDE 中点击微位移）
                let dragDistance = self?.mouseDownLocation.map { hypot($0.x - mouse.x, $0.y - mouse.y) } ?? 0
                // 双击/三击选词（clickCount 在 leftMouseDown 中可靠）
                let isMultiClick = (self?.mouseDownClickCount ?? 0) >= 2
                hasSelectionGesture = (dragDistance > 30 || isMultiClick)
                    && self?.mouseDownPID == NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
            // 关键：用完立即重置按下状态——防止上一次双击/拖选的残留值
            // 被下一次单击误判为"选中手势"（"翻译后马上又跳成复制内容"的根因）
            self?.mouseDownLocation = nil
            self?.mouseDownClickCount = 0
            self?.mouseDownPID = nil
            self?.syncSelection(hasSelectionGesture: hasSelectionGesture)
        }
        translateKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.selectionState.isOpen, !event.isARepeat,
                  let cgEvent = event.cgEvent,
                  cgEvent.getIntegerValueField(.eventSourceUserData) != SelectedTextReader.syntheticCopyTag,
                  let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.type == .keyDown, event.keyCode == 8, flags == .command {
                // 只观察真实复制前后的变化，不轮询或翻译历史剪贴板。
                SelectedTextReader.interruptCopy()
                let baseline = NSPasteboard.general.changeCount
                self.requestSelection(pid: pid, copiedAfter: baseline)
            } else if event.type == .keyUp,
                      (event.keyCode == 0 && flags == .command) ||
                      (flags.contains(.shift) && [123, 124, 125, 126].contains(Int(event.keyCode))) {
                self.requestSelection(pid: pid)
            }
        }
    }

    private func stopTranslateSync() {
        if let monitor = translateClickMonitor {
            NSEvent.removeMonitor(monitor)
            translateClickMonitor = nil
        }
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = translateKeyMonitor { NSEvent.removeMonitor(monitor) }
        translateKeyMonitor = nil
        mouseDownLocation = nil
        mouseDownClickCount = 0
        mouseDownPID = nil
    }

    /// 按"翻译浮窗是否存在"刷新监听：
    /// 仅当浮窗打开时才监听选中（实时刷新内容）；浮窗关闭后不再响应选中，
    /// 避免打卡窗口开着时误选文本就自动弹窗（需翻译请按快捷键或点浮窗 ↻）
    private func refreshTranslateSync() {
        if selectionState.isOpen, translateResultPanel != nil {
            startTranslateSync()
        } else {
            stopTranslateSync()
        }
    }

    private func syncSelection(hasSelectionGesture: Bool = false) {
        guard selectionState.isOpen, let panel = translateResultPanel, hasSelectionGesture,
              !panel.frame.contains(NSEvent.mouseLocation),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier else { return }
        requestSelection(pid: pid)
    }

    /// 创建或更新划词翻译浮窗（双语对照，可拖动、可调大小）
    private func updateTranslateResult(source: String, sourceLines: [String], targetLines: [String]) {
        guard selectionState.isOpen else { return }
        debugLog("[翻译] 更新当前请求，原文字符数=\(source.count)")
        let view = TranslateResultView(source: source,
                                       sourceLines: sourceLines,
                                       targetLines: targetLines,
                                       onClose: { [weak self] in self?.closeTranslateResult() },
                                       onReset: { [weak self] in
            (self?.translateResultPanel as? ResizableTranslatePanel)?.resetToDefaultSize()
        },
                                       onRetry: { [weak self] in self?.retrySelectionTranslation() })
        if let hosting = translateHostingController {
            // 复用面板：直接更新内容
            hosting.rootView = view
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
        refreshTranslateSync()   // 浮窗打开 → 启动选中监听（实时刷新内容）
        observeClose(of: panel) { [weak self, weak panel] in
            guard let self, let panel, self.translateResultPanel === panel else { return }
            self.closeTranslateResult()
        }
        // 显示结果不激活本应用，保留源应用的选区与复制目标。
        panel.orderFrontRegardless()
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
        SelectedTextReader.interruptCopy()
        selectionState.close()
        selectionReadTask?.cancel()
        selectionReadTask = nil
        selectionIsReading = false
        lastTranslatedText = ""
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
        if let panel = translateInputPanel {
            debugLog("toggle 分支：关闭现有输入翻译")
            panel.orderOut(nil)
            translateInputPanel = nil
            return
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
        panel.level = NSWindow.Level(NSWindow.Level.popUpMenu.rawValue + 1)
        panel.center()
        translateInputPanel = panel
        observeClose(of: panel) { [weak self, weak panel] in
            guard let self, let panel, self.translateInputPanel === panel else { return }
            self.translateInputPanel = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        debugLog("输入翻译显示 isVisible=\(panel.isVisible) frame=\(panel.frame) level=\(panel.level.rawValue)")
    }

    private func closeTranslateInput() {
        translateInputPanel?.orderOut(nil)
        translateInputPanel = nil
    }

    /// 辅助功能权限检查（划词翻译需要）
    private func ensureAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        return trusted
    }

    /// 快捷键操作目标：焦点（key window）在哪个面板就作用哪个面板
    private enum HotKeyTarget {
        case quiz       // 测试面板
        case study      // 学习面板（⌥W 浮动面板 / 菜单栏弹窗）
    }

    /// 用户最后点击/激活的面板（nonactivating 窗口不成为 key，需用点击记录兜底）
    private var lastHotKeyTarget: HotKeyTarget = .study

    /// 当前快捷键作用的面板：优先 key window 判断，其次面板可见性，最后最近点击
    private var hotKeyTarget: HotKeyTarget {
        if let key = NSApp.keyWindow {
            if key === quiz.window { return .quiz }
            if key === studyPanel.window || key === statusItem.popoverWindow { return .study }
        }
        // nonactivating 面板（NSPopover 等）不成为 keyWindow：按可见性判断
        if studyPanel.isVisible || statusItem.popoverWindow != nil { return .study }
        if quiz.isVisible { return .quiz }
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
        if let monitor = localPanelClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalPanelClickMonitor { NSEvent.removeMonitor(monitor) }
        localPanelClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.recordClickTarget() }
            return event   // 不拦截，继续传递
        }
        globalPanelClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.recordClickTarget() }
        }
    }

    /// 移动当前焦点所在的浮动面板（测试面板或 ⌥W 学习面板）
    private func movePanel(dx: CGFloat, dy: CGFloat) {
        let target = hotKeyTarget
        debugLog("移动: target=\(target == .quiz ? "quiz" : "study") dx=\(dx) dy=\(dy)")
        switch target {
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

    /// 后台线程可用的文件日志（nonisolated 方法不能调 MainActor 的 debugLog）
    nonisolated private static func fileLog(_ message: String) {
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
        let target = hotKeyTarget
        debugLog("透明度: target=\(target == .quiz ? "quiz" : "study") delta=\(delta)")
        switch target {
        case .quiz: AppSettings.shared.adjustQuizOpacity(by: delta)
        case .study: AppSettings.shared.adjustStudyOpacity(by: delta)
        }
    }

    /// 跳转顶层显示：激活 App 并弹出指引气泡
    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        showOnboarding()
    }

    /// 独立设置窗口：避免系统颜色面板与 popover 的窗口层级冲突
    /// 每次打开重建 hosting 视图（避免 SwiftUI AttributeGraph 状态长期复用导致偶发崩溃）
    func showSettingsWindow() {
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
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
        // 位置：学习面板（菜单栏弹窗或 ⌥W 浮动面板）打开时，显示在其左侧；否则居中
        let anchorWindow = studyPanel.window ?? statusItem.popoverWindow
        let screen = anchorWindow?.screen ?? NSScreen.screens.first { $0.visibleFrame.contains(NSEvent.mouseLocation) } ?? primaryScreen
        if let screen {
            let vf = screen.visibleFrame
            var origin = NSPoint(x: vf.midX - panel.frame.width / 2, y: vf.midY - panel.frame.height / 2)
            if let anchor = anchorWindow?.frame {
                origin = NSPoint(x: anchor.minX - panel.frame.width - 12, y: anchor.midY - panel.frame.height / 2)
                if origin.x < vf.minX { origin.x = anchor.maxX + 12 }
            }
            panel.setFrame(WindowPlacement.clampedFrame(NSRect(origin: origin, size: panel.frame.size), in: vf), display: false)
        } else { panel.center() }
        panel.makeKeyAndOrderFront(nil)
        // 仅打开时置顶（不改变常驻层级），确保不被学习面板等 floating 窗口遮挡
        panel.orderFrontRegardless()
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
        // 其他窗口的开合不能新建翻译会话。
        refreshTranslateSync()
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
        if onboardingFlow.isActive {
            renderCoachMark(focus: true)
            return
        }
        isOnboardingOpen = true
        onboardingDemo.state = OnboardingDemoState()
        updateAmbientSuppression()
        installCoachObservers()
        onboardingFlow.start(skipOnNextLaunch: UserDefaults.standard.bool(forKey: Self.hideOnboardingKey))
    }

    private func finishOnboarding(rememberSkip: Bool) {
        coachPresentationTask?.cancel()
        coachAdvanceTask?.cancel()
        coachPresentationTask = nil
        coachAdvanceTask = nil
        onboardingFlow.stop()
        coachObservers.removeAll()
        UserDefaults.standard.set(rememberSkip, forKey: Self.hideOnboardingKey)
        coachPanel?.onDismiss = nil
        coachPanel?.orderOut(nil)
        coachPanel = nil
        closeCoachWindows(except: nil)
        isOnboardingOpen = false
        updateAmbientSuppression()
    }

    private func coachSurface(for step: OnboardingFlow.Step) -> CoachSurface? {
        switch step {
        case .study, .opacityDemo, .movement, .tripleClose: return .study
        case .library: return .library
        case .quiz: return .quiz
        case .appearance: return .settings
        case .rewards: return .rewards
        default: return nil
        }
    }

    /// 只清理由引导创建或重新显示的窗口，不关闭用户原先打开的界面。
    private func closeCoachWindows(except surface: CoachSurface?) {
        for (kind, window) in Array(coachOwnedWindows) where kind != surface {
            coachOwnedWindows[kind] = nil
            switch kind {
            case .study, .quiz:
                if onboardingDemoWindow === window {
                    window.orderOut(nil)
                    onboardingDemoWindow = nil
                }
            case .library:
                if libraryWindow === window { window.close() }
            case .settings:
                window.orderOut(nil)
            case .rewards:
                window.close()
                if onboardingRewardsWindow === window { onboardingRewardsWindow = nil }
            }
        }
    }

    private func showOnboardingDemo(isQuiz: Bool) {
        if let window = onboardingDemoWindow { window.makeKeyAndOrderFront(nil); return }
        // 练习演示尺寸随字号同正式浮层公式；背单词演示与学习面板一致。
        let quizFont = AppSettings.shared.quizFontSize
        let contentSize = isQuiz
            ? NSSize(width: min(720, max(440, 260 + quizFont * 11)), height: 118 + quizFont * 3.4 + 56)
            : NSSize(width: 340, height: 470)
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: contentSize),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        let hosting = NSHostingView(rootView: OnboardingDemoView(model: onboardingDemo, flow: onboardingFlow, isQuiz: isQuiz) { [weak self, weak panel] triple in
            guard let self, let panel, self.onboardingDemoWindow === panel else { return }
            self.closeOnboardingDemo()
            if triple && !isQuiz { self.onboardingFlow.notifyTripleClosed() }
        })
        hosting.sizingOptions = []
        hosting.frame.size = contentSize
        panel.contentView = hosting
        panel.center()
        onboardingDemoWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func closeOnboardingDemo() {
        onboardingDemoWindow?.orderOut(nil)
        onboardingDemoWindow = nil
        renderCoachMark()
    }

    /// 教程窗口获得焦点时，常用快捷键只操作演示，不影响真实学习和持久化设置。
    private func performOnboardingAction(_ action: HotKeyAction) -> Bool {
        guard onboardingFlow.isActive, let window = onboardingDemoWindow, window.isVisible,
              NSApp.keyWindow === window || NSApp.keyWindow === coachPanel else { return false }
        switch action {
        case .revealWord: onboardingDemo.state.flip()
        case .speak: SpeechService.shared.speak(OnboardingDemoState.word)
        case .togglePanel, .toggleQuiz: closeOnboardingDemo()
        case .opacityUp, .opacityDown:
            if onboardingDemo.state.adjustOpacity(action == .opacityUp ? 0.08 : -0.08) {
                onboardingFlow.notifyOpacityChanged()
            }
        case .panelLeft, .panelRight, .panelUp, .panelDown:
            let dx: CGFloat = action == .panelLeft ? -24 : (action == .panelRight ? 24 : 0)
            let dy: CGFloat = action == .panelDown ? -24 : (action == .panelUp ? 24 : 0)
            let frame = window.frame
            let desired = frame.offsetBy(dx: dx, dy: dy)
            let next = window.screen.map { WindowPlacement.clampedFrame(desired, in: $0.visibleFrame) } ?? desired
            window.setFrame(next, display: true)
            if frame != next { onboardingFlow.notifyPanelMoved() }
        case .showWordDetail:
            return true   // 示例不是词库记录，不能跳到当前真实学习词的详情。
        default: return false
        }
        return true
    }

    /// 切步时才展示目标；迟到的展示任务与自动推进都必须匹配当前步骤令牌。
    private func prepareOnboardingStep() {
        guard onboardingFlow.isActive else { return }
        coachPresentationTask?.cancel()
        coachAdvanceTask?.cancel()
        let token = onboardingFlow.revision
        let surface = coachSurface(for: onboardingFlow.step)
        closeCoachWindows(except: surface)
        let before = coachTargetWindow
        let wasVisible = before?.isVisible == true
        switch surface {
        case .study, .quiz: showOnboardingDemo(isQuiz: surface == .quiz)
        case .library: showLibrary()
        case .settings:
            if let settingsWindow, settingsWindow.isVisible {
                settingsWindow.makeKeyAndOrderFront(nil)
            } else {
                showSettingsWindow()
            }
        case .rewards:
            if onboardingRewardsWindow == nil {
                let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                                    styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
                panel.title = "学习成就 · 引导预览"
                panel.isReleasedWhenClosed = false
                // RewardsPanel 根部是贪婪 ScrollView、理想尺寸极小，contentViewController 的
                // 自动尺寸联动会把窗口缩成标题条；改用 NSHostingView 固定内容尺寸（同演示面板）。
                let hosting = NSHostingView(rootView: RewardsPanel(summary: (try? database.rewardSummary()) ?? .empty))
                hosting.sizingOptions = []
                hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 520)
                panel.contentView = hosting
                panel.center()
                onboardingRewardsWindow = panel
            }
            onboardingRewardsWindow?.makeKeyAndOrderFront(nil)
        case nil: break   // 翻译、游戏、备份仅说明，不调用带副作用的功能。
        }
        if let surface, let window = coachTargetWindow, !wasVisible || before !== window {
            coachOwnedWindows[surface] = window
        }
        coachPresentationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard let self, self.onboardingFlow.progress.accepts(token) else { return }
            self.renderCoachMark(focus: true)
        }
    }

    /// 更新内容和位置，不重新打开目标、不重置学习/练习状态。
    private func renderCoachMark(focus: Bool = false) {
        guard onboardingFlow.isActive else { return }
        let step = onboardingFlow.step
        let token = onboardingFlow.revision

        let target = coachTargetWindow
        coachLastTargetWindow = target
        let anchor = step == .menubar ? statusItem.buttonScreenFrame
            : (target?.isVisible == true ? target?.frame : nil)
        let screen = anchor.flatMap { frame in NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } }
            ?? coachPanel?.screen ?? primaryScreen
        guard let screen else { return }
        let vf = screen.visibleFrame
        let cardWidth = min(360, max(180, vf.width - 44))
        let contentHeight = min(260, max(60, vf.height - 250))
        var view = CoachMarkView(
            step: step, arrow: .none, flow: onboardingFlow,
            cardWidth: cardWidth, contentHeight: contentHeight, statusMessage: coachStatusMessage,
            onNext: { [weak self] in
                guard let self, self.onboardingFlow.progress.accepts(token) else { return }
                if step == .complete { self.finishOnboarding(rememberSkip: true) }
                else { self.onboardingFlow.advance(ifCurrent: token) }
            },
            onBack: { [weak self] in
                guard let self, self.onboardingFlow.progress.accepts(token) else { return }
                self.onboardingFlow.back()
            },
            onSkip: { [weak self] in
                guard let self, self.onboardingFlow.progress.accepts(token) else { return }
                self.finishOnboarding(rememberSkip: self.onboardingFlow.skipOnNextLaunch)
            },
            onShowTarget: coachSurface(for: step) == nil || onboardingFlow.celebrating ? nil : { [weak self] in
                guard let self, self.onboardingFlow.progress.accepts(token), !self.onboardingFlow.celebrating else { return }
                self.prepareOnboardingStep()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        var size = hosting.fittingSize
        // 保险：贪婪容器可能让 fittingSize 退化为 0，零尺寸面板会让渲染内容盖住目标窗口。
        if size.width < 40 || size.height < 40 {
            size = CGSize(width: cardWidth + 28, height: contentHeight + 210)
        }
        let placement = OnboardingPlacement.resolve(anchor: anchor, visibleFrame: vf,
                                                     size: size, preferBelow: step == .menubar)
        view = CoachMarkView(step: step, arrow: placement.arrow, arrowOffset: placement.arrowOffset,
                             flow: onboardingFlow, cardWidth: cardWidth, contentHeight: contentHeight,
                             statusMessage: coachStatusMessage, onNext: view.onNext, onBack: view.onBack,
                             onSkip: view.onSkip, onShowTarget: view.onShowTarget)
        hosting.rootView = view
        hosting.frame.size = size

        let panel = coachPanel ?? CoachMarkPanel(contentRect: NSRect(origin: .zero, size: size),
                                                 styleMask: [.borderless, .nonactivatingPanel],
                                                 backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onDismiss = { [weak self] in
            guard let self else { return }
            self.finishOnboarding(rememberSkip: self.onboardingFlow.skipOnNextLaunch)
        }
        panel.contentView = hosting
        panel.setContentSize(size)
        panel.setFrameOrigin(placement.origin)
        debugLog("引导气泡 step=\(step.rawValue) anchor=\(anchor.map { "\($0.origin) \($0.size)" } ?? "nil") card=\(size.width)x\(size.height) arrow=\(placement.arrow) origin=\(placement.origin)")
        coachPanel = panel
        panel.orderFrontRegardless()
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            if let target, target.isVisible { target.makeKey() }
            else { panel.makeKey() }
        }
    }

    /// 其他功能首次展示仍使用主屏；引导则跟随真实目标所在屏幕。
    private var primaryScreen: NSScreen? { NSScreen.screens.first }

    private var coachTargetWindow: NSWindow? {
        switch coachSurface(for: onboardingFlow.step) {
        case .study, .quiz: return onboardingDemoWindow
        case .library: return libraryWindow
        case .settings: return settingsWindow
        case .rewards: return onboardingRewardsWindow
        case nil: return nil
        }
    }

    private var coachStatusMessage: String? {
        if onboardingFlow.celebrating { return nil }
        if coachSurface(for: onboardingFlow.step) != nil, coachTargetWindow?.isVisible != true {
            return "本步界面已关闭，可重新显示，或直接继续引导。"
        }
        if onboardingFlow.step == .menubar, statusItem.buttonScreenFrame == nil {
            return "暂未定位到菜单栏图标，可从设置重看引导。"
        }
        return nil
    }

    private func installCoachObservers() {
        coachObservers.removeAll()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] note in
                    guard let self, self.onboardingFlow.isActive,
                          let window = note.object as? NSWindow,
                          window === self.coachLastTargetWindow || window === self.coachTargetWindow else { return }
                    self.renderCoachMark()
                }
                .store(in: &coachObservers)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderCoachMark() }
            .store(in: &coachObservers)
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
        observeClose(of: panel) { [weak self, weak panel] in
            guard let self, let panel, self.wordDetailWindow === panel else { return }
            self.wordDetailWindow = nil
            self.wordDetailHeadword = nil
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
        observeClose(of: window) { [weak self, weak window] in
            guard let self, let window, self.libraryWindow === window else { return }
            self.libraryWindow = nil
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 爬塔小游戏

    private lazy var towerEngine = TowerGameEngine(database: database)

    /// 启动时后台预热修仙塔词库（避免首次进入游戏/继续修仙路卡顿）
    private func prewarmTowerPool() {
        let db = database
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
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
            let snapshotCounts = counts
            let snapshotWords = catWords
            await MainActor.run {
                self.towerEngine.injectPool(words, counts: snapshotCounts, categoryWords: snapshotWords)
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
        observeClose(of: window) { [weak self, weak window] in
            guard let self, let window, self.gameWindow === window else { return }
            self.towerEngine.pauseBattleTimer()
            self.gameWindow = nil
            self.isGameOpen = false
            self.updateAmbientSuppression()
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
                try data.write(to: url, options: .atomic)
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
                AppSettings.shared.reloadFromDefaults()
                registerHotKeys()
                session.collectionKey = AppSettings.shared.currentCollectionKey
                let limit = UserDefaults.standard.object(forKey: Self.dailyNewLimitKey) as? Int ?? 20
                session.updateDailyNewLimit(limit)
                NotificationCenter.default.post(name: .collectionDidChange, object: nil)
                ambient.checkNow()
            } else {
                refreshAfterImport()
            }
            quiz.engine.reloadPool()
            var message = imported.isEmpty ? "文件为空或格式不符" : "已导入：" + imported.joined(separator: "、")
            if imported.contains("游戏进度") {
                message += "\n游戏进度将在重启应用后完全生效"
            }
            if imported.contains("目标与自我激励") && !imported.contains(where: { $0.hasPrefix("词库熟练度与成就") }) {
                message += "\n提示：等级/经验/成就进度来自词库熟练度与成就数据（复习记录），需同时导入该项才能完整恢复"
            }
            showInfoAlert(title: "导入成功", message: message)
        } catch {
            debugLog("[导入] 失败，未应用本次备份：\(error)")
            showInfoAlert(title: "导入失败", message: (error as? BackupError)?.localizedDescription ?? "文件格式不正确、词库不匹配或数据损坏。本次导入未写入。")
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
        let observation = WindowCloseObservation(window: window, handler: handler)
        objc_setAssociatedObject(window, &Self.closeObservationKey, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
