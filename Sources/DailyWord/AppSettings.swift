import AppKit
import Carbon.HIToolbox
import SwiftUI
import DailyWordCore

/// 学习卡问答方向
enum StudyDirection: String {
    case enToCn   // 看英文 → 出中文释义
    case cnToEn   // 看中文 → 出英文单词（并发音）
}

/// 无感复习浮卡的弹出位置
enum AmbientPosition: String, CaseIterable, Identifiable {
    case topCenter, topRight, topLeft, bottomRight, bottomLeft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topCenter: return "顶部居中"
        case .topRight: return "右上角"
        case .topLeft: return "左上角"
        case .bottomRight: return "右下角"
        case .bottomLeft: return "左下角"
        }
    }

    /// 依据屏幕可视区域与浮卡尺寸计算原点
    /// 边距留足（水平 24 / 顶部 28 / 底部 24），避免刘海屏圆角裁掉卡片内容
    func origin(in visibleFrame: NSRect, panelSize: NSSize) -> NSPoint {
        let margin: CGFloat = 24
        let topInset: CGFloat = 28
        let bottomInset: CGFloat = 24
        switch self {
        case .topCenter:
            return NSPoint(x: visibleFrame.midX - panelSize.width / 2,
                           y: visibleFrame.maxY - panelSize.height - topInset)
        case .topRight:
            return NSPoint(x: visibleFrame.maxX - panelSize.width - margin,
                           y: visibleFrame.maxY - panelSize.height - topInset)
        case .topLeft:
            return NSPoint(x: visibleFrame.minX + margin,
                           y: visibleFrame.maxY - panelSize.height - topInset)
        case .bottomRight:
            return NSPoint(x: visibleFrame.maxX - panelSize.width - margin,
                           y: visibleFrame.minY + bottomInset)
        case .bottomLeft:
            return NSPoint(x: visibleFrame.minX + margin,
                           y: visibleFrame.minY + bottomInset)
        }
    }
}

/// 可绑定全局快捷键的动作
enum HotKeyAction: String, CaseIterable, Identifiable {
    case revealWord       // 显示单词（翻面）
    case speak            // 快速发音
    case togglePanel      // 隐藏/显示面板
    case toggleQuiz       // 弹出测试
    case opacityUp        // 背景更实
    case opacityDown      // 背景更透
    case panelLeft        // 面板左移
    case panelRight       // 面板右移
    case panelUp          // 面板上移
    case panelDown        // 面板下移
    case translateSelection   // 划词翻译（选中文本直接翻译）
    case translateInput       // 输入翻译（弹输入框，回车翻译）
    case showWordDetail       // 查看当前单词详情
    case toggleGame           // 打开/关闭修仙塔

    var id: String { rawValue }

    var title: String {
        switch self {
        case .revealWord: return "显示单词"
        case .speak: return "快速发音"
        case .togglePanel: return "隐藏/显示面板"
        case .toggleQuiz: return "弹出测试"
        case .opacityUp: return "背景更实（测试/面板）"
        case .opacityDown: return "背景更透（测试/面板）"
        case .panelLeft: return "面板左移"
        case .panelRight: return "面板右移"
        case .panelUp: return "面板上移"
        case .panelDown: return "面板下移"
        case .translateSelection: return "划词翻译"
        case .translateInput: return "输入翻译"
        case .showWordDetail: return "查看单词详情"
        case .toggleGame: return "打开/关闭修仙塔"
        }
    }

    /// Carbon 热键需要唯一 id
    var hotKeyID: UInt32 {
        switch self {
        case .revealWord: return 1
        case .speak: return 2
        case .togglePanel: return 3
        case .toggleQuiz: return 4
        case .opacityUp: return 5
        case .opacityDown: return 6
        case .panelLeft: return 7
        case .panelRight: return 8
        case .panelUp: return 9
        case .panelDown: return 10
        case .translateSelection: return 11
        case .translateInput: return 12
        case .showWordDetail: return 13
        case .toggleGame: return 14
        }
    }

