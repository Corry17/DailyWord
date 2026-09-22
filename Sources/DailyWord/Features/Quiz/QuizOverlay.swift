import AppKit
import Combine
import SwiftUI
import Carbon.HIToolbox
import DailyWordCore

// MARK: - 可获得键盘焦点的无边框面板（打字模式需要）

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 练习引擎

/// 练习出题与判分：
/// - 拼写模式：出中文释义 → 键入英文单词
/// - 选择模式：出英文单词 → 四选一中文释义
/// 出题优先抽"到期待复习"的词（答对/答错会推进艾宾浩斯排期），其余时间随机抽已学词纯练习。
@MainActor
final class QuizEngine: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case typing = "拼写"
        case choice = "选择"
        var id: String { rawValue }
    }

    enum Feedback: Equatable {
        case correct(answer: String)
        case wrong(answer: String)
    }

    struct Question {
        let item: StudyItem
        let options: [String]      // 选择模式的四个中文释义
        let correctIndex: Int
        let wasDue: Bool           // 出题时是否到期（决定是否计入复习排期）
    }

    @Published var mode: Mode = .typing {
        didSet { if oldValue != mode { nextQuestion() } }
    }
    @Published var input = ""
    /// 普通拼写模式的光标位置（0 = 起点，input.count = 末尾）
    @Published var plainCaret = 0
    @Published private(set) var question: Question?
    @Published private(set) var feedback: Feedback?
    @Published private(set) var chosenIndex: Int?
    @Published private(set) var correctCount = 0
    @Published private(set) var totalCount = 0
        // 拼写模式多次尝试状态
    @Published private(set) var typingAttempts = 0     // 当前题已答错次数
    @Published private(set) var shakeTrigger = 0       // 递增触发震动动画
    // 字母格状态（连错 2 次后启用）
    @Published private(set) var slotChars: [Character?] = []
    @Published private(set) var caret = 0
    @Published private(set) var wrongPositions: Set<Int> = []
    @Published private(set) var correctPositions: Set<Int> = []
    @Published var isPeeking = false                   // 按住空格偷看单词
    /// 已锁定的位置（判定正确的绿字母 + 系统送的字母）：不可删除、光标不停留
    @Published private(set) var lockedPositions: Set<Int> = []
    /// 换题/需要重新聚焦时递增，视图监听后把光标拉回输入区
    @Published private(set) var focusToken = 0

    /// 字母格：进入时的累计错误次数（用于计算字母格内已错次数）
    private var slotEntryAttempts = 0
    /// 标色粘滞：满足过一次标色条件后持续标色
    private var colorSticky = false

    private let database: AppDatabase
    private let scheduler: SRSScheduler
    private let ambient: AmbientReviewController
    private var learnedPool: [StudyItem] = []
    private var newPool: [StudyItem] = []
    private var allDefinitions: [String] = []
    private var recentWordIds: [Int64] = []
    private var advanceTask: Task<Void, Never>?

    init(database: AppDatabase, scheduler: SRSScheduler, ambient: AmbientReviewController) {
        self.database = database
        self.scheduler = scheduler
        self.ambient = ambient
    }

    func startSession() {
        reloadPool()
        nextQuestion()
    }

    func stopSession() {
        advanceTask?.cancel()
        question = nil
        feedback = nil
    }

    func reloadPool() {
        let key = AppSettings.shared.currentCollectionKey
        let all = (try? database.allItems(collectionKey: key)) ?? []
        learnedPool = all.filter { $0.card != nil && $0.card?.state != .suspended }
        newPool = all.filter { $0.card == nil }
        allDefinitions = all.map { Self.firstLine($0.word.definitionCn) }
    }

    static func firstLine(_ definition: String) -> String {
        definition.split(separator: "\n").first.map(String.init) ?? definition
    }

    // MARK: - 出题

    func nextQuestion() {
        advanceTask?.cancel()
        feedback = nil
        chosenIndex = nil
        input = ""
        plainCaret = 0
        typingAttempts = 0
        slotChars = []
        slotEntryAttempts = 0
        colorSticky = false
        caret = 0
        wrongPositions = []
        correctPositions = []
        lockedPositions = []
        isPeeking = false

        let now = Date()
        let notRecent: (StudyItem) -> Bool = { [recentWordIds] in !recentWordIds.contains($0.word.id) }

        // 到期词优先 → 已学词 → 新词兜底
        let due = learnedPool.filter { ($0.card?.dueAt ?? .distantFuture) <= now }.filter(notRecent)
        let item = due.randomElement()
            ?? learnedPool.filter(notRecent).randomElement()
            ?? newPool.filter(notRecent).randomElement()
            ?? learnedPool.randomElement()
            ?? newPool.randomElement()

        guard let item else {
            question = nil
            return
        }

        recentWordIds.append(item.word.id)
        if recentWordIds.count > 5 { recentWordIds.removeFirst() }

        let correctDef = Self.firstLine(item.word.definitionCn)
        var options = Array(Set(allDefinitions.filter { $0 != correctDef })
            .shuffled()
            .prefix(3))
        let correctIndex = Int.random(in: 0...options.count)
        options.insert(correctDef, at: correctIndex)

        let wasDue = (item.card?.dueAt ?? .distantFuture) <= now
        question = Question(item: item, options: options, correctIndex: correctIndex, wasDue: wasDue)
        focusToken += 1   // 换题后把键盘焦点拉回输入区
    }

    // MARK: - 判分

    func submitTyping() {
        NSLog("[QuizEngine] submitTyping slotsActive=%d slotChars=%@ input=%@ attempts=%d", slotsActive ? 1:0, slotChars.map { $0.map(String.init) ?? "_" }.joined(), input, typingAttempts)
        guard let question, feedback == nil else { return }
        // 回车即判分：普通模式空输入、字母格全空都算一次（空答案判错），无任何防呆
        let answer = (slotsActive ? slotText : input).trimmingCharacters(in: .whitespacesAndNewlines)
        let correct = answer.compare(question.item.word.headword,
                                     options: .caseInsensitive) == .orderedSame
        if correct {
            // 一次答对才算"记得"；反复尝试后答对按"忘记"推进排期
            resolve(success: true, srsRating: typingAttempts == 0 ? .good : .again)
        } else {
            typingAttempts += 1
            shakeTrigger += 1
            if slotChars.isEmpty {
                if typingAttempts >= 2 { enterSlotMode() }
            } else {
                let beforeGreen = correctPositions.count
                markCheckedPositions()   // 标绿/标红（按条件：拼对过半或字母格内错满 3 次）
                // 只要有新的字母变绿（用户拼对），错误计数重新开始
                if correctPositions.count > beforeGreen {
                    slotEntryAttempts = typingAttempts
                }
                grantHintIfNeeded()      // 送字母（有用户拼对或计数未到 3 的倍数则不送）
                caret = nextEditable(atOrAfter: 0) ?? slotChars.count
            }
            focusToken += 1
        }
    }

    func choose(_ index: Int) {
        guard let question, feedback == nil else { return }
        chosenIndex = index
        let correct = index == question.correctIndex
        resolve(success: correct, srsRating: correct ? .good : .again)
    }

    func skip() {
        guard feedback == nil else { return }
        nextQuestion()
    }

    // MARK: - 普通拼写光标操作（non-slot 模式）

    /// 在 plainCaret 位置插入字符并右移光标
    func plainInsert(_ char: Character) {
        NSLog("[QuizEngine] plainInsert %@ caret=%d", String(char), plainCaret)
        let idx = input.index(input.startIndex, offsetBy: min(plainCaret, input.count))
        input.insert(char, at: idx)
        plainCaret = min(plainCaret + 1, input.count)
    }

    /// 删除光标前的一个字符
    func plainDeleteBackward() {
        guard !input.isEmpty, plainCaret > 0 else { return }
        let idx = input.index(input.startIndex, offsetBy: plainCaret - 1)
        input.remove(at: idx)
        plainCaret -= 1
    }

    /// 删除光标后的一个字符
    func plainDeleteForward() {
        guard !input.isEmpty, plainCaret < input.count else { return }
        let idx = input.index(input.startIndex, offsetBy: plainCaret)
        input.remove(at: idx)
    }

    /// 左右移动光标
    func plainMoveCaret(by delta: Int) {
        plainCaret = max(0, min(input.count, plainCaret + delta))
    }

    private func resolve(success: Bool, srsRating: Rating) {
        guard let question else { return }
        totalCount += 1
        if success { correctCount += 1 }

        let answer = mode == .typing
            ? question.item.word.headword
            : question.options[question.correctIndex]
        feedback = success ? .correct(answer: answer) : .wrong(answer: answer)

        SpeechService.shared.speak(question.item.word.headword)

        // 到期词的练习结果计入复习排期
        if question.wasDue, let card = question.item.card {
            let now = Date()
            let after = scheduler.review(card: card, rating: srsRating, now: now)
            let log = ReviewLog(
                uuid: UUID().uuidString,
                cardUuid: after.uuid,
                wordId: question.item.word.id,
                rating: srsRating.rawValue,
                stateBefore: card.state.rawValue,
                reviewedAt: now
            )
            try? database.recordReview(card: after, log: log, isNewWord: false, now: now)
            ambient.refreshDueCount()
            // 不重建题库池（全量查询 1.7 万词会卡顿）；notRecent 已排除最近答过的词
        }

        // 短暂展示反馈后自动下一题
        advanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((success ? 1.0 : 2.0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.nextQuestion()
        }
    }

    // MARK: - 拼写字母格（回车确认 · 绿字母锁定 · 只在未对位置编辑）
    // 连错 2 次：出现字母格，回车才判定
    // 判定后：对的字母变绿并**锁定**（不可删除、光标跳过），错的变红继续编辑
    // 错误次数每到 3 的倍数：送一个"还没对"的字母（而不是固定送开头）
    // 按住空格：临时显示正确单词

    /// 字母格输入模式是否激活
    var slotsActive: Bool {
        mode == .typing && !slotChars.isEmpty && question != nil
    }

    /// 字母格拼出的字符串（空位用 _ 占位，不会误判为正确）
    var slotText: String {
        String(slotChars.map { $0 ?? "_" })
    }

    /// 当前可编辑（未锁定）的位置
    private var editableIndices: [Int] {
        slotChars.indices.filter { !lockedPositions.contains($0) }
    }

    private func nextEditable(atOrAfter index: Int) -> Int? {
        editableIndices.first { $0 >= index }
    }

    private func lastEditable(before index: Int) -> Int? {
        editableIndices.last { $0 < index }
    }

    private func enterSlotMode() {
        guard let question else { return }
        slotChars = Array(repeating: nil, count: question.item.word.headword.count)
        wrongPositions = []
        correctPositions = []
        lockedPositions = []
        colorSticky = false
        slotEntryAttempts = typingAttempts   // 字母格模式重新计数：从进入时开始
        caret = 0
    }

    /// 字母格模式内的错误次数（进入字母格后重新从 0 计数）
    var slotErrorCount: Int {
        max(0, typingAttempts - slotEntryAttempts)
    }

    /// 回车判定：仅当「拼对的字母数 > 总字母数一半」或「字母格内已错 3 次及以上」时，
    /// 才对的位置标绿锁定、错的位置标红；否则不标色（保持输入状态）。
    /// 返回本次拼对的字母数。
    @discardableResult
    private func markCheckedPositions() -> Int {
        guard let question else { return 0 }
        let answer = Array(question.item.word.headword.lowercased())
        let total = slotChars.count
        var correctCount = 0
        for index in slotChars.indices {
            guard let char = slotChars[index] else { continue }
            if String(char).lowercased() == String(answer[index]) { correctCount += 1 }
        }
        let slotErrors = typingAttempts - slotEntryAttempts   // 字母格内已错次数（含本次）
        let shouldColor = correctCount * 2 > total || slotErrors >= 3
        // 标色粘滞：一旦满足过条件就持续标色，避免红黄反复闪烁
        if shouldColor { colorSticky = true }
        if colorSticky {
            var wrong: Set<Int> = []
            for index in slotChars.indices {
                guard let char = slotChars[index] else { continue }
                if String(char).lowercased() == String(answer[index]) {
                    correctPositions.insert(index)
                    lockedPositions.insert(index)   // 绿字母锁定
                } else {
                    wrong.insert(index)
                }
            }
            wrongPositions = wrong
        }
        // 未标色状态：不改 wrongPositions（保留已有红标，避免闪烁）
        return correctCount
    }

    /// 字母格模式内的错误次数每到 3 的倍数（从 3 的 1 倍开始，字母格内重新计数），
    /// 送一个**还没对**的字母：优先送空位（不覆盖用户输入），无空位则送第一个未锁定位（覆盖错误输入）；
    /// 至少留一个位置给用户自己拼。
    private func grantHintIfNeeded() {
        guard let question else { return }
        let slotErrors = slotErrorCount
        guard slotErrors > 0, slotErrors % 3 == 0 else { return }
        let headword = Array(question.item.word.headword)
        // 空位优先（用户还没输入的位置），否则第一个未锁定位（用户拼错的位置）
        let emptyIndices = slotChars.indices.filter { slotChars[$0] == nil }
        let target = emptyIndices.first ?? editableIndices.first
        guard editableIndices.count > 1, let target else { return }   // 至少留一个位置给用户
        slotChars[target] = headword[target]
        correctPositions.insert(target)
        lockedPositions.insert(target)
        wrongPositions.remove(target)
    }

    /// 在光标处输入字母（自动跳过已锁定位，需回车确认）
    func typeLetter(_ char: Character) {
        NSLog("[QuizEngine] typeLetter %@ slotsActive=%d caret=%d", String(char), slotsActive ? 1:0, caret)
        guard slotsActive, feedback == nil,
              let target = nextEditable(atOrAfter: caret) else { return }
        slotChars[target] = char
        wrongPositions.remove(target)
        caret = nextEditable(atOrAfter: target + 1) ?? slotChars.count
    }

    /// 退格：删除前一个可编辑位（绿色字母删不掉）
    func deleteBackward() {
        guard slotsActive, feedback == nil else { return }
        // 光标当前位已有字母时先清本位，否则回退一位
        if let here = nextEditable(atOrAfter: caret), here == caret, slotChars[here] != nil {
            slotChars[here] = nil
            wrongPositions.remove(here)
            return
        }
        guard let prev = lastEditable(before: caret) else { return }
        slotChars[prev] = nil
        wrongPositions.remove(prev)
        caret = prev
    }

    /// 前向删除：清空当前可编辑位
    func deleteForward() {
        guard slotsActive, feedback == nil,
              let target = nextEditable(atOrAfter: caret) else { return }
        slotChars[target] = nil
        wrongPositions.remove(target)
        caret = target
    }

    /// 左右移动光标：只在未锁定（红色/空白）的位置之间跳
    func moveCaret(by delta: Int) {
        guard slotsActive else { return }
        if delta > 0 {
            caret = nextEditable(atOrAfter: caret + 1) ?? caret
        } else {
            caret = lastEditable(before: caret) ?? caret
        }
    }
}

