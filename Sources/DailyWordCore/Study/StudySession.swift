import Foundation
import SwiftUI

/// 学习会话：管理今日队列与三种轮次
/// - plan：今日计划（到期复习 + 每日新词额度）
/// - extra：继续学习（额外批次，不计入"今日复习"范围）
/// - review：再次复习（按熟练度重刷今日计划内的词）
@MainActor
public final class StudySession: ObservableObject {
    public enum Phase: Equatable {
        case loading
        case studying
        case finished
        case failed(String)
    }

    public enum Round: Equatable {
        case plan
        case extra
        case review
    }

    @Published public private(set) var phase: Phase = .loading
    @Published public private(set) var round: Round = .plan
    @Published public private(set) var currentItem: StudyItem?
    @Published public var isRevealed = false

    // 今日进度
    @Published public private(set) var newDone = 0
    @Published public private(set) var newTotal = 0
    @Published public private(set) var reviewDone = 0
    @Published public private(set) var reviewTotal = 0

    /// 今日计划内"尚未完全熟练"的词数（决定完成页是否提供"再次复习"）
    @Published public private(set) var reviewableTodayCount = 0
    /// 词库里还有没有没学过的新词（决定完成页是否提供"继续学习"）
    @Published public private(set) var hasMoreNewWords = true

    /// 每日新词上限（可在设置中修改）
    @Published public private(set) var dailyNewLimit: Int

    private let database: AppDatabase
    private let scheduler: SRSScheduler
    private var queue: [StudyItem] = []
    /// 本轮内已计入进度的词（忘记后重现不重复计数）
    private var countedWordIds: Set<Int64> = []
    /// 今日计划内的词（含今天学过的历史记录）——"再次复习"的范围
    private var plannedWordIds: Set<Int64> = []
    /// "继续学习"额外学的词——不计入"再次复习"范围
    private var extraWordIds: Set<Int64> = []
    /// 错词重复机制：词 id → 本轮还需要再答对几次
    private var repeatsRemaining: [Int64: Int] = [:]

    public init(database: AppDatabase, scheduler: SRSScheduler = EbbinghausScheduler(), dailyNewLimit: Int = 20) {
        self.database = database
        self.scheduler = scheduler
        self.dailyNewLimit = dailyNewLimit
    }

    /// 当前词库 key（nil = 全部词库）；切换词库后需调用 start() 重建队列
    public var collectionKey: String?

    // MARK: - 熟练度

    /// 是否已完全熟练：走完艾宾浩斯阶梯（已掌握）
    public nonisolated static func isFullyProficient(_ item: StudyItem) -> Bool {
        guard let card = item.card else { return false }
        if card.state == .suspended { return true }   // 斩词不再复习
        return card.state == .mastered || card.repetition >= EbbinghausScheduler.steps.count
    }

    /// 熟练度档位（越小越不熟，复习时优先）
    private nonisolated static func familiarity(_ item: StudyItem) -> Int {
        guard let card = item.card else { return -1 }
        return card.state == .mastered ? Int.max : card.repetition
    }

    // MARK: - 队列构建

    /// 修改每日新词上限并重建今日队列（已学数量不受影响）
    public func updateDailyNewLimit(_ limit: Int, now: Date = Date()) {
        dailyNewLimit = max(1, limit)
        start(now: now)
    }

