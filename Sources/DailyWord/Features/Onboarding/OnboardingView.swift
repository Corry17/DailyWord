import AppKit
import SwiftUI
import DailyWordCore

// MARK: - 教程流程状态

/// UI 只负责反馈，进度与过期回调校验由可测试的状态机管理。
@MainActor
final class OnboardingFlow: ObservableObject {
    typealias Step = OnboardingProgress.Step
    typealias ArrowDirection = OnboardingPlacement.Arrow

    @Published private(set) var progress = OnboardingProgress()
    @Published private(set) var praise: String?
    @Published var skipOnNextLaunch = false
    var onStepChanged: ((Step) -> Void)?
    var onCelebrate: ((String) -> Void)?

    var step: Step { progress.step }
    var isActive: Bool { progress.isActive }
    var celebrating: Bool { praise != nil }
    var revision: UUID { progress.revision }

    func start(skipOnNextLaunch: Bool) {
        self.skipOnNextLaunch = skipOnNextLaunch
        praise = nil
        progress.start()
        onStepChanged?(step)
    }

    func stop() {
        progress.stop()
        praise = nil
    }

    func advance(ifCurrent token: UUID) {
        guard progress.advance(ifCurrent: token) else { return }
        praise = nil
        onStepChanged?(step)
    }

    func back() {
        guard progress.back() else { return }
        praise = nil
        onStepChanged?(step)
    }

    private func celebrate(_ interaction: OnboardingProgress.Interaction, message: String) {
        guard progress.record(interaction) else { return }
        praise = message
        onCelebrate?(message)
    }

    func notifyStudyRated() {
        celebrate(.studyRated, message: "已完成一次自评，即将进入下一步。")
    }

    func notifyQuizAnswered(correct: Bool) {
        guard correct else { return }
        celebrate(.quizAnswered, message: "答对了！即将进入下一步。")
    }

    func notifyOpacityChanged() {
        celebrate(.opacityChanged, message: "背景透明度已调整，文字不受影响。")
    }

    func notifyPanelMoved() {
        celebrate(.panelMoved, message: "面板已移动，即将进入下一步。")
    }

    func notifyTripleClosed() {
        celebrate(.tripleClosed, message: "面板已关闭，需要时可用菜单或快捷键召回。")
    }
}

extension OnboardingProgress.Step {
    var title: String {
        switch self {
        case .welcome: return "欢迎使用 DailyWord"
        case .menubar: return "从菜单栏开始"
        case .study: return "翻面、自评与发音"
        case .library: return "词库与单词详情"
        case .quiz: return "选择与拼写练习"
        case .appearance: return "学习计划与个性设置"
        case .opacityDemo: return "调整背景透明度"
        case .movement: return "移动浮动面板"
        case .tripleClose: return "关闭与再次呼出"
        case .translation: return "划词翻译与输入翻译"
        case .rewards: return "经验、成就与复习提醒"
        case .game: return "修仙路：用单词闯关"
        case .complete: return "准备就绪 · 数据与帮助"
        }
    }