    var defaultBinding: HotKeyBinding {
        switch self {
        // 空格/P 不带修饰键 → 仅面板内生效（不会抢占其他 App 的按键）
        case .revealWord: return HotKeyBinding(keyCode: kVK_Space, modifiers: 0)
        case .speak: return HotKeyBinding(keyCode: kVK_ANSI_P, modifiers: 0)
        case .togglePanel: return HotKeyBinding(keyCode: kVK_ANSI_W, modifiers: optionKey)
        case .toggleQuiz: return HotKeyBinding(keyCode: kVK_ANSI_D, modifiers: optionKey)
        case .opacityUp: return HotKeyBinding(keyCode: kVK_ANSI_Equal, modifiers: optionKey)
        case .opacityDown: return HotKeyBinding(keyCode: kVK_ANSI_Minus, modifiers: optionKey)
        // ⌃⌥ 方向键：面板移动快捷键（用户指定，不加 ⌘）
        case .panelLeft: return HotKeyBinding(keyCode: kVK_LeftArrow, modifiers: optionKey | controlKey)
        case .panelRight: return HotKeyBinding(keyCode: kVK_RightArrow, modifiers: optionKey | controlKey)
        case .panelUp: return HotKeyBinding(keyCode: kVK_UpArrow, modifiers: optionKey | controlKey)
        case .panelDown: return HotKeyBinding(keyCode: kVK_DownArrow, modifiers: optionKey | controlKey)
        case .translateSelection: return HotKeyBinding(keyCode: kVK_ANSI_T, modifiers: optionKey)
        case .translateInput: return HotKeyBinding(keyCode: kVK_ANSI_T, modifiers: optionKey | controlKey)
        case .showWordDetail: return HotKeyBinding(keyCode: kVK_ANSI_I, modifiers: optionKey)
        case .toggleGame: return HotKeyBinding(keyCode: kVK_ANSI_G, modifiers: optionKey)
        }
    }
}

/// 一个快捷键绑定（自定义录制：keyCode + Carbon 修饰键）
struct HotKeyBinding: Equatable {
    var keyCode: Int
    var modifiers: Int

    /// 未绑定
    static let none = HotKeyBinding(keyCode: -1, modifiers: 0)

    var isSet: Bool { keyCode >= 0 }

    /// 人类可读标签，如 "⌥⇧D"
    var label: String {
        guard isSet else { return "未设置" }
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + KeyCodeNames.name(for: keyCode)
    }

    /// 至少一个修饰键 → 可注册为系统级全局热键
    var isGlobal: Bool { isSet && modifiers != 0 }

    /// 无修饰键（如空格）→ 仅在 DailyWord 面板内生效，不干扰其他 App
    var isLocalOnly: Bool { isSet && modifiers == 0 }

    /// 面板内 SwiftUI 快捷键映射
    var keyEquivalent: KeyEquivalent? {
        guard isSet, let char = KeyCodeNames.character(for: keyCode) else { return nil }
        return KeyEquivalent(char)
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers & cmdKey != 0 { result.insert(.command) }
        if modifiers & optionKey != 0 { result.insert(.option) }
        if modifiers & controlKey != 0 { result.insert(.control) }
        if modifiers & shiftKey != 0 { result.insert(.shift) }
        return result
    }

    var storage: String { "\(keyCode):\(modifiers)" }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(storage: String) {
        let parts = storage.split(separator: ":")
        guard parts.count == 2, let key = Int(parts[0]), let mod = Int(parts[1]) else { return nil }
        self.init(keyCode: key, modifiers: mod)
    }

    /// 由 NSEvent 修饰键转换为 Carbon 修饰键
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var value = 0
        if flags.contains(.command) { value |= cmdKey }
        if flags.contains(.option) { value |= optionKey }
        if flags.contains(.control) { value |= controlKey }
        if flags.contains(.shift) { value |= shiftKey }
        return value
    }
}

/// 键码 → 显示名
enum KeyCodeNames {
    private static let table: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "空格", kVK_Return: "回车", kVK_Tab: "Tab", kVK_Escape: "Esc",
        kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Grave: "`",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    static func name(for keyCode: Int) -> String {
        table[keyCode] ?? "键\(keyCode)"
    }

    /// 用于 SwiftUI keyboardShortcut 的字符（仅支持常见按键）
    static func character(for keyCode: Int) -> Character? {
        switch keyCode {
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Escape: return nil
        default:
            guard let name = table[keyCode], name.count == 1 else { return nil }
            return Character(name.lowercased())
        }
    }
}