// MARK: - 浮层控制器

/// 歌词条式练习浮层：透明、置顶、可拖动，位置记忆；双击关闭，⌥D 全局显隐
@MainActor
final class QuizOverlayController {
    private static let originKey = "quizOverlayOrigin"

    let engine: QuizEngine
    private var panel: KeyablePanel?
    private var modeCancellable: AnyCancellable?
    private var moveCancellable: AnyCancellable?
    var onVisibilityChanged: (() -> Void)?

    var isVisible: Bool { panel != nil }

    /// 浮层在屏幕上的位置（引导气泡锚定用）
    var panelFrame: NSRect? { panel?.frame }

    /// 测试面板窗口（供快捷键按焦点分派）
    var window: NSWindow? { panel }

    init(engine: QuizEngine) {
        self.engine = engine
    }

    /// 面板尺寸随字号自适应，避免内容超出
    private static func size(for mode: QuizEngine.Mode) -> NSSize {
        let font = AppSettings.shared.quizFontSize
        let width = min(720, max(440, 260 + font * 11))
        switch mode {
        case .typing: return NSSize(width: width, height: 104 + font * 3.0)
        case .choice: return NSSize(width: width, height: 118 + font * 3.4)
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard panel == nil else { return }
        engine.startSession()

        let view = QuizOverlayView(engine: engine, onClose: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []   // 无边框面板：禁止 SwiftUI 接管窗口尺寸约束，否则抛异常
        let size = Self.size(for: engine.mode)
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
        panel.hasShadow = false            // 歌词条风格：无窗口阴影更干净
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true   // 按住任意空白处即可拖动
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 恢复上次拖动的位置（需仍在屏内）；首次显示在主屏上方居中（类似歌词条）
        if let saved = UserDefaults.standard.string(forKey: Self.originKey),
           StudyPanelController.isOriginOnScreen(NSPointFromString(saved), size: size) {
            panel.setFrameOrigin(NSPointFromString(saved))
        } else if let screen = NSScreen.screens.first {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: vf.midX - panel.frame.width / 2,
                y: vf.maxY - panel.frame.height - 80
            ))
        }

        // 拖动后记住位置
        moveCancellable = NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak panel] _ in
                guard let self, let panel, self.panel === panel else { return }
                UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
            }

        // 模式切换 / 字号改变时重算面板尺寸（保持顶边不动）
        modeCancellable = Publishers.CombineLatest(
            engine.$mode,
            AppSettings.shared.$quizFontSize
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] mode, _ in
            self?.resize(to: Self.size(for: mode))
            if mode == .typing { self?.panel?.makeKey() }
        }

        panel.orderFrontRegardless()
        panel.makeKey()   // 拼写模式需要键盘焦点（nonactivating：不抢其他 App 的激活状态）
        self.panel = panel
        onVisibilityChanged?()
    }

    private func resize(to size: NSSize) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: true)
    }

    func hide() {
        engine.stopSession()
        modeCancellable = nil
        moveCancellable = nil
        panel?.orderOut(nil)
        panel = nil
        onVisibilityChanged?()
    }

    /// 引导等场景：浮层若不在主屏，拉回主屏默认位置
    func ensureOnPrimaryScreen() {
        guard let panel, let primary = NSScreen.screens.first,
              panel.screen != primary else { return }
        let vf = primary.visibleFrame
        let origin = NSPoint(x: vf.midX - panel.frame.width / 2,
                             y: vf.maxY - panel.frame.height - 80)
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
    }

    /// 快捷键微移浮层（限制在屏幕可见区内）并记住位置
    func nudge(dx: CGFloat, dy: CGFloat) {
        guard let panel else { return }
        var origin = panel.frame.origin
        origin.x += dx
        origin.y += dy
        if let screen = panel.screen ?? NSScreen.screens.first {
            let vf = screen.visibleFrame
            origin.x = min(max(vf.minX, origin.x), vf.maxX - panel.frame.width)
            origin.y = min(max(vf.minY, origin.y), vf.maxY - panel.frame.height)
        }
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: Self.originKey)
    }
}