    var detail: String {
        switch self {
        case .welcome:
            return "DailyWord 常驻菜单栏，没有 Dock 图标。接下来会展示常用入口和操作。\n每一步都可以直接继续，不必完成练习；可随时点“结束引导”，或点击引导后按 Esc 退出。"
        case .menubar:
            return "单击书本图标打开学习面板；双击或右键可打开菜单，进入练习、词库、设置或退出应用。图标旁数字是待复习词数。\n浮动学习面板也可用下方快捷键呼出。"
        case .study:
            return "先在演示面板点击“显示答案”翻面；根据记忆程度自评：1 忘记、2 模糊、3 记得、4 太简单。\n发音按钮可随时朗读；5“毕业”会移出常规复习，请谨慎使用。"
        case .library:
            return "在词库中搜索、筛选并查看熟悉度与下次复习时间。双击词条查看音标、释义、助记和例句。\n词库选择与每日新词量在设置中调整；修改掌握状态会影响复习安排。"
        case .quiz:
            return "演示浮层默认拼写：输入 apple 并回车判分；悬停浮层顶部图标可切到选择模式，点击选项或按 1–4 / A–D。判分后自动出下一题。\n答对一题会继续引导；也可直接点“下一步”。双击浮层可关闭。"
        case .appearance:
            return "设置中可以切换词库、调整每日新词量、英美发音、浮卡位置，以及学习/练习/词库的字号、背景和文字颜色。\n快捷键支持重新录制；各步骤的快捷键提示会读取你当前的绑定。"
        case .opacityDemo:
            return "先点击演示面板，用下方快捷键让背景更透或更实。透明度只影响背景，不影响文字；此次尝试不修改正式外观设置。\n快捷键未设置或无响应时，可在设置中用滑块调整，或直接继续。"
        case .movement:
            return "先点击要移动的浮动学习面板或练习浮层，再使用下方方向快捷键；也可拖动空白背景。\n菜单栏弹窗固定在图标下方，不是可移动的浮动面板。"
        case .tripleClose:
            return "试着在学习面板空白处快速连点三下关闭它。练习浮层使用双击；词库、游戏、翻译窗口可用关闭按钮。\n关闭面板不等于退出应用；菜单栏右键菜单中的“退出 DailyWord”才会退出。"
        case .translation:
            return "先主动打开划词翻译窗口，再到其他应用选中文本；识别后上方显示原文，下方显示“翻译中…”并更新译文。\n翻译窗口关闭时，选中文本不应自动弹出。输入翻译支持自行输入文本后回车。"
        case .rewards:
            return "学习面板左上角的等级入口可查看经验、打卡连击和学习成就。修仙路内还有独立的游戏成就。\n到期词会按设置位置弹出复习小卡；引导期间暂停这些提醒，结束后恢复。"
        case .game:
            return "从学习面板的游戏图标、菜单或快捷键进入修仙路。选择职业，通过答题推进境界、关卡组与分叉路线，管理背包和随从。\n已有进度时优先选择继续；重新开始会重置本次闯关进度。"
        case .complete:
            return "右键菜单栏图标可导出 JSON 备份；导入前请先备份并阅读确认提示，部分设置和进度会被覆盖。\n“重看上手引导”可从菜单或设置再次进入。完成后不再自动展示本引导。"
        }
    }

    var note: String {
        switch self {
        case .study, .quiz, .opacityDemo, .movement, .tripleClose: return "这是独立演示面板，操作不计入学习进度、复习排期、XP 或正式外观设置。"
        case .translation: return "翻译需要联网；划词读取需要辅助功能权限。PDF/受限应用的识别取决于文本层及应用支持，不保证所有内容都能读取。本步骤不会自动取词或请求权限。"
        case .game: return "这里只介绍玩法，不会自动开局、读写闯关进度或改变装备。"
        default: return "可随时返回上一步；无需完成互动也能继续。"
        }
    }

    var shortcuts: [HotKeyAction] {
        switch self {
        case .menubar, .tripleClose: return [.togglePanel]
        case .study: return [.revealWord, .speak, .showWordDetail]
        case .quiz: return [.toggleQuiz]
        case .opacityDemo: return [.opacityDown, .opacityUp]
        case .movement: return [.panelLeft, .panelRight, .panelUp, .panelDown]
        case .translation: return [.translateSelection, .translateInput]
        case .game: return [.toggleGame]
        default: return []
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .menubar: return "menubar.rectangle"
        case .study: return "keyboard"
        case .library: return "books.vertical"
        case .quiz: return "character.cursor.ibeam"
        case .appearance: return "gearshape"
        case .opacityDemo: return "slider.horizontal.3"
        case .movement: return "arrow.up.and.down.and.arrow.left.and.right"
        case .tripleClose: return "cursorarrow.click.2"
        case .translation: return "character.bubble"
        case .rewards: return "flame.fill"
        case .game: return "gamecontroller"
        case .complete: return "checkmark.seal.fill"
        }
    }
}