    /// 今日计划：到期复习在前，新词在后
    public func start(now: Date = Date()) {
        phase = .loading
        do {
            let due = try database.dueItems(now: now, collectionKey: collectionKey)
            let introducedToday = try database.newCardsCreatedToday(now: now)
            let stat = try database.todayStat(now: now)

            let remainingNew = max(0, dailyNewLimit - introducedToday)
            let fresh = try database.newWordItems(limit: remainingNew, collectionKey: collectionKey)

            queue = due + fresh
            countedWordIds = []
            extraWordIds = []
            repeatsRemaining = [:]
            round = .plan

            // 今日计划范围 = 今天已学过的词 + 本次到期复习 + 本次新词
            plannedWordIds = Set(try database.wordIdsStudiedToday(now: now))
                .union(due.map(\.word.id))
                .union(fresh.map(\.word.id))

            newDone = stat?.newLearned ?? 0
            newTotal = min(dailyNewLimit, newDone + fresh.count)
            reviewDone = 0
            reviewTotal = due.count

            advance()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 继续学习：再抓一批新词（数量 = 当前每日新词设置），照常安排复习排期
    public func continueLearning(now: Date = Date()) {
        do {
            let fresh = try database.newWordItems(limit: dailyNewLimit, collectionKey: collectionKey)
            guard !fresh.isEmpty else {
                hasMoreNewWords = false
                phase = .finished
                return
            }
            extraWordIds.formUnion(fresh.map(\.word.id))
            queue = fresh
            countedWordIds = []
            repeatsRemaining = [:]
            round = .extra
            advance()
            reviewableTodayCount = (try? pendingReviewItems().count) ?? 0
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 再次复习：把今日计划内还没完全熟练的词按熟练度分组乱序重刷一遍
    /// 重复机制：答错的词本轮需要再答对 2 次，“模糊”需要再答对 1 次，直到清完才算本轮结束
    public func reviewTodayAgain() {
        do {
            let pending = try pendingReviewItems()
            guard !pending.isEmpty else {
                reviewableTodayCount = 0
                phase = .finished
                return
            }
            queue = pending
            countedWordIds = []
            repeatsRemaining = [:]
            round = .review
            reviewDone = 0
            reviewTotal = pending.count
            advance()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 今日计划内待复习的词（未完全熟练）：先按熟练度分档，同档内随机洗牌
    /// → 保证“不熟的先考”，同时每次复习顺序都不一样
    public func pendingReviewItems() throws -> [StudyItem] {
        // 从数据库查今日所有已学词（不考虑 plan/extra 区分），避免不同面板间差异
        let allIds = try database.wordIdsStudiedToday()
        let grouped = Dictionary(grouping: try database.items(forWordIds: Array(allIds))
            .filter { !Self.isFullyProficient($0) }) { Self.familiarity($0) }
        return grouped.keys.sorted().flatMap { grouped[$0]!.shuffled() }
    }

    // MARK: - 卡片交互

    public func reveal() {
        guard phase == .studying, !isRevealed else { return }
        isRevealed = true
    }

    /// 空格双向显隐：已显示答案时再按空格可以重新隐藏
    public func toggleReveal() {
        guard phase == .studying else { return }
        isRevealed.toggle()
    }

    /// 朗读当前单词（供全局快捷键调用）
    public var currentHeadword: String? { currentItem?.word.headword }

    /// 将当前词标记为毕业（不再出现）
    public func graduateCurrentWord() {
        guard let item = currentItem else { return }
        try? database.setCardState(wordId: item.word.id, to: .suspended)
        advance()
    }

    /// 用户自评：更新卡片 → 落库 → 前进
    public func rate(_ rating: Rating, now: Date = Date()) {
        guard phase == .studying, isRevealed, let item = currentItem else { return }

        let isNewWord = item.isNew
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

        do {
            try database.recordReview(card: after, log: log, isNewWord: isNewWord, now: now)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // 进度计数（本轮内每个词只计一次）
        if !countedWordIds.contains(item.word.id) {
            countedWordIds.insert(item.word.id)
            if isNewWord { newDone += 1 } else { reviewDone += 1 }
        }

        // 重复机制：答错要再对 2 次，"模糊"要再对 1 次；答对则递减
        var remaining = repeatsRemaining[item.word.id] ?? 0
        switch rating {
        case .again:
            remaining = 2
        case .hard:
            remaining = max(remaining, 1)
        case .good, .easy:
            remaining = max(0, remaining - 1)
        }
        repeatsRemaining[item.word.id] = remaining

        // 需要重复的词插回队列随机位置（避开紧接着的下一张，也不固定在末尾）
        if remaining > 0 {
            let next = StudyItem(word: item.word, card: after)
            let lower = min(2, queue.count)
            let insertAt = queue.isEmpty ? 0 : Int.random(in: lower...queue.count)
            queue.insert(next, at: insertAt)
        }

        advance()
    }

    private func advance() {
        isRevealed = false
        if queue.isEmpty {
            currentItem = nil
            refreshCompletionOptions()
            phase = .finished
        } else {
            currentItem = queue.removeFirst()
            phase = .studying
        }
    }

    /// 刷新完成页两个选项的可用性
    private func refreshCompletionOptions() {
        reviewableTodayCount = (try? pendingReviewItems().count) ?? 0
        hasMoreNewWords = ((try? database.newWordItems(limit: 1).count) ?? 0) > 0
    }
}