// MARK: - 字母格键盘捕获（字母/退格/前后删除/左右移动/回车/按住空格偷看）

private struct SlotKeyCatcher: NSViewRepresentable {
    let engine: QuizEngine

    func makeNSView(context: Context) -> SlotKeyView {
        let view = SlotKeyView()
        view.engine = engine
        return view
    }

    func updateNSView(_ nsView: SlotKeyView, context: Context) {
        nsView.engine = engine
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class SlotKeyView: NSView {
    var engine: QuizEngine?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        guard let window else { return }
        let ok = window.makeFirstResponder(self)
        NSLog("[SlotKeyView] viewDidMoveToWindow makeFirstResponder=%d isKey=%d", ok ? 1:0, window.isKeyWindow ? 1:0)
        // 窗口每次成为 key 时重新抢占焦点，保证键盘事件不丢
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey),
            name: NSWindow.didBecomeKeyNotification, object: window)
    }

    @objc private func windowBecameKey() {
        window?.makeFirstResponder(self)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// 统一处理所有快捷键（空格偷看/P 发音/⌥D 关闭浮层/透明度/移动…）
    private func handleShortcutIfAny(event: NSEvent) -> Bool {
        let settings = AppSettings.shared
        // 仅看 4 个核心修饰键；忽略 capsLock / Fn / Globe / numericPad / help，避免误匹配
        let flags = event.modifierFlags
        var mods = 0
        if flags.contains(.shift)   { mods |= shiftKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option)  { mods |= optionKey }
        if flags.contains(.command) { mods |= cmdKey }
        let keyCode = Int(event.keyCode)
        NSLog("[SlotKeyView] handleShortcutIfAny keyCode=%d mods=%d", keyCode, mods)
        for action in HotKeyAction.allCases {
            let binding = settings.hotKeys[action] ?? .none
            guard binding.matches(keyCode: keyCode, modifiers: mods) else { continue }
            // 拼写中的字母优先作为答案；选择模式仍可用配置的发音键。
            if engine?.mode == .typing, mods == 0, let ch = event.charactersIgnoringModifiers?.first,
               ch.isLetter || ch == "-" || ch == "'" {
                continue
            }
            // 若刚被全局 Carbon 热键触发过（0.3s 内），面板内跳过（避免重复执行）
            if hotKeyRecentlyFired(action.hotKeyID) {
                NSLog("[SlotKeyView] skip (global handled): %@", action.rawValue)
                return true
            }
            NSLog("[SlotKeyView] shortcut matched %@", action.rawValue)
            // 有修饰键的快捷键——异步执行（避免在 keyDown 中销毁面板导致崩溃）
            if mods != 0 {
                let capturedAction = action
                let capturedEngine = engine
                DispatchQueue.main.async {
                    switch capturedAction {
                    case .revealWord: capturedEngine?.isPeeking = true
                    case .speak:
                        if let word = capturedEngine?.question?.item.word.headword {
                            SpeechService.shared.speak(word)
                        }
                    default: AppServices.shared.perform(capturedAction)
                    }
                }
            } else {
                // 无修饰键（空格偷看、非可输入字符的快捷键）——同步执行
                switch action {
                case .revealWord: engine?.isPeeking = true
                case .speak:
                    if let word = engine?.question?.item.word.headword {
                        SpeechService.shared.speak(word)
                    }
                default: AppServices.shared.perform(action)
                }
            }
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        NSLog("[SlotKeyView] keyDown keyCode=%d chars=%@ engine=%d", event.keyCode, event.charactersIgnoringModifiers ?? "", engine == nil ? 0 : 1)
        guard let engine else { return super.keyDown(with: event) }
        // 快捷键优先
        if handleShortcutIfAny(event: event) { return }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51:   // delete
            engine.deleteBackward()
        case 117:  // forward delete
            engine.deleteForward()
        case 123:  // ←
            engine.moveCaret(by: -1)
        case 124:  // →
            engine.moveCaret(by: 1)
        case 36, 76: // return / enter
            engine.submitTyping()
        case 48:   // tab → 跳过本题
            engine.skip()
        default:
            guard let chars = event.charactersIgnoringModifiers, let char = chars.first,
                  char.isLetter || char == "-" || char == "'" else { return }
            engine.typeLetter(char)
        }
    }

    override func keyUp(with event: NSEvent) {
        let flags = event.modifierFlags
        var mods = 0
        if flags.contains(.shift)   { mods |= shiftKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option)  { mods |= optionKey }
        if flags.contains(.command) { mods |= cmdKey }
        let keyCode = Int(event.keyCode)
        let reveal = AppSettings.shared.hotKeys[.revealWord] ?? .none
        // 精确匹配或宽松匹配（keyCode 匹配即可）
        if (reveal.keyCode == keyCode && reveal.modifiers == mods)
            || (reveal.keyCode == keyCode && mods == 0) {
            engine?.isPeeking = false
        } else {
            super.keyUp(with: event)
        }
    }
}