/// 全局用户设置（UserDefaults 持久化）
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// 单词字号
    @Published var wordFontSize: Double {
        didSet { defaults.set(wordFontSize, forKey: "wordFontSize") }
    }

    /// 单词颜色；nil = 跟随系统默认
    @Published var wordColor: Color? {
        didSet { persistWordColor() }
    }

    /// 释义/正文颜色；nil = 系统默认
    @Published var definitionColor: Color? {
        didSet { persistColor(definitionColor, forKey: "definitionColorRGBA") }
    }

    /// 浮动学习面板的背景不透明度（仅作用于毛玻璃背景，文字始终清晰）
    @Published var studyOpacity: Double {
        didSet { defaults.set(studyOpacity, forKey: "studyOpacity") }
    }

    /// 学习面板（浮动面板）背景颜色；nil = 默认毛玻璃
    @Published var studyBackgroundColor: Color? {
        didSet { persistColor(studyBackgroundColor, forKey: "studyBackgroundColorRGBA") }
    }

    /// 题库（词库列表）字号（独立于学习面板）
    @Published var libraryFontSize: Double {
        didSet { defaults.set(libraryFontSize, forKey: "libraryFontSize") }
    }

    /// 题库（词库列表）单词颜色（独立于学习面板）；nil = 默认
    @Published var libraryWordColor: Color? {
        didSet { persistColor(libraryWordColor, forKey: "libraryWordColorRGBA") }
    }

    /// 题库（词库列表）释义颜色（独立于学习面板）；nil = 默认
    @Published var libraryDefinitionColor: Color? {
        didSet { persistColor(libraryDefinitionColor, forKey: "libraryDefinitionColorRGBA") }
    }

    /// 当前选择的词库 key（如 cet4/ielts），默认四级
    @Published var currentCollectionKey: String {
        didSet { defaults.set(currentCollectionKey, forKey: "currentCollectionKey") }
    }

    /// 发音口音
    @Published var accent: SpeechService.Accent {
        didSet {
            defaults.set(accent.rawValue, forKey: "accent")
            SpeechService.shared.accent = accent
        }
    }

    /// 学习卡问答方向
    @Published var studyDirection: StudyDirection {
        didSet { defaults.set(studyDirection.rawValue, forKey: "studyDirection") }
    }

    /// 测试浮层背景不透明度（0 = 全透明，0.85 = 接近实心）
    @Published var quizOpacity: Double {
        didSet { defaults.set(quizOpacity, forKey: "quizOpacity") }
    }

    /// 测试浮层字号
    @Published var quizFontSize: Double {
        didSet { defaults.set(quizFontSize, forKey: "quizFontSize") }
    }

    /// 测试浮层词语颜色；nil = 白色
    @Published var quizWordColor: Color? {
        didSet { persistColor(quizWordColor, forKey: "quizWordColorRGBA") }
    }

    /// 测试面板释义颜色（中答英题目/英答中选项）；nil = 默认
    @Published var quizDefinitionColor: Color? {
        didSet { persistColor(quizDefinitionColor, forKey: "quizDefinitionColorRGBA") }
    }

    /// 测试浮层背景颜色；nil = 默认黑色
    @Published var quizBackgroundColor: Color? {
        didSet { persistColor(quizBackgroundColor, forKey: "quizBackgroundColorRGBA") }
    }

    /// 无感复习浮卡位置
    @Published var ambientPosition: AmbientPosition {
        didSet { defaults.set(ambientPosition.rawValue, forKey: "ambientPosition") }
    }

    /// 两次无感弹卡的最小间隔（分钟）
    @Published var ambientIntervalMinutes: Int {
        didSet { defaults.set(ambientIntervalMinutes, forKey: "ambientIntervalMinutes") }
    }

    /// 划词翻译：整句翻译（true）；false = 仅翻译选中的部分
    @Published var translateWholeSentence: Bool {
        didSet { defaults.set(translateWholeSentence, forKey: "translateWholeSentence") }
    }

    /// 各动作的快捷键绑定（自定义录制）
    @Published private(set) var hotKeys: [HotKeyAction: HotKeyBinding] = [:]

    /// 设置绑定；与其他动作冲突时先释放对方
    func setHotKey(_ binding: HotKeyBinding, for action: HotKeyAction) {
        if binding.isSet {
            for (other, existing) in hotKeys where other != action && existing == binding {
                hotKeys[other] = .none
            }
        }
        hotKeys[action] = binding
        persistHotKeys()
        AppServices.shared.registerHotKeys()
    }

    func adjustQuizOpacity(by delta: Double) {
        quizOpacity = min(0.85, max(0.0, quizOpacity + delta))
    }

    func adjustStudyOpacity(by delta: Double) {
        studyOpacity = min(1.0, max(0.0, studyOpacity + delta))
    }

    /// 恢复单个动作的默认快捷键
    func resetHotKey(for action: HotKeyAction) {
        setHotKey(action.defaultBinding, for: action)
    }

    /// 恢复全部默认快捷键
    func resetAllHotKeys() {
        hotKeys = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultBinding) })
        persistHotKeys()
        AppServices.shared.registerHotKeys()
    }

    /// 恢复测试浮层默认外观
    func resetQuizAppearance() {
        quizOpacity = 0.18
        quizFontSize = 18
        quizWordColor = nil
        quizDefinitionColor = nil
        quizBackgroundColor = nil
    }

    /// 恢复题库（词库列表）默认外观
    func resetLibraryAppearance() {
        libraryFontSize = 18
        libraryWordColor = nil
        libraryDefinitionColor = nil
    }

    /// 恢复学习面板默认外观
    func resetStudyAppearance() {
        studyOpacity = 1.0
        wordColor = nil
        definitionColor = nil
        wordFontSize = 34
        studyBackgroundColor = nil
    }

    private func persistHotKeys() {
        let raw = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value.storage) })
        defaults.set(raw, forKey: "hotKeyBindingsV2")
    }

    private init() {
        let size = defaults.double(forKey: "wordFontSize")
        wordFontSize = size > 0 ? size : 34
        if let comps = defaults.array(forKey: "wordColorRGBA") as? [Double], comps.count == 4 {
            wordColor = Color(.sRGB, red: comps[0], green: comps[1], blue: comps[2], opacity: comps[3])
        } else {
            wordColor = nil
        }
        definitionColor = Self.color(from: defaults.array(forKey: "definitionColorRGBA") as? [Double])
        // 背景专属透明度：文字不受影响，允许透到 0%
        let storedStudyOpacity = (defaults.object(forKey: "studyOpacity") as? Double) ?? 1.0
        studyOpacity = min(1.0, max(0.0, storedStudyOpacity))
        studyBackgroundColor = Self.color(from: defaults.array(forKey: "studyBackgroundColorRGBA") as? [Double])
        let libSize = defaults.double(forKey: "libraryFontSize")
        libraryFontSize = libSize > 0 ? libSize : 18
        libraryWordColor = Self.color(from: defaults.array(forKey: "libraryWordColorRGBA") as? [Double])
        libraryDefinitionColor = Self.color(from: defaults.array(forKey: "libraryDefinitionColorRGBA") as? [Double])
        currentCollectionKey = defaults.string(forKey: "currentCollectionKey") ?? "cet4"
        accent = SpeechService.Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .american
        studyDirection = StudyDirection(rawValue: defaults.string(forKey: "studyDirection") ?? "") ?? .enToCn

        let opacity = defaults.object(forKey: "quizOpacity") as? Double
        quizOpacity = opacity ?? 0.18
        let quizSize = defaults.double(forKey: "quizFontSize")
        quizFontSize = quizSize > 0 ? quizSize : 18
        quizWordColor = Self.color(from: defaults.array(forKey: "quizWordColorRGBA") as? [Double])
        quizDefinitionColor = Self.color(from: defaults.array(forKey: "quizDefinitionColorRGBA") as? [Double])
        quizBackgroundColor = Self.color(from: defaults.array(forKey: "quizBackgroundColorRGBA") as? [Double])
        ambientPosition = AmbientPosition(rawValue: defaults.string(forKey: "ambientPosition") ?? "") ?? .topCenter
        let interval = defaults.integer(forKey: "ambientIntervalMinutes")
        ambientIntervalMinutes = interval > 0 ? interval : 3
        translateWholeSentence = defaults.bool(forKey: "translateWholeSentence")

        let raw = defaults.dictionary(forKey: "hotKeyBindingsV2") as? [String: String] ?? [:]
        hotKeys = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { action in
            let binding = raw[action.rawValue].flatMap(HotKeyBinding.init(storage:)) ?? action.defaultBinding
            return (action, binding)
        })
        // 迁移：把之前自动升级为 ⌃⌥⌘ 的移动键 改回 ⌃⌥（用户要求不带 ⌘）
        var migrated = false
        for action in [HotKeyAction.panelLeft, .panelRight, .panelUp, .panelDown] {
            if var b = hotKeys[action], b.modifiers & cmdKey != 0,
               b.modifiers & (optionKey | controlKey) == (optionKey | controlKey) {
                b.modifiers &= ~cmdKey
                hotKeys[action] = b
                migrated = true
            }
        }
        if migrated { persistHotKeys() }
    }

    /// 导入数据后：从 UserDefaults 重新读回全部设置（内存缓存刷新，立即生效）
    func reloadFromDefaults() {
        let size = defaults.double(forKey: "wordFontSize")
        wordFontSize = size > 0 ? size : 34
        if let comps = defaults.array(forKey: "wordColorRGBA") as? [Double], comps.count == 4 {
            wordColor = Color(.sRGB, red: comps[0], green: comps[1], blue: comps[2], opacity: comps[3])
        } else {
            wordColor = nil
        }
        definitionColor = Self.color(from: defaults.array(forKey: "definitionColorRGBA") as? [Double])
        let storedStudyOpacity = (defaults.object(forKey: "studyOpacity") as? Double) ?? 1.0
        studyOpacity = min(1.0, max(0.0, storedStudyOpacity))
        studyBackgroundColor = Self.color(from: defaults.array(forKey: "studyBackgroundColorRGBA") as? [Double])
        let libSize = defaults.double(forKey: "libraryFontSize")
        libraryFontSize = libSize > 0 ? libSize : 18
        libraryWordColor = Self.color(from: defaults.array(forKey: "libraryWordColorRGBA") as? [Double])
        libraryDefinitionColor = Self.color(from: defaults.array(forKey: "libraryDefinitionColorRGBA") as? [Double])
        currentCollectionKey = defaults.string(forKey: "currentCollectionKey") ?? "cet4"
        accent = SpeechService.Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .american
        studyDirection = StudyDirection(rawValue: defaults.string(forKey: "studyDirection") ?? "") ?? .enToCn

        let opacity = defaults.object(forKey: "quizOpacity") as? Double
        quizOpacity = opacity ?? 0.18
        let quizSize = defaults.double(forKey: "quizFontSize")
        quizFontSize = quizSize > 0 ? quizSize : 18
        quizWordColor = Self.color(from: defaults.array(forKey: "quizWordColorRGBA") as? [Double])
        quizDefinitionColor = Self.color(from: defaults.array(forKey: "quizDefinitionColorRGBA") as? [Double])
        quizBackgroundColor = Self.color(from: defaults.array(forKey: "quizBackgroundColorRGBA") as? [Double])
        ambientPosition = AmbientPosition(rawValue: defaults.string(forKey: "ambientPosition") ?? "") ?? .topCenter
        let interval = defaults.integer(forKey: "ambientIntervalMinutes")
        ambientIntervalMinutes = interval > 0 ? interval : 3
        translateWholeSentence = defaults.bool(forKey: "translateWholeSentence")

        let raw = defaults.dictionary(forKey: "hotKeyBindingsV2") as? [String: String] ?? [:]
        hotKeys = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { action in
            let binding = raw[action.rawValue].flatMap(HotKeyBinding.init(storage:)) ?? action.defaultBinding
            return (action, binding)
        })
    }

    private func persistWordColor() {
        persistColor(wordColor, forKey: "wordColorRGBA")
    }

    private func persistColor(_ color: Color?, forKey key: String) {
        guard let color, let ns = NSColor(color).usingColorSpace(.sRGB) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set([ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent].map(Double.init),
                     forKey: key)
    }

    private static func color(from comps: [Double]?) -> Color? {
        guard let comps, comps.count == 4 else { return nil }
        return Color(.sRGB, red: comps[0], green: comps[1], blue: comps[2], opacity: comps[3])
    }
}
