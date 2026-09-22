import SwiftUI
import DailyWordCore

extension Notification.Name {
    /// 引导流程请求自动弹开/收起设置与奖励面板
    static let openStudySettings = Notification.Name("com.dailyword.openStudySettings")
    static let openStudyRewards = Notification.Name("com.dailyword.openStudyRewards")
    static let closeStudyPopovers = Notification.Name("com.dailyword.closeStudyPopovers")
    /// 词库切换后刷新词库页
    static let collectionDidChange = Notification.Name("com.dailyword.collectionDidChange")
    static let wordDetailChanged = Notification.Name("com.dailyword.wordDetailChanged")
}

/// Popover 主视图：根据会话阶段展示 学习卡片 / 完成页 / 错误
struct StudyView: View {
    @EnvironmentObject var session: StudySession
    @ObservedObject private var settings = AppSettings.shared
    @State private var showRewards = false
    @State private var rewards: RewardSummary = .empty
    @ObservedObject private var detailState = WordDetailState.shared
    /// 浮动面板使用：关闭自身而不是退出 App
    var onClose: (() -> Void)?

    /// 鼠标悬停状态（透明度为 0 时仍显示半透明背景，类似测试面板的 hover 效果）
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 340, height: 420)
        .background(panelBackground)
        .onTapGesture(count: 3) { closeInterface() }   // 三连击关闭学习界面
        // 鼠标悬停检测（透明度低时仍显示背景，方便拖动）
        .onHover { hovering = $0 }
        .onAppear(perform: reloadRewards)
        // 数据导入/词库切换后刷新成就与经验
        .onReceive(NotificationCenter.default.publisher(for: .collectionDidChange)) { _ in
            reloadRewards()
        }
        .onChange(of: session.phase) { _ in reloadRewards() }
        .onReceive(NotificationCenter.default.publisher(for: .openStudySettings)) { _ in
            showRewards = false
            AppServices.shared.showSettingsWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openStudyRewards)) { _ in
            AppServices.shared.closeSettingsWindow()
            reloadRewards()
            showRewards = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeStudyPopovers)) { _ in
            AppServices.shared.closeSettingsWindow()
            showRewards = false
        }
    }

    /// 浮动面板背景：无边框窗口自身全透明，必须自带毛玻璃底；
    /// 透明度只作用于背景层，文字/控件始终全亮；可自定义背景颜色。
    /// 鼠标悬停时透明度增加（类似测试面板 hover 效果），透明度为 0 也能看到半透明框
    @ViewBuilder
    private var panelBackground: some View {
        if onClose != nil {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(settings.studyBackgroundColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.regularMaterial))
                .opacity(hovering ? max(settings.studyOpacity, 0.22) : settings.studyOpacity)
                .allowsHitTesting(true)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
        }
    }

    /// 关闭当前学习界面（浮动面板关自己，菜单栏弹窗关弹窗）
    private func closeInterface() {
        if let onClose {
            onClose()
        } else {
            AppServices.shared.statusItem.closePopover()
        }
    }

    private func reloadRewards() {
        rewards = (try? AppServices.shared.database.rewardSummary()) ?? .empty
    }

    // MARK: - 顶部进度条

    private var header: some View {
        HStack(spacing: 10) {
            // 等级 + 连续打卡徒章（点击看奖励详情）
            Button {
                showRewards.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text("Lv\(rewards.level)")
                        .font(.caption2.bold())
                    if rewards.streakDays > 0 {
                        Text("🔥\(rewards.streakDays)")
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("等级与成就")
            .popover(isPresented: $showRewards, arrowEdge: .bottom) {
                RewardsPanel(summary: rewards)
            }

            Label("\(session.newDone)/\(session.newTotal)", systemImage: "sparkles")
            Label("\(session.reviewDone)/\(session.reviewTotal)", systemImage: "arrow.triangle.2.circlepath")
            Spacer()
            Button {
                settings.studyDirection = settings.studyDirection == .enToCn ? .cnToEn : .enToCn
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.plain)
            .help(settings.studyDirection == .enToCn
                  ? "当前：看英文出中文（点击切换为看中文拼英文）"
                  : "当前：看中文出英文（点击切换为看英文出中文）")
            Button {
                AppServices.shared.showTowerGame()
            } label: {
                Image(systemName: "gamecontroller")
            }
            .buttonStyle(.plain)
            .help("爬塔挑战：用单词闯关遗忘之塔")
            Button {
                AppServices.shared.showLibrary()
            } label: {
                Image(systemName: "books.vertical")
            }
            .buttonStyle(.plain)
            .help("词库：查看熟悉度与下次出现时间")
            Button {
                AppServices.shared.toggleQuizOverlay()
            } label: {
                Image(systemName: "keyboard.badge.ellipsis")
            }
            .buttonStyle(.plain)
            .help("练习浮层：双击浮层关闭（快捷键可在设置中修改）")
            Button {
                AppServices.shared.showSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 中部内容

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .loading:
            ProgressView("正在准备今日队列…")
        case .studying:
            if let item = session.currentItem {
                ZStack(alignment: .topTrailing) {
                    CardView(item: item, isRevealed: session.isRevealed)
                        .id(item.word.id)
                    // 单词详情：快速打开（Esc 关闭）
                    Button {
                        AppServices.shared.showWordDetail(item)
                    } label: {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        // 详情已打开时灯泡变黄填充（覆盖在原有图标上）
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .opacity(detailState.headword == item.word.headword ? 1 : 0)
                    )
                    .help("查看单词详情（Esc 关闭）")
                    .padding(8)
                }
            }
        case .finished:
            finishedView
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("出错了：\(message)")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    /// 完成页：提供「继续学习」与「再次复习」两个选项
    private var finishedView: some View {
        let canReview = ((try? session.pendingReviewItems().count) ?? 0) > 0
        return VStack(spacing: 10) {
            Text(canReview ? "🎉" : "🏆")
                .font(.system(size: 44))
            Text(roundFinishTitle)
                .font(.title3.bold())
            Text("新学 \(session.newDone) 个 · 复习 \(session.reviewDone) 个")
                .font(.callout)
                .foregroundStyle(.secondary)

            // 奖励结算
            HStack(spacing: 10) {
                Label("+\(rewards.todayXP) XP", systemImage: "bolt.fill")
                    .foregroundStyle(Color.orange)
                Label("Lv\(rewards.level) \(rewards.title)", systemImage: "star.circle.fill")
                    .foregroundStyle(Color.accentColor)
                if rewards.streakDays > 0 {
                    Label("\(rewards.streakDays) 天", systemImage: "flame.fill")
                        .foregroundStyle(Color.red)
                }
            }
            .font(.caption.weight(.medium))

            ProgressView(value: rewards.levelProgress)
                .frame(width: 180)

            if canReview {
                Text("今日还有 \(session.reviewableTodayCount) 个词没完全熟练")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("今日词语已经复习的很棒啦！")
                    .font(.caption)
                    .foregroundStyle(Color.green)
            }

            VStack(spacing: 6) {
                if session.hasMoreNewWords {
                    Button {
                        session.continueLearning()
                    } label: {
                        Label("继续学习（再来 \(session.dailyNewLimit) 个新词）", systemImage: "plus.circle")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("词库已经全部学完了 🎊")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if canReview {
                    Button {
                        session.reviewTodayAgain()
                    } label: {
                        Label("再次复习（按熟练度）", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: 220)
                    }
                    .controlSize(.large)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
    }

    private var roundFinishTitle: String {
        switch session.round {
        case .plan: return "今日任务完成！"
        case .extra: return "这一轮学完了！"
        case .review: return "本轮复习完成！"
        }
    }

    // MARK: - 底部操作区

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            if session.phase == .studying {
                if session.isRevealed {
                    ratingBar
                } else {
                    revealBar
                }
            } else {
                HStack {
                    Spacer()
                    quitButton
                }
                .padding(10)
            }
        }
    }

    /// 翻面按钮（快捷键可在设置中修改，默认空格）
    private var revealBar: some View {
        HStack {
            quitButton
            Spacer()
            Button {
                session.toggleReveal()
            } label: {
                Text(settings.studyDirection == .cnToEn ? "显示单词" : "显示答案")
                    .frame(maxWidth: 160)
            }
            .modifier(BindingShortcut(binding: settings.hotKeys[.revealWord] ?? .none))
            .controlSize(.large)
            Spacer()
            speakButton
        }
        .padding(10)
    }

    /// 四档自评（1-4）；可再按显示单词的快捷键收回答案
    private var ratingBar: some View {
        HStack(spacing: 8) {
            RatingButton(title: "忘记", key: "1", tint: .red) { rate(.again) }
            RatingButton(title: "模糊", key: "2", tint: .orange) { rate(.hard) }
            RatingButton(title: "记得", key: "3", tint: .green) { rate(.good) }
            RatingButton(title: "太简单", key: "4", tint: .blue) { rate(.easy) }
            RatingButton(title: "毕业", key: "5", tint: .gray) { session.graduateCurrentWord() }
            // 隐藏按钮：再按一次收回答案
            Button("") { session.toggleReveal() }
                .modifier(BindingShortcut(binding: settings.hotKeys[.revealWord] ?? .none))
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .padding(10)
    }

    /// 正式学习自评；教程由独立演示状态处理，不监听真实作答。
    private func rate(_ rating: Rating) {
        session.rate(rating)
    }

    private var speakButton: some View {
        Button {
            if let item = session.currentItem {
                SpeechService.shared.speak(item.word.headword)
            }
        } label: {
            Image(systemName: "speaker.wave.2")
        }
        .modifier(BindingShortcut(binding: settings.hotKeys[.speak] ?? .none))
        .help("再听一遍发音（\((settings.hotKeys[.speak] ?? .none).label)）")
    }

    private var quitButton: some View {
        Button {
            if let onClose {
                onClose()   // 浮动面板：仅关闭面板
            } else {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: onClose == nil ? "power" : "xmark")
        }
        .keyboardShortcut(onClose == nil ? "q" : "w")
        .help(onClose == nil ? "退出 DailyWord (⌘Q)" : "关闭面板")
    }
}

// MARK: - 单词卡片（支持 英→中 / 中→英 两个方向）

private struct CardView: View {
    let item: StudyItem
    let isRevealed: Bool
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 10) {
            if item.isNew {
                Text("新词")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }

            if settings.studyDirection == .enToCn {
                headwordText
                phoneticText
                if isRevealed {
                    definitionScroll(alignment: .leading)
                        .transition(.opacity)
                } else {
                    hintText("回忆词义 · \(revealHint)查看答案，再按隐藏")
                }
            } else {
                definitionScroll(alignment: .center)
                if isRevealed {
                    headwordText
                        .transition(.opacity)
                    phoneticText
                } else {
                    hintText("回忆英文单词 · \(revealHint)显示并发音，再按隐藏")
                }
            }
        }
        .padding(.vertical, 16)
        .onAppear {
            // 英→中：出卡即发音；中→英：揭晓时才发音（避免剧透）
            if settings.studyDirection == .enToCn {
                SpeechService.shared.speak(item.word.headword)
            }
        }
        .onChange(of: isRevealed) { revealed in
            if revealed && settings.studyDirection == .cnToEn {
                SpeechService.shared.speak(item.word.headword)
            }
        }
    }

    private var headwordText: some View {
        Text(item.word.headword)
            .font(.system(size: min(settings.wordFontSize, 44), weight: .bold, design: .rounded))
            .foregroundStyle(settings.wordColor ?? Color.primary)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var phoneticText: some View {
        if let phonetic = item.word.phonetic {
            Text("/\(phonetic)/")
                .font(.callout)
                .foregroundStyle((settings.wordColor ?? Color.primary).opacity(0.65))
        }
    }

    private func definitionScroll(alignment: TextAlignment) -> some View {
        ScrollView {
            Text(item.word.definitionCn)
                .font(.body)
                .foregroundStyle(settings.definitionColor ?? Color.primary)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity,
                       alignment: alignment == .center ? .center : .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 130)
        .padding(.horizontal, 20)
    }

    private var revealHint: String {
        let binding = settings.hotKeys[.revealWord] ?? .none
        return binding.isSet ? "\(binding.label) " : "点击按钮"
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 20)
    }
}

// MARK: - 按配置应用面板内快捷键

/// 把自定义绑定转为 SwiftUI 快捷键（仅当前窗口生效）
struct BindingShortcut: ViewModifier {
    let binding: HotKeyBinding

    func body(content: Content) -> some View {
        if let key = binding.keyEquivalent {
            content.keyboardShortcut(key, modifiers: binding.eventModifiers)
        } else {
            content
        }
    }
}

// MARK: - 自评按钮

/// 五档自评按钮（标题+数字键）；引导演示面板复用同一样式以保持界面一致。
struct RatingButton: View {
    let title: String
    let key: Character
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(String(key))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .tint(tint)
        .controlSize(.large)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }
}