// MARK: - 普通拼写键盘（自定义 NSView，拦截空格为偷看、字母写 engine.input、回车提交）

private struct PlainTypingCatcher: NSViewRepresentable {
    let engine: QuizEngine

    func makeNSView(context: Context) -> PlainTypingView {
        let v = PlainTypingView()
        v.engine = engine
        return v
    }

    func updateNSView(_ v: PlainTypingView, context: Context) {
        v.engine = engine
        v.needsDisplay = true
        if v.window?.firstResponder !== v {
            v.window?.makeFirstResponder(v)
        }
    }
}

final class PlainTypingView: NSView {
    var engine: QuizEngine?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        guard let window else { return }
        let ok = window.makeFirstResponder(self)
        NSLog("[PlainTypingView] viewDidMoveToWindow makeFirstResponder=%d isKey=%d", ok ? 1:0, window.isKeyWindow ? 1:0)
        // 窗口每次成为 key 时重新抢占焦点，保证键盘事件不丢
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey),
            name: NSWindow.didBecomeKeyNotification, object: window)
    }

    @objc private func windowBecameKey() {
        window?.makeFirstResponder(self)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// 统一处理所有快捷键。仅看 4 个核心修饰键（忽略 capsLock/Fn/Globe/numericPad）
    private func handleShortcutIfAny(event: NSEvent) -> Bool {
        let settings = AppSettings.shared
        let flags = event.modifierFlags
        var mods = 0
        if flags.contains(.shift)   { mods |= shiftKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option)  { mods |= optionKey }
        if flags.contains(.command) { mods |= cmdKey }
        let keyCode = Int(event.keyCode)
        NSLog("[PlainTypingView] handleShortcutIfAny keyCode=%d mods=%d", keyCode, mods)
        for action in HotKeyAction.allCases {
            let binding = settings.hotKeys[action] ?? .none
            guard binding.matches(keyCode: keyCode, modifiers: mods) else { continue }
            // 拼写中的字母优先作为答案；选择模式仍可用配置的发音键。
            if engine?.mode == .typing, mods == 0, let ch = event.charactersIgnoringModifiers?.first,
               ch.isLetter || ch == "-" || ch == "'" {
                continue
            }
            // 若刚被全局 Carbon 热键触发过（0.3s 内），面板内跳过（避免重复执行）
            if hotKeyRecentlyFired(action.hotKeyID) {
                NSLog("[PlainTypingView] skip (global handled): %@", action.rawValue)
                return true
            }
            NSLog("[PlainTypingView] shortcut matched %@", action.rawValue)
            // 有修饰键的快捷键——异步执行（避免在 keyDown 中销毁面板导致崩溃）
            if mods != 0 {
                let capturedAction = action
                let capturedEngine = engine
                DispatchQueue.main.async {
                    switch capturedAction {
                    case .revealWord: capturedEngine?.isPeeking = true
                    case .speak:
                        if let word = capturedEngine?.question?.item.word.headword {
                            SpeechService.shared.speak(word)
                        }
                    default: AppServices.shared.perform(capturedAction)
                    }
                }
            } else {
                // 无修饰键（空格偷看、非可输入字符的快捷键）——同步执行
                switch action {
                case .revealWord: engine?.isPeeking = true
                case .speak:
                    if let word = engine?.question?.item.word.headword {
                        SpeechService.shared.speak(word)
                    }
                default: AppServices.shared.perform(action)
                }
            }
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        NSLog("[PlainTypingView] keyDown keyCode=%d chars=%@ engine=%d", event.keyCode, event.charactersIgnoringModifiers ?? "", engine == nil ? 0 : 1)
        guard let engine else { return super.keyDown(with: event) }
        if handleShortcutIfAny(event: event) { return }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        // 选择模式：1-4 / A-D 直接选择选项；其他按键放行
        if engine.mode == .choice {
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), let ch = chars.first else {
                super.keyDown(with: event)
                return
            }
            if let n = Int(String(ch)), (1...4).contains(n) {
                engine.choose(n - 1)
                return
            }
            if let idx = ["a", "b", "c", "d"].firstIndex(of: String(ch)) {
                engine.choose(idx)
                return
            }
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 76:              // return / enter
            engine.submitTyping()
        case 51:                  // delete
            engine.plainDeleteBackward()
        case 117:                 // forward delete
            engine.plainDeleteForward()
        case 123:                 // ←
            engine.plainMoveCaret(by: -1)
        case 124:                 // →
            engine.plainMoveCaret(by: 1)
        case 125:                 // ↓  (移到末尾)
            engine.plainCaret = engine.input.count
        case 126:                 // ↑  (移到开头)
            engine.plainCaret = 0
        case 48:                  // tab
            engine.skip()
        default:
            guard let chars = event.charactersIgnoringModifiers, let ch = chars.first else { return }
            if ch.isLetter || ch == "-" || ch == "'" {
                engine.plainInsert(ch)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        let flags = event.modifierFlags
        var mods = 0
        if flags.contains(.shift)   { mods |= shiftKey }
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option)  { mods |= optionKey }
        if flags.contains(.command) { mods |= cmdKey }
        let keyCode = Int(event.keyCode)
        let reveal = AppSettings.shared.hotKeys[.revealWord] ?? .none
        // 精确匹配或宽松匹配（keyCode 匹配即可）
        if (reveal.keyCode == keyCode && reveal.modifiers == mods)
            || (reveal.keyCode == keyCode && mods == 0) {
            engine?.isPeeking = false
        } else {
            super.keyUp(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // 装饰性光标（主要光标由 SwiftUI 侧渲染）
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let caretColor = NSColor.controlAccentColor.withAlphaComponent(0.85)
        let rect = CGRect(x: bounds.midX - 1, y: bounds.midY - 8, width: 2, height: 16)
        ctx.setFillColor(caretColor.cgColor)
        ctx.fill(rect)
    }
}

// MARK: - 震动动画（答错时输入框左右抖动）

private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * shakesPerUnit * 2),
            y: 0
        ))
    }
}

