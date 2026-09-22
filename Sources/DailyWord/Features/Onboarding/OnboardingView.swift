import AppKit
import SwiftUI

// MARK: - 教程流程状态

/// 分步教程状态机：外部事件（打开学习面板/练习浮层）可自动推进步骤
@MainActor
final class OnboardingFlow: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome     // 屏幕正中：告知入口在菜单栏
        case menubar     // 箭头指菜单栏图标（锚定真实位置）
        case study       // 自动打开背词面板
        case library     // 自动打开词库窗口
        case quiz        // 自动打开练习浮层
        case appearance  // 自动打开设置：透明度/字号
        case opacityDemo // 互动：用快捷键调背景透明度
        case tripleClose // 互动：三连击关闭面板
        case rewards     // 自动打开经验/成就面板

        var title: String {
            switch self {
            case .welcome: return "欢迎使用 DailyWord"
            case .menubar: return "就是这个图标"
            case .study: return "这就是背词面板"
            case .library: return "词库与熟悉度"
            case .quiz: return "歌词条式练习"
            case .appearance: return "外观随你调"
            case .opacityDemo: return "背景随手调"
            case .tripleClose: return "三连击关闭"
            case .rewards: return "经验与成就"
            }
        }

        var detail: String {
            switch self {
            case .welcome:
                return "DailyWord 没有 Dock 图标，它住在屏幕右上角的菜单栏里。\n点“下一步”，我会用箭头指给你看。"
            case .menubar:
                return "单击这个 📖 图标开始背词，双击（或右键）弹出菜单，可以开始练习或退出应用。图标旁数字＝待复习词数。"
            case .study:
                return "试试看：按空格翻面，再按 1-4 给自己打分（1忘记 / 2模糊 / 3记得 / 4太简单）——完成一次自动进入下一步！"
            case .library:
                return "这里能看到每个词的熟悉度、下次出现时间，支持搜索和筛选；行尾 ⋯ 菜单可直接把词标为已掌握或毕业。"
            case .quiz:
                return "试试看：答对一题（选择题按 1234/ABCD，拼写题打字回车）——答对自动进入下一步！可拖动、双击关闭。"
            case .appearance:
                return "已为你打开设置面板：这里能调背景透明度、字号、单词/释义颜色。"
            case .opacityDemo:
                return "试试看：按 ⌥-（更透）或 ⌥=（更实）调整面板背景——可以一直透到 0%，文字始终清晰。调一下自动进入下一步！"
            case .tripleClose:
                return "试试看：在面板空白处快速连点三下关闭它——完成即进入下一步！（⌥W 可随时再呼出）"
            case .rewards:
                return "背词得 XP、升级、积累连击🔥和成就徽章。到期单词还会自动在屏幕顶部弹小卡提醒复习——一切就绪，开始吧！"
            }
        }

        var icon: String {
            switch self {
            case .welcome: return "hand.wave.fill"
            case .menubar: return "arrow.up"
            case .study: return "keyboard"
            case .library: return "books.vertical"
            case .quiz: return "character.cursor.ibeam"
            case .appearance: return "paintbrush"
            case .opacityDemo: return "slider.horizontal.3"
            case .tripleClose: return "cursorarrow.click.2"
            case .rewards: return "flame.fill"
            }
        }

        /// 箭头默认指向（实际方向由 AppServices 按气泡落点动态计算）
        var arrow: ArrowDirection {
            switch self {
            case .welcome: return .none
            case .menubar: return .up
            default: return .down
            }
        }
    }
    
    enum ArrowDirection {
        case up, down, left, right, none
    }

    @Published var step: Step = .welcome {
        didSet { onStepChanged?(step) }
    }
    var onStepChanged: ((Step) -> Void)?
    /// 鼓励阶段：用户在引导中完成了一次尝试
    var onCelebrate: ((String) -> Void)?
    private(set) var celebrating = false
    /// 教程是否进行中
    var isActive = false

    func reset() {
        celebrating = false
        step = .welcome
    }

    func advance() {
        celebrating = false
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    func back() {
        celebrating = false
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    /// 引导第 3 步：用户完成了一次自评 → 鼓励并自动进入下一步
    func notifyStudyRated() {
        guard isActive, step == .study, !celebrating else { return }
        celebrating = true
        onCelebrate?("🎉 很好！就是这样背词——带你去下一步")
    }

    /// 引导：用户答对了一题 → 鼓励并自动进入下一步
    func notifyQuizAnswered(correct: Bool) {
        guard isActive, step == .quiz, correct, !celebrating else { return }
        celebrating = true
        onCelebrate?("🎉 漂亮！练习也难不倒你")
    }

    /// 引导：用户用快捷键调了透明度 → 鼓励并自动进入下一步
    func notifyOpacityChanged() {
        guard isActive, step == .opacityDemo, !celebrating else { return }
        celebrating = true
        onCelebrate?("🎉 看，背景变了——文字依然清晰！")
    }

    /// 引导：用户三连击关闭了面板 → 鼓励并自动进入下一步
    func notifyTripleClosed() {
        guard isActive, step == .tripleClose, !celebrating else { return }
        celebrating = true
        onCelebrate?("🎉 关得漂亮！需要时 ⌥W 随时召回")
    }
}

// MARK: - 箭头指引气泡

/// 小气泡指引：带指向箭头，贴在被指引的界面元素旁边
struct CoachMarkView: View {
    let step: OnboardingFlow.Step
    let arrow: OnboardingFlow.ArrowDirection
    /// 向上箭头的水平偏移（气泡被屏边限制时仍能对准目标）
    var arrowXOffset: CGFloat = 0
    /// 非 nil 时显示鼓励文案（隐藏按钮，稍后自动进入下一步）
    var praise: String? = nil
    let stepIndex: Int
    let totalSteps: Int
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @State private var bouncing = false

    var body: some View {
        Group {
            switch arrow {
            case .up:
                VStack(spacing: 0) {
                    arrowView(angle: 0, bounceAxis: .vertical)
                        .offset(x: arrowXOffset)
                    bubble
                }
            case .down:
                VStack(spacing: 0) { bubble; arrowView(angle: 180, bounceAxis: .vertical) }
            case .left:
                HStack(spacing: 0) { arrowView(angle: -90, bounceAxis: .horizontal); bubble }
            case .right:
                HStack(spacing: 0) { bubble; arrowView(angle: 90, bounceAxis: .horizontal) }
            case .none:
                bubble
            }
        }
        .onAppear { bouncing = true }
    }

    private enum BounceAxis { case vertical, horizontal }

    private func arrowView(angle: Double, bounceAxis: BounceAxis) -> some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 15))
            .foregroundStyle(Color.accentColor)
            .rotationEffect(.degrees(angle))
            .offset(x: bounceAxis == .horizontal ? (bouncing ? (angle > 0 ? 3 : -3) : 0) : 0,
                    y: bounceAxis == .vertical ? (bouncing ? -3 : 2) : 0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: bouncing)
            .padding(bounceAxis == .horizontal ? .horizontal : .vertical, 2)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: step.icon)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(step.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(stepIndex + 1)/\(totalSteps)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let praise {
                // 鼓励状态：绿色大字，自动进入下一步，不显示按钮
                Text(praise)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                HStack(spacing: 8) {
                    Button("跳过") { onSkip() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if stepIndex > 0 {
                        Button("上一步") { onBack() }
                            .controlSize(.small)
                    }
                    Button(stepIndex == totalSteps - 1 ? "完成" : "下一步") { onNext() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(11)
        .frame(width: step == .welcome ? 330 : 268)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }
}
