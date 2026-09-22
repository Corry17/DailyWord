import AppKit
import SwiftUI
import DailyWordCore

/// 定时弹卡控制器：
/// 按用户设置的固定间隔（分钟）定时弹出单词卡片，不再依赖艾宾浩斯 due_at。
/// 每次取词优先级：复习中 → 学习中 → 未学，同一张卡 15 分钟内不重复。
@MainActor
final class AmbientReviewController: ObservableObject {
    /// 当前到期待复习数（显示在菜单栏角标，仅供参考）
    @Published private(set) var dueCount = 0

    /// 学习面板/引导页打开期间暂停弹卡
    var isSuppressed = false {
        didSet { if isSuppressed { hidePanel(snoozeCurrent: false) } }
    }

    private let database: AppDatabase
    private let scheduler: SRSScheduler
    private var timer: Timer?
    private var panel: NSPanel?
    private var currentItem: StudyItem?
    /// 手动暂缓（cardUuid / new_headword → 截止时间）
    private var snoozedUntil: [String: Date] = [:]
    /// 最近弹过的卡（cardUuid / new_headword → 弹卡时间）
    private var recentlyShown: [String: Date] = [:]
    private var lastShownAt = Date.distantPast

    private let checkInterval: TimeInterval = 60
    private let snoozeInterval: TimeInterval = 15 * 60
    private let repeatWindow: TimeInterval = 15 * 60

    /// 两次弹卡最小间隔（用户设置，分钟数 * 60 秒）
    private var cooldown: TimeInterval {
        TimeInterval(max(1, AppSettings.shared.ambientIntervalMinutes)) * 60
    }

    init(database: AppDatabase, scheduler: SRSScheduler) {
        self.database = database
        self.scheduler = scheduler
        // 上次弹卡时间持久化：重启 App 后仍按用户设置的间隔计时，不会提前弹
        let saved = UserDefaults.standard.double(forKey: Self.lastShownKey)
        lastShownAt = saved > 0 ? Date(timeIntervalSince1970: saved) : .distantPast
    }

    private static let lastShownKey = "ambientLastShownAt"

    /// 更新弹卡时间（内存 + 持久化）
    private func setLastShown(_ date: Date) {
        lastShownAt = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastShownKey)
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// 立即检查并弹卡（供设置面板修改间隔后触发，不用等 60 秒）
    func checkNow() { tick() }