// MARK: - 浮层视图（透明歌词条风格）

private struct QuizOverlayView: View {
    @ObservedObject var engine: QuizEngine
    @ObservedObject private var settings = AppSettings.shared
    let onClose: () -> Void
    @FocusState private var typingFocused: Bool
    @State private var hovering = false
    @State private var inputFlashRed = false

    var body: some View {
        VStack(spacing: 6) {
            controlBar
                .opacity(hovering ? 1 : 0)
            Spacer(minLength: 0)
            if let question = engine.question {
                switch engine.mode {
                case .typing: typingContent(question)
                case .choice: choiceContent(question)
                }
            } else {
                Text("词库为空")
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill((settings.quizBackgroundColor ?? .black)
                    .opacity(hovering ? min(0.9, settings.quizOpacity + 0.22) : settings.quizOpacity))
        )
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onClose() }   // 双击浮层退出
        .onChange(of: engine.focusToken) { _ in
            // 换题/判定后把光标拉回输入区（稍延迟等视图重建完成）
            guard engine.mode == .typing else { return }
            Task {
                try? await Task.sleep(nanoseconds: 80_000_000)
                typingFocused = true
            }
        }
        .onChange(of: engine.shakeTrigger) { _ in
            // 答错：短暂红色提示 + 震动（震动由 ShakeEffect 响应 shakeTrigger）
            inputFlashRed = true
            typingFocused = true
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                inputFlashRed = false
            }
        }
        .background(
            // 隐藏按钮：Esc 关闭
            Button("") { onClose() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }

    // 悬停才出现的控制条（平时纯净如歌词）
    private var controlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .help("按住空白处拖动 · 双击关闭 · ⌥D 显示/隐藏")
            if engine.totalCount > 0 {
                Text("\(engine.correctCount)/\(engine.totalCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            modeButton(.typing, icon: "keyboard")
            modeButton(.choice, icon: "square.grid.2x2")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("关闭（双击浮层或 ⌥D）")
        }
    }

    private func modeButton(_ mode: QuizEngine.Mode, icon: String) -> some View {
        Button {
            engine.mode = mode
        } label: {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(engine.mode == mode ? .white : .white.opacity(0.35))
        }
        .buttonStyle(.plain)
        .help("\(mode.rawValue)模式")
    }

    // 拼写模式：普通透明输入；连错 2 次后切换为可自由编辑的字母格
    private func typingContent(_ question: QuizEngine.Question) -> some View {
        VStack(spacing: 6) {
            Text(QuizEngine.firstLine(question.item.word.definitionCn))
                .font(.system(size: min(settings.quizFontSize, 20), weight: .semibold))
                .foregroundStyle(settings.quizDefinitionColor ?? .white)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if engine.slotsActive {
                slotInput(question)
                guidanceText(question)
            } else {
                plainInput
            }

            feedbackLine
        }
        .onAppear { typingFocused = true }
    }

    // 普通输入：自定义键盘捕获，按住空格偷看单词；←→/delete 可在字符间移动光标
    private var plainInput: some View {
        VStack(spacing: 5) {
            ZStack {
                PlainTypingCatcher(engine: engine)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                HStack(spacing: 0) {
                    if engine.isPeeking {
                        Text(engine.question?.item.word.headword ?? "")
                            .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.4))
                    } else if engine.input.isEmpty {
                        Text("输入英文单词，回车提交")
                            .foregroundStyle(.white.opacity(0.35))
                        // 空输入时显示光标在位置 0
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 1.5, height: settings.quizFontSize)
                    } else {
                        let caret = max(0, min(engine.input.count, engine.plainCaret))
                        let startIdx = engine.input.index(engine.input.startIndex, offsetBy: caret)
                        Text(String(engine.input[..<startIdx]))
                        Rectangle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 1.5, height: settings.quizFontSize)
                        Text(String(engine.input[startIdx...]))
                    }
                }
                .font(.system(size: settings.quizFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(inputFlashRed
                                 ? Color(red: 1.0, green: 0.35, blue: 0.3)
                                 : (settings.quizWordColor ?? .white))
            }
            .frame(width: 260, height: settings.quizFontSize + 6)
            .modifier(ShakeEffect(animatableData: CGFloat(engine.shakeTrigger)))
            .animation(.linear(duration: 0.4), value: engine.shakeTrigger)

            Rectangle()
                .fill(inputFlashRed ? Color.red.opacity(0.8) : .white.opacity(0.35))
                .frame(width: 260, height: 1)

            Text("按住空格偷看答案 · ←→ 移动光标 · 回车提交 · Tab 跳过")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
        }
        .disabled(engine.feedback != nil)
    }

    // 字母格：直接在下划线上输入，可左右移动、前后删除；按住空格偷看单词
    private func slotInput(_ question: QuizEngine.Question) -> some View {
        let answer = Array(question.item.word.headword)

        return VStack(spacing: 4) {
            // 按住空格时临时显示答案
            Text(engine.isPeeking ? question.item.word.headword : " ")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.4))

            ZStack {
                SlotKeyCatcher(engine: engine)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                HStack(spacing: 5) {
                    ForEach(answer.indices, id: \.self) { index in
                        VStack(spacing: 2) {
                            Text(engine.slotChars[index].map(String.init) ?? " ")
                                .font(.system(size: settings.quizFontSize, weight: .bold, design: .monospaced))
                                .foregroundStyle(slotColor(index: index))
                            Rectangle()
                                .fill(index == engine.caret ? Color.accentColor : .white.opacity(0.55))
                                .frame(width: max(13, settings.quizFontSize * 0.85),
                                       height: index == engine.caret ? 2.5 : 1.5)
                        }
                    }
                }
                .modifier(ShakeEffect(animatableData: CGFloat(engine.shakeTrigger)))
                .animation(.linear(duration: 0.4), value: engine.shakeTrigger)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// 字母格配色：已锁定提示/判定正确 = 绿色；判定错误 = 红色；输入中 = 白色
    private func slotColor(index: Int) -> Color {
        guard engine.slotChars.indices.contains(index),
              engine.slotChars[index] != nil else { return .clear }
        if engine.correctPositions.contains(index) {
            return Color(red: 0.45, green: 1.0, blue: 0.55)
        }
        if engine.wrongPositions.contains(index) {
            return Color(red: 1.0, green: 0.4, blue: 0.35)
        }
        return settings.quizWordColor ?? .white
    }

    /// 手把手引导文案
    private func guidanceText(_ question: QuizEngine.Question) -> some View {
        let total = question.item.word.headword.count
        let locked = engine.lockedPositions.count
        let slotErrors = engine.slotErrorCount            // 字母格内重新计数
        let nextHintIn = slotErrors == 0 ? 3 : 3 - (slotErrors % 3)
        let text: String
        if locked == 0 {
            text = "共 \(total) 个字母 · 回车确认 · ←→ 移动 · 按住空格看答案（再错 \(nextHintIn) 次送字母）"
        } else if locked < total - 1 {
            text = "绿色 \(locked) 个已锁定，只需改红色/空白处 · 回车确认"
        } else {
            text = "只差最后一个字母了，回车确认！"
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.55))
    }

    // 选择模式：单词 + 四个透明选项胶囊；按住空格偷看答案
    private func choiceContent(_ question: QuizEngine.Question) -> some View {
        VStack(spacing: 7) {
            // 空格偷看监听器（选择模式也需要 firstResponder）
            PlainTypingCatcher(engine: engine)
                .frame(width: 1, height: 1)
                .opacity(0.01)

            HStack(spacing: 8) {
                Text(engine.isPeeking
                     ? "👀 答案：\(question.options[question.correctIndex])"
                     : question.item.word.headword)
                    .font(.system(size: settings.quizFontSize + 4, weight: .bold))
                    .foregroundStyle(engine.isPeeking
                                     ? Color(red: 1.0, green: 0.85, blue: 0.4)
                                     : (settings.quizWordColor ?? .white))
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .animation(.easeInOut(duration: 0.15), value: engine.isPeeking)
                if !engine.isPeeking, let phonetic = question.item.word.phonetic {
                    Text("/\(phonetic)/")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Button {
                    SpeechService.shared.speak(question.item.word.headword)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            Text("按住空格看释义 · 按 1/2/3/4 或 A/B/C/D 选择")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(question.options.indices, id: \.self) { index in
                    Button {
                        engine.choose(index)
                    } label: {
                        HStack(spacing: 5) {
                            // 序号提示：1234 / ABCD 两套键都可选
                            Text("\(index + 1)\(Self.letterKeys[index].uppercased())")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        Text(question.options[index])
                                .font(.system(size: max(11, settings.quizFontSize - 6)))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(settings.quizDefinitionColor ?? .white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(optionFill(index, question: question)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.feedback != nil)
                }
            }

            // 隐藏快捷键：1-4 与 A-D 都可选项
            ZStack {
                ForEach(question.options.indices, id: \.self) { index in
                    Button("") { engine.choose(index) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    Button("") { engine.choose(index) }
                        .keyboardShortcut(KeyEquivalent(Self.letterKeys[index]), modifiers: [])
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)

            feedbackLine
        }
    }

    /// 选项字母键（与 1234 并行可用）
    private static let letterKeys: [Character] = ["a", "b", "c", "d"]

    private func optionFill(_ index: Int, question: QuizEngine.Question) -> Color {
        guard engine.feedback != nil else { return .white.opacity(0.10) }
        if index == question.correctIndex { return .green.opacity(0.55) }
        if index == engine.chosenIndex { return .red.opacity(0.55) }
        return .white.opacity(0.06)
    }

    @ViewBuilder
    private var feedbackLine: some View {
        switch engine.feedback {
        case .correct(let answer):
            Text("✓ \(answer)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.55))
                .shadow(color: .black.opacity(0.7), radius: 2)
        case .wrong(let answer):
            Text("✗ 正确答案：\(answer)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.45))
                .shadow(color: .black.opacity(0.7), radius: 2)
        case nil:
            Text(" ").font(.caption)   // 占位防止布局跳动
        }
    }
}