// MARK: - 箭头指引气泡

/// 小气泡指引：带指向箭头，贴在被指引的界面元素旁边
struct CoachMarkView: View {
    let step: OnboardingFlow.Step
    let arrow: OnboardingFlow.ArrowDirection
    var arrowOffset: CGFloat = 0
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject private var settings = AppSettings.shared
    let cardWidth: CGFloat
    let contentHeight: CGFloat
    let statusMessage: String?
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    var onShowTarget: (() -> Void)?

    var body: some View {
        bubble
            .padding(14)
            // 箭头用固定对齐而非 GeometryReader：贪婪容器会把 fittingSize 拉成 0，
            // 导致气泡面板零尺寸、渲染内容盖住目标窗口。
            .overlay(alignment: arrowAlignment) {
                if arrow != .none {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                        .rotationEffect(.degrees(arrowAngle))
                        .offset(x: arrowShift.width, y: arrowShift.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private var arrowAlignment: Alignment {
        switch arrow {
        case .up: return .top
        case .down: return .bottom
        case .left: return .leading
        case .right, .none: return .trailing
        }
    }

    /// 沿边缘滑动箭头；纵向箭头横向偏移，横向箭头纵向偏移（正值向右/向下）。
    private var arrowShift: CGSize {
        switch arrow {
        case .up, .down: return CGSize(width: arrowOffset, height: 0)
        case .left, .right: return CGSize(width: 0, height: arrowOffset)
        case .none: return .zero
        }
    }

    private var arrowAngle: Double {
        switch arrow {
        case .up, .none: return 0
        case .down: return 180
        case .left: return -90
        case .right: return 90
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: step.icon)
                    .foregroundStyle(Color.accentColor)
                Text(step.title).font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(step.rawValue + 1)/\(OnboardingFlow.Step.allCases.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("第 \(step.rawValue + 1) 步，共 \(OnboardingFlow.Step.allCases.count) 步")
            }
            ProgressView(value: Double(step.rawValue + 1), total: Double(OnboardingFlow.Step.allCases.count))
                .accessibilityLabel("引导进度")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(step.detail)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if !step.shortcuts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("当前快捷键").font(.caption.bold())
                            ForEach(step.shortcuts) { action in
                                let binding = settings.hotKeys[action] ?? HotKeyBinding.none
                                HStack {
                                    Text(action.title)
                                    Spacer(minLength: 8)
                                    Text(binding.isSet ? "\(binding.label) · \(binding.isGlobal ? "全局" : "面板内")" : "未设置")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(10)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text(step.note).font(.caption).foregroundStyle(.secondary)
                    if let statusMessage {
                        Label(statusMessage, systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: contentHeight)
            .id(step)

            if let praise = flow.praise {
                Label(praise, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onShowTarget {
                Button("重新显示本步界面", action: onShowTarget)
                    .buttonStyle(.link).font(.caption)
            }
            Toggle("下次启动不再自动显示", isOn: $flow.skipOnNextLaunch)
                .font(.caption)
            HStack(spacing: 8) {
                Button("结束引导", action: onSkip)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button("上一步", action: onBack).disabled(step == .welcome)
                Button(step == .complete ? "完成" : "下一步", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: cardWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }
}

@MainActor
final class OnboardingDemoModel: ObservableObject {
    @Published var state = OnboardingDemoState()
}

/// 仅内存的示例，不复用会启动真实队列的 StudyPanelController/QuizEngine。
struct OnboardingDemoView: View {
    @ObservedObject var model: OnboardingDemoModel
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject private var settings = AppSettings.shared
    let isQuiz: Bool
    let onClose: (Bool) -> Void
    // 练习演示状态：默认拼写模式（与正式浮层一致），判分反馈与自动出题节奏同 QuizEngine。
    @State private var spelling = true
    @State private var quizHovering = false
    @State private var quizFeedback: Bool?      // nil=未判分；true=✓；false=✗
    @State private var quizChosen: Int?
    @State private var quizTotal = 0
    @State private var quizCorrectCount = 0
    @State private var quizAdvanceTask: Task<Void, Never>?
    @FocusState private var demoTypingFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            banner
            if isQuiz {
                quizContent
                Text("双击空白背景关闭演示")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 8)
            } else {
                // 结构复刻真实学习面板：header / 卡片 / 自评条，数据仅来自演示状态。
                Divider()
                studyHeader
                Divider()
                studyCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                studyFooter
                Text("三连击空白背景关闭演示")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: demoWindowSize.width, height: demoWindowSize.height)
        .background {
            // 练习演示对应正式暗色浮层（含悬停加深）；背单词演示对应浅色学习面板。
            RoundedRectangle(cornerRadius: isQuiz ? 14 : 16, style: .continuous)
                .fill(isQuiz
                      ? AnyShapeStyle((settings.quizBackgroundColor ?? .black).opacity(
                            quizHovering ? min(0.9, settings.quizOpacity + 0.22) : settings.quizOpacity))
                      : AnyShapeStyle(.regularMaterial))
                .opacity(isQuiz ? 1 : model.state.opacity)
                .contentShape(Rectangle())
                .onTapGesture(count: isQuiz ? 2 : 3) { onClose(true) }
        }
        .overlay {
            if !isQuiz {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 1)
            }
        }
        .onHover { if isQuiz { quizHovering = $0 } }
    }

    private var banner: some View {
        HStack {
            Label("引导演示 · 不计入进度", systemImage: "play.rectangle")
                .font(.caption2)
                .foregroundStyle(isQuiz ? Color.white.opacity(0.55) : Color.secondary)
            Spacer()
            Button { onClose(false) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(isQuiz ? Color.white.opacity(0.6) : Color.secondary)
        }
        .padding(.horizontal, isQuiz ? 16 : 18)
        .padding(.top, isQuiz ? 8 : 12)
        .padding(.bottom, isQuiz ? 2 : 8)
    }

    /// 窗口尺寸：练习与正式浮层同公式，背单词与学习面板同宽度。
    private var demoWindowSize: CGSize {
        if isQuiz {
            return CGSize(width: min(720, max(440, 260 + settings.quizFontSize * 11)),
                          height: 118 + settings.quizFontSize * 3.4 + 56)
        }
        return CGSize(width: 340, height: 470)
    }

    // MARK: - 练习演示（复刻 QuizOverlayView：暗底浮层 + 悬停控制条 + 同款输入/选项）

    private var quizContent: some View {
        VStack(spacing: 6) {
            quizControlBar
                .opacity(quizHovering ? 1 : 0)
            Spacer(minLength: 0)
            if spelling {
                quizTyping
            } else {
                quizChoice
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if spelling { demoTypingFocused = true } }
        .background {
            // 隐藏快捷键：Esc 关闭（与正式浮层一致）
            Button("") { onClose(false) }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    /// 悬停才出现的控制条：计分 + 模式切换 + 关闭，样式同正式。
    private var quizControlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
            if quizTotal > 0 {
                Text("\(quizCorrectCount)/\(quizTotal)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            quizModeButton(false, icon: "square.grid.2x2")
            quizModeButton(true, icon: "keyboard")
            Button { onClose(false) } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func quizModeButton(_ target: Bool, icon: String) -> some View {
        Button {
            guard spelling != target else { return }
            spelling = target
            resetQuizRound()
        } label: {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(spelling == target ? .white : .white.opacity(0.35))
        }
        .buttonStyle(.plain)
    }

    /// 拼写模式：中文释义题干 + 透明等宽输入行（占位文案与正式一致，不泄露答案）。
    private var quizTyping: some View {
        VStack(spacing: 6) {
            Text(OnboardingDemoState.definition)
                .font(.system(size: min(settings.quizFontSize, 20), weight: .semibold))
                .foregroundStyle(settings.quizDefinitionColor ?? .white)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            TextField("输入英文单词，回车提交", text: $model.state.quizInput)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: settings.quizFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(quizFeedback == false
                                 ? Color(red: 1.0, green: 0.35, blue: 0.3)
                                 : settings.quizWordColor ?? .white)
                .frame(width: 260, height: settings.quizFontSize + 6)
                .focused($demoTypingFocused)
                .onSubmit { submitSpelling() }
                .disabled(quizFeedback != nil)

            Rectangle()
                .fill(quizFeedback == false ? Color.red.opacity(0.8) : .white.opacity(0.35))
                .frame(width: 260, height: 1)

            Text("回车提交 · 判分后自动出下一题")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))

            quizFeedbackLine
        }
    }

    /// 选择模式：单词+音标+发音 + 1A/2B 胶囊选项（判分后绿/红高亮），与正式一致。
    private var quizChoice: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(OnboardingDemoState.word)
                    .font(.system(size: settings.quizFontSize + 4, weight: .bold))
                    .foregroundStyle(settings.quizWordColor ?? .white)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("/ˈæpəl/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                Button {
                    SpeechService.shared.speak(OnboardingDemoState.word)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            Text("点击选项 · 按 1/2/3/4 或 A/B/C/D 选择")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(OnboardingDemoState.options.indices, id: \.self) { index in
                    Button {
                        chooseOption(index)
                    } label: {
                        HStack(spacing: 5) {
                            Text("\(index + 1)\(Self.demoLetterKeys[index].uppercased())")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(OnboardingDemoState.options[index])
                                .font(.system(size: max(11, settings.quizFontSize - 6)))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(settings.quizDefinitionColor ?? .white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(demoOptionFill(index)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(quizFeedback != nil)
                }
            }

            // 隐藏快捷键：1-4 与 A-D 都可选项（与正式一致）
            ZStack {
                ForEach(OnboardingDemoState.options.indices, id: \.self) { index in
                    Button("") { chooseOption(index) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                    Button("") { chooseOption(index) }
                        .keyboardShortcut(KeyEquivalent(Self.demoLetterKeys[index]), modifiers: [])
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)

            quizFeedbackLine
        }
    }

    /// 选项字母键（与 1234 并行可用），同正式 letterKeys。
    private static let demoLetterKeys: [Character] = ["a", "b", "c", "d"]

    private func demoOptionFill(_ index: Int) -> Color {
        guard quizFeedback != nil else { return .white.opacity(0.10) }
        if index == OnboardingDemoState.correctOption { return .green.opacity(0.55) }
        if index == quizChosen { return .red.opacity(0.55) }
        return .white.opacity(0.06)
    }

    @ViewBuilder
    private var quizFeedbackLine: some View {
        // 反馈答案与正式一致：拼写展示单词，选择展示释义选项。
        let answer = spelling ? OnboardingDemoState.word
            : OnboardingDemoState.options[OnboardingDemoState.correctOption]
        switch quizFeedback {
        case .some(true):
            Text("✓ \(answer)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.55))
                .shadow(color: .black.opacity(0.7), radius: 2)
        case .some(false):
            Text("✗ 正确答案：\(answer)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.45))
                .shadow(color: .black.opacity(0.7), radius: 2)
        case .none:
            Text(" ").font(.caption)   // 占位防止布局跳动
        }
    }

    private func submitSpelling() {
        guard quizFeedback == nil else { return }
        let correct = model.state.submitSpelling()
        finishQuizRound(correct: correct, chosen: nil)
    }

    private func chooseOption(_ index: Int) {
        guard quizFeedback == nil else { return }
        let correct = model.state.choose(index)
        finishQuizRound(correct: correct, chosen: index)
    }

    /// 判分后短暂展示反馈再自动重置，节奏与正式 QuizEngine.resolve 一致（对 1s / 错 2s）。
    private func finishQuizRound(correct: Bool, chosen: Int?) {
        quizFeedback = correct
        quizChosen = chosen
        quizTotal += 1
        if correct { quizCorrectCount += 1 }
        flow.notifyQuizAnswered(correct: correct)
        quizAdvanceTask?.cancel()
        quizAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64((correct ? 1.0 : 2.0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            resetQuizRound()
        }
    }

    private func resetQuizRound() {
        quizFeedback = nil
        quizChosen = nil
        model.state.quizInput = ""
    }

    // MARK: - 背单词演示（对应 StudyView.header / CardView / footer）

    private var studyHeader: some View {
        HStack(spacing: 10) {
            Text("Lv1")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                .foregroundStyle(Color.accentColor)
            Label("0/1", systemImage: "sparkles")
            Label("0/0", systemImage: "arrow.triangle.2.circlepath")
            Spacer()
            // 图标仅装饰：演示不打开真实的方向切换/游戏/词库/练习/设置。
            Image(systemName: "arrow.left.arrow.right")
            Image(systemName: "gamecontroller")
            Image(systemName: "books.vertical")
            Image(systemName: "keyboard.badge.ellipsis")
            Image(systemName: "gearshape")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var studyCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Text("新词")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                Text(OnboardingDemoState.word)
                    .font(.system(size: min(settings.wordFontSize, 44), weight: .bold, design: .rounded))
                    .foregroundStyle(settings.wordColor ?? Color.primary)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                Text("/ˈæpəl/")
                    .font(.callout)
                    .foregroundStyle((settings.wordColor ?? Color.primary).opacity(0.65))
                if model.state.isRevealed {
                    ScrollView {
                        Text(OnboardingDemoState.definition)
                            .font(.body)
                            .foregroundStyle(settings.definitionColor ?? Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 130)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                } else {
                    Text("回忆词义 · \(revealHint)查看答案，再按隐藏")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20)
                }
            }
            .padding(.vertical, 16)
            Image(systemName: "lightbulb")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(8)
        }
    }

    private var revealHint: String {
        let binding = settings.hotKeys[.revealWord] ?? .none
        return binding.isSet ? "\(binding.label) " : "点击按钮"
    }

    @ViewBuilder
    private var studyFooter: some View {
        if model.state.isRevealed {
            // 五档自评与真实一致（含 5 毕业）；演示毕业仅推进引导。
            HStack(spacing: 8) {
                RatingButton(title: "忘记", key: "1", tint: .red) {
                    if model.state.rate(1) { flow.notifyStudyRated() }
                }
                RatingButton(title: "模糊", key: "2", tint: .orange) {
                    if model.state.rate(2) { flow.notifyStudyRated() }
                }
                RatingButton(title: "记得", key: "3", tint: .green) {
                    if model.state.rate(3) { flow.notifyStudyRated() }
                }
                RatingButton(title: "太简单", key: "4", tint: .blue) {
                    if model.state.rate(4) { flow.notifyStudyRated() }
                }
                RatingButton(title: "毕业", key: "5", tint: .gray) {
                    flow.notifyStudyRated()
                }
                Button("") { model.state.flip() }
                    .modifier(BindingShortcut(binding: localBinding(.revealWord)))
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
            .padding(10)
        } else {
            HStack {
                Button { onClose(false) } label: { Image(systemName: "xmark") }
                    .help("关闭演示面板")
                Spacer()
                Button { model.state.flip() } label: {
                    Text("显示答案").frame(maxWidth: 160)
                }
                .modifier(BindingShortcut(binding: localBinding(.revealWord)))
                .controlSize(.large)
                Spacer()
                Button {
                    SpeechService.shared.speak(OnboardingDemoState.word)
                } label: { Image(systemName: "speaker.wave.2") }
                    .modifier(BindingShortcut(binding: localBinding(.speak)))
                    .help("再听一遍发音")
            }
            .padding(10)
        }
    }

    private func localBinding(_ action: HotKeyAction) -> HotKeyBinding {
        let binding = settings.hotKeys[action] ?? .none
        return binding.isLocalOnly ? binding : .none
    }
}

/// 无边框气泡仍需可获得键盘焦点，保证下一步与 Esc 可用。
final class CoachMarkPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}