    /// 弹卡位置设置变更：忽略冷却，按新位置弹一张新卡
    func reposition() {
        // 先关掉当前弹卡（保留 currentItem 引用，避免回调时访问 nil）
        if let p = panel {
            self.panel = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                p.animator().alphaValue = 0
            }, completionHandler: { p.orderOut(nil) })
        }
        setLastShown(.distantPast)
        tick()
    }

    func refreshDueCount() {
        dueCount = (try? database.dueCount()) ?? 0
    }

    // MARK: - 调度

    /// 定时触发：弹卡一次（不依赖 due_at，按固定间隔）
    private func tick() {
        refreshDueCount()
        guard !isSuppressed,
              panel?.isVisible != true,
              Date().timeIntervalSince(lastShownAt) >= cooldown,
              let item = nextAmbientItem() else { return }
        show(item)
    }

    /// 取词优先级：复习中 → 学习中 → 未学；同一张卡 15 分钟内不重复
    private func nextAmbientItem() -> StudyItem? {
        let now = Date()
        let all = (try? database.allItems()) ?? []
        let windowStart = now.addingTimeInterval(-repeatWindow)

        // 优先级 1：复习中（state == .review），按到期时间排序
        let reviewItems = all.filter { $0.card?.state == .review }
            .sorted { ($0.card?.dueAt ?? .distantFuture) < ($1.card?.dueAt ?? .distantFuture) }
        if let item = firstUnshown(reviewItems, now: now, windowStart: windowStart) {
            return item
        }

        // 优先级 2：学习中（state == .learning）
        let learningItems = all.filter { $0.card?.state == .learning }
        if let item = firstUnshown(learningItems, now: now, windowStart: windowStart) {
            return item
        }

        // 优先级 3：未学（no card）
        let newItems = all.filter { $0.card == nil }
        if let item = firstUnshown(newItems, now: now, windowStart: windowStart) {
            return item
        }

        // 全部弹过：兜底取第一个未暂缓的
        return all.first { item in
            let key = item.card?.uuid ?? "new_\(item.word.headword.lowercased())"
            if let until = snoozedUntil[key], until > now { return false }
            return true
        }
    }

    /// 从列表中取第一个「未弹过/未暂缓」的词
    private func firstUnshown(_ items: [StudyItem], now: Date, windowStart: Date) -> StudyItem? {
        items.first { item in
            let key = item.card?.uuid ?? "new_\(item.word.headword.lowercased())"
            if let until = snoozedUntil[key], until > now { return false }
            if let shown = recentlyShown[key], shown > windowStart { return false }
            return true
        }
    }

    // MARK: - 浮卡展示

    private func show(_ item: StudyItem) {
        currentItem = item
        setLastShown(Date())
        if let card = item.card {
            recentlyShown[card.uuid] = Date()
        } else {
            recentlyShown["new_\(item.word.headword.lowercased())"] = Date()
        }
        // 清理过期的记录
        let cutoff = Date().addingTimeInterval(-repeatWindow)
        recentlyShown = recentlyShown.filter { $0.value > cutoff }

        let view = AmbientCardView(
            item: item,
            dueCount: dueCount,
            onRate: { [weak self] rating in
                guard let self else { return }
                self.setLastShown(Date())
                self.rate(rating)
            },
            onGraduate: { [weak self] in
                guard let self else { return }
                self.setLastShown(Date())
                self.graduateCurrent()
            },
            onDismiss: { [weak self] in
                guard let self else { return }
                self.setLastShown(Date())
                self.hidePanel(snoozeCurrent: true)
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []   // 无边框面板：禁止 SwiftUI 接管窗口尺寸约束，否则抛异常
        // 卡片尺寸固定（sizingOptions=[] 时 fittingSize 恒为 0，不能用于计算位置）
        let cardSize = NSSize(width: 348, height: 240)
        hosting.frame.size = cardSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .statusBar   // 弹卡保持最高层，醒目可见
        panel.becomesKeyOnlyIfNeeded = true   // 不抢 key window，避免误关其他窗口
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // 优先弹在鼠标所在屏幕（外接屏场景下用户操作哪块屏就弹哪块屏），fallback 主屏
        let mousePoint = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mousePoint) }
            ?? NSScreen.screens.first
        if let screen {
            let visible = screen.visibleFrame
            var origin = AppSettings.shared.ambientPosition.origin(
                in: visible, panelSize: panel.frame.size)
            // 钳制到屏幕可视区域内，确保卡片完整显示、不超出边界
            origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
        self.panel = panel
    }

    private func hidePanel(snoozeCurrent: Bool) {
        if snoozeCurrent, let item = currentItem {
            let key = item.card?.uuid ?? "new_\(item.word.headword.lowercased())"
            snoozedUntil[key] = Date().addingTimeInterval(snoozeInterval)
        }
        currentItem = nil
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - 浮卡上的快速自评

    private func graduateCurrent() {
        guard let item = currentItem else { return }
        try? database.setCardState(wordId: item.word.id, to: .suspended)
        hidePanel(snoozeCurrent: false)
        refreshDueCount()
    }

    private func rate(_ rating: Rating) {
        guard let item = currentItem else { return }
        let now = Date()
        // 未学词首次评分：自动创建卡片（与学习面板一致）
        let isNewWord = item.card == nil
        let before = item.card ?? .fresh(wordId: item.word.id, now: now)
        let after = scheduler.review(card: before, rating: rating, now: now)
        let log = ReviewLog(
            uuid: UUID().uuidString,
            cardUuid: after.uuid,
            wordId: item.word.id,
            rating: rating.rawValue,
            stateBefore: isNewWord ? "new" : before.state.rawValue,
            reviewedAt: now
        )
        try? database.recordReview(card: after, log: log, isNewWord: isNewWord, now: now)
        hidePanel(snoozeCurrent: false)
        refreshDueCount()
    }
}

// MARK: - 浮卡视图

private struct AmbientCardView: View {
    let item: StudyItem
    let dueCount: Int
    let onRate: (Rating) -> Void
    let onGraduate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(dueCount > 1 ? "复习时间 · 还有 \(dueCount) 个词到期" : "复习时间",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("先不看（15 分钟后再提醒）")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.word.headword)
                    .font(.title2.bold())
                if let phonetic = item.word.phonetic {
                    Text("/\(phonetic)/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    SpeechService.shared.speak(item.word.headword)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text(item.word.definitionCn)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Button("忘了") { onRate(.again) }
                    .tint(.red)
                Button("毕业") { onGraduate() }
                    .tint(.gray)
                Button("记得") { onRate(.good) }
                    .tint(.green)
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}
