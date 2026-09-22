import Foundation
import GRDB
import DailyWordCore

// 轻量测试框架：Command Line Tools 没有 XCTest/Testing，用 swift run TestRunner 执行
var passed = 0
var failed = 0

func expect(_ condition: Bool, _ message: String,
            file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        let filename = (file as NSString).lastPathComponent
        print("  ❌ \(message)  (\(filename):\(line))")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String,
                               file: String = #file, line: Int = #line) {
    expect(actual == expected, "\(message) — 期望 \(expected)，实际 \(actual)", file: file, line: line)
}

func test(_ name: String, _ body: () throws -> Void) {
    let before = failed
    do {
        try body()
        print(failed == before ? "✅ \(name)" : "💥 \(name)")
    } catch {
        failed += 1
        print("💥 \(name) 抛出异常: \(error)")
    }
}

// MARK: - 公共工具

let now0 = Date(timeIntervalSince1970: 1_800_000_000)
let scheduler = SM2Scheduler()

func makeTestDatabase() throws -> AppDatabase {
    let database = try AppDatabase.makeInMemory()
    try database.dbQueue.write { db in
        for i in 1...30 {
            try db.execute(
                sql: "INSERT INTO word (id, headword, definition_cn, frequency) VALUES (?,?,?,?)",
                arguments: [i, "word\(i)", "释义\(i)", i]
            )
        }
    }
    return database
}

/// 完整背完一遍指定评分，模拟一天的学习
func studyAll(in database: AppDatabase, rating: Rating, dailyNewLimit: Int, now: Date) throws {
    let due = try database.dueItems(now: now)
    let introduced = try database.newCardsCreatedToday(now: now)
    let fresh = try database.newWordItems(limit: max(0, dailyNewLimit - introduced))
    for item in due + fresh {
        let before = item.card ?? .fresh(wordId: item.word.id, now: now)
        let after = scheduler.review(card: before, rating: rating, now: now)
        let log = ReviewLog(uuid: UUID().uuidString, cardUuid: after.uuid, wordId: item.word.id,
                            rating: rating.rawValue, stateBefore: item.isNew ? "new" : before.state.rawValue,
                            reviewedAt: now)
        try database.recordReview(card: after, log: log, isNewWord: item.isNew, now: now)
    }
}

// MARK: - SM-2 调度算法

print("— SM-2 调度算法 —")

test("新卡第一次'记得' → 1 天后复习，进入 review 状态") {
    let card = scheduler.review(card: .fresh(wordId: 1, now: now0), rating: .good, now: now0)
    expectEqual(card.intervalDays, 1, "间隔应为 1 天")
    expectEqual(card.repetition, 1, "repetition 应为 1")
    expectEqual(card.state, .review, "状态应为 review")
    expectEqual(card.dueAt, now0.addingTimeInterval(86_400), "到期时间应为明天")
    expect(abs(card.easiness - 2.5) < 0.001, "q=4 时 EF 不变")
}

test("新卡第一次'太简单' → 3 天，EF 增加") {
    let card = scheduler.review(card: .fresh(wordId: 1, now: now0), rating: .easy, now: now0)
    expectEqual(card.intervalDays, 3, "间隔应为 3 天")
    expect(abs(card.easiness - 2.6) < 0.001, "EF 应升至 2.6")
}

test("忘记 → repetition 归零、10 分钟后重现、记 lapse") {
    var card = scheduler.review(card: .fresh(wordId: 1, now: now0), rating: .good, now: now0)
    card = scheduler.review(card: card, rating: .again, now: now0)
    expectEqual(card.repetition, 0, "repetition 应归零")
    expectEqual(card.lapseCount, 1, "应记 1 次 lapse")
    expectEqual(card.state, .learning, "状态应回到 learning")
    expectEqual(card.dueAt, now0.addingTimeInterval(10 * 60), "10 分钟后重现")
    expect(card.easiness < 2.5, "忘记应降低 EF")
}

test("间隔按 1 → 6 → round(6*EF) 递增") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    card = scheduler.review(card: card, rating: .good, now: now0)
    expectEqual(card.intervalDays, 1, "第 1 次间隔")
    card = scheduler.review(card: card, rating: .good, now: now0)
    expectEqual(card.intervalDays, 6, "第 2 次间隔")
    card = scheduler.review(card: card, rating: .good, now: now0)
    expectEqual(card.intervalDays, 15, "第 3 次间隔 round(6*2.5)")
}

test("EF 永远不低于 1.3") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    for _ in 0..<20 {
        card = scheduler.review(card: card, rating: .again, now: now0)
    }
    expect(card.easiness >= 1.3, "EF 下限 1.3")
}

test("'模糊'也算成功，但 EF 下降") {
    let card = scheduler.review(card: .fresh(wordId: 1, now: now0), rating: .hard, now: now0)
    expectEqual(card.repetition, 1, "算一次成功")
    expectEqual(card.intervalDays, 1, "间隔 1 天")
    expect(abs(card.easiness - 2.36) < 0.001, "EF 应降至 2.36")
}

// MARK: - 今日队列闭环

print("— 今日队列闭环 —")

test("第一天: 队列 = 0 复习 + 20 新词(按词频排序)") {
    let database = try makeTestDatabase()
    expectEqual(try database.dueItems(now: now0).count, 0, "第一天无复习")
    let fresh = try database.newWordItems(limit: 20)
    expectEqual(fresh.count, 20, "20 个新词")
    expectEqual(fresh.first?.word.headword, "word1", "最高频优先")
}

test("核心验收: 第一天学 20 个全'记得' → 第二天 20 个到期复习, 新词不重复") {
    let database = try makeTestDatabase()
    try studyAll(in: database, rating: .good, dailyNewLimit: 20, now: now0)

    expectEqual(try database.dueItems(now: now0.addingTimeInterval(3600)).count, 0, "当天无到期")
    expectEqual(try database.newCardsCreatedToday(now: now0), 20, "今日新词额度已用完")

    let day2 = now0.addingTimeInterval(86_400 + 3600)
    let due = try database.dueItems(now: day2)
    expectEqual(due.count, 20, "第二天 20 个到期复习")
    expect(due.allSatisfy { $0.card?.state == .review }, "都应处于 review 状态")

    let fresh = try database.newWordItems(limit: 20)
    expectEqual(fresh.count, 10, "词库只剩 10 个新词")
    expectEqual(fresh.first?.word.headword, "word21", "新词从 word21 开始不重复")
}

test("忘记的词 10 分钟后仍在今日到期队列里(重启 App 也不会丢)") {
    let database = try makeTestDatabase()
    try studyAll(in: database, rating: .again, dailyNewLimit: 5, now: now0)
    let due = try database.dueItems(now: now0.addingTimeInterval(15 * 60))
    expectEqual(due.count, 5, "5 个忘记的词全部到期")
    expect(due.allSatisfy { $0.card?.state == .learning }, "都应处于 learning 状态")
}

test("每日统计正确累加") {
    let database = try makeTestDatabase()
    try studyAll(in: database, rating: .good, dailyNewLimit: 20, now: now0)
    let stat = try database.todayStat(now: now0)
    expectEqual(stat?.newLearned, 20, "新学 20")
    expectEqual(stat?.reviewed, 20, "复习动作 20 次")
}

test("新词额度当天已用完时不再给新词") {
    let database = try makeTestDatabase()
    try studyAll(in: database, rating: .good, dailyNewLimit: 20, now: now0)
    let remaining = max(0, 20 - (try database.newCardsCreatedToday(now: now0)))
    expectEqual(remaining, 0, "额度剩余 0")
    expectEqual(try database.newWordItems(limit: remaining).count, 0, "不再给新词")
}

// MARK: - 艾宾浩斯阶梯调度

print("— 艾宾浩斯阶梯调度 —")

let ebb = EbbinghausScheduler()

test("新卡'记得' → 30 分钟后复习（learning 状态，无感弹卡承接）") {
    let card = ebb.review(card: .fresh(wordId: 1, now: now0), rating: .good, now: now0)
    expectEqual(card.dueAt, now0.addingTimeInterval(30 * 60), "30 分钟后到期")
    expectEqual(card.repetition, 1, "进入第 1 级")
    expectEqual(card.state, .learning, "不足 1 天仍为 learning")
}

test("阶梯递进: 30分钟 → 12小时 → 1天 → 2天，满 1 天转 review") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    card = ebb.review(card: card, rating: .good, now: now0)
    expectEqual(card.dueAt, now0.addingTimeInterval(30 * 60), "第 1 次: 30 分钟")
    card = ebb.review(card: card, rating: .good, now: now0)
    expectEqual(card.dueAt, now0.addingTimeInterval(12 * 3600), "第 2 次: 12 小时")
    expectEqual(card.state, .learning, "12 小时仍为 learning")
    card = ebb.review(card: card, rating: .good, now: now0)
    expectEqual(card.dueAt, now0.addingTimeInterval(86_400), "第 3 次: 1 天")
    expectEqual(card.state, .review, "满 1 天转 review")
    card = ebb.review(card: card, rating: .good, now: now0)
    expectEqual(card.dueAt, now0.addingTimeInterval(2 * 86_400), "第 4 次: 2 天")
}

test("忘记 → 回到阶梯起点，5 分钟后重现") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    for _ in 0..<3 { card = ebb.review(card: card, rating: .good, now: now0) }
    card = ebb.review(card: card, rating: .again, now: now0)
    expectEqual(card.repetition, 0, "回到起点")
    expectEqual(card.dueAt, now0.addingTimeInterval(5 * 60), "5 分钟后重现")
    expectEqual(card.lapseCount, 1, "记 1 次 lapse")
}

test("模糊 → 停留在当前级重复间隔") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    card = ebb.review(card: card, rating: .good, now: now0)  // 级 1
    card = ebb.review(card: card, rating: .hard, now: now0)
    expectEqual(card.repetition, 1, "级数不变")
    expectEqual(card.dueAt, now0.addingTimeInterval(30 * 60), "重复 30 分钟间隔")
}

test("太简单 → 跳级") {
    let card = ebb.review(card: .fresh(wordId: 1, now: now0), rating: .easy, now: now0)
    expectEqual(card.dueAt, now0.addingTimeInterval(12 * 3600), "直接到 12 小时节点")
    expectEqual(card.repetition, 2, "跳过一级")
}

test("走完整条阶梯 → 已掌握，180 天超长间隔后再出现") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    card.repetition = EbbinghausScheduler.steps.count - 1  // 级 7，即将完成 30 天节点
    card = ebb.review(card: card, rating: .good, now: now0)
    expectEqual(card.dueAt, now0.addingTimeInterval(30 * 86_400), "最后一级: 30 天")
    expectEqual(card.state, .review, "尚未掌握")
    card = ebb.review(card: card, rating: .good, now: now0)
    expectEqual(card.state, .mastered, "走完阶梯后判定已掌握")
    expectEqual(card.dueAt, now0.addingTimeInterval(180 * 86_400), "180 天后再出现")
}

test("已掌握的词再次'记得' → 保持已掌握，继续 180 天") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    card.repetition = 9
    card.state = .mastered
    let after = ebb.review(card: card, rating: .good, now: now0)
    expectEqual(after.state, .mastered, "保持已掌握")
    expectEqual(after.dueAt, now0.addingTimeInterval(180 * 86_400), "继续 180 天间隔")
}

test("已掌握的词忘记 → 回到阶梯起点重学") {
    var card = StudyCard.fresh(wordId: 1, now: now0)
    card.repetition = 9
    card.state = .mastered
    let after = ebb.review(card: card, rating: .again, now: now0)
    expectEqual(after.state, .learning, "回到学习中")
    expectEqual(after.repetition, 0, "阶梯归零")
    expectEqual(after.dueAt, now0.addingTimeInterval(5 * 60), "5 分钟后重现")
}

test("词库手动调整学习状态：已掌握 / 斩词 / 重置未学") {
    let database = try makeTestDatabase()
    // 直接标记已掌握
    try database.setCardState(wordId: 1, to: .mastered, now: now0)
    var item = try database.allItems().first { $0.word.id == 1 }!
    expectEqual(item.card?.state, .mastered, "状态应为已掌握")
    expect(item.card!.dueAt > now0.addingTimeInterval(179 * 86_400), "下次出现应在 180 天后")
    // 斩词后不进入到期队列
    try database.setCardState(wordId: 1, to: .suspended, now: now0)
    let due = try database.dueItems(now: now0.addingTimeInterval(365 * 86_400))
    expect(!due.contains { $0.word.id == 1 }, "斩词不应出现在到期队列")
    // 重置为未学
    try database.setCardState(wordId: 1, to: nil, now: now0)
    item = try database.allItems().first { $0.word.id == 1 }!
    expect(item.card == nil, "卡片应被删除，回到未学")
}

test("熟练度判定：未学/学习中未完全熟练，已掌握/斩词算完全熟练") {
    let database = try makeTestDatabase()
    let items = try database.allItems()
    let fresh = items.first { $0.word.id == 1 }!
    expect(!StudySession.isFullyProficient(fresh), "未学的词需要复习")

    try database.setCardState(wordId: 1, to: .learning, now: now0)
    var item = try database.items(forWordIds: [1]).first!
    expect(!StudySession.isFullyProficient(item), "学习中需要复习")

    try database.setCardState(wordId: 1, to: .mastered, now: now0)
    item = try database.items(forWordIds: [1]).first!
    expect(StudySession.isFullyProficient(item), "已掌握不再复习")

    try database.setCardState(wordId: 1, to: .suspended, now: now0)
    item = try database.items(forWordIds: [1]).first!
    expect(StudySession.isFullyProficient(item), "斩词不再复习")
}

test("今日学过的词可以从流水恢复（支撑“再次复习”范围）") {
    let database = try makeTestDatabase()
    try studyAll(in: database, rating: .good, dailyNewLimit: 5, now: now0)
    let ids = try database.wordIdsStudiedToday(now: now0)
    expectEqual(ids.count, 5, "今日学过 5 个词")
    // 跨天后不属于“今日”
    let tomorrow = now0.addingTimeInterval(86_400 * 2)
    expectEqual(try database.wordIdsStudiedToday(now: tomorrow).count, 0, "隔天后不计入今日")
}

test("items(forWordIds:) 返回词 + 学习状态") {
    let database = try makeTestDatabase()
    try database.setCardState(wordId: 3, to: .learning, now: now0)
    let items = try database.items(forWordIds: [2, 3])
    expectEqual(items.count, 2, "返回 2 条")
    expect(items.first { $0.word.id == 2 }?.card == nil, "word2 无卡片")
    expectEqual(items.first { $0.word.id == 3 }?.card?.state, .learning, "word3 学习中")
}

// MARK: - 奖励机制

print("— 奖励机制 —")

test("经验计算：新学 +3 · 记得 +2 · 模糊 +1 · 忘记 +0") {
    expectEqual(RewardEngine.xp(rating: 3, isNewWord: true), 3, "新学")
    expectEqual(RewardEngine.xp(rating: 3, isNewWord: false), 2, "记得")
    expectEqual(RewardEngine.xp(rating: 4, isNewWord: false), 2, "太简单")
    expectEqual(RewardEngine.xp(rating: 2, isNewWord: false), 1, "模糊")
    expectEqual(RewardEngine.xp(rating: 1, isNewWord: false), 0, "忘记不加分")
}

test("等级派生：阶段递增，级内进度正确") {
    expectEqual(RewardEngine.levelInfo(xp: 0).level, 1, "0 XP 为 1 级")
    expectEqual(RewardEngine.levelInfo(xp: 199).level, 1, "未满 200 仍为 1 级")
    expectEqual(RewardEngine.levelInfo(xp: 200).level, 2, "200 XP 升到 2 级")
    let info = RewardEngine.levelInfo(xp: 230)
    expectEqual(info.level, 2, "230 XP 为 2 级")
    expectEqual(info.inLevel, 30, "级内 30 XP")
    expectEqual(info.needed, 320, "2 级升级需 320 XP")
}

test("连续打卡：今天未打卡但昨天有 → 连击仍在") {
    let calendar = Calendar.current
    let fmt = { (offset: Int) -> String in
        DailyStat.localDateString(for: calendar.date(byAdding: .day, value: offset, to: now0)!)
    }
    expectEqual(AppDatabase.currentStreak(dates: [fmt(0), fmt(-1), fmt(-2)], now: now0), 3, "连续 3 天")
    expectEqual(AppDatabase.currentStreak(dates: [fmt(-1), fmt(-2)], now: now0), 2, "今天未学仍算 2 天")
    expectEqual(AppDatabase.currentStreak(dates: [fmt(-3), fmt(-4)], now: now0), 0, "断了则归零")
    expectEqual(AppDatabase.currentStreak(dates: [], now: now0), 0, "无记录为 0")
}

test("最长连击统计") {
    let calendar = Calendar.current
    let fmt = { (offset: Int) -> String in
        DailyStat.localDateString(for: calendar.date(byAdding: .day, value: offset, to: now0)!)
    }
    // 最近 2 天连续 + 更早 4 天连续
    let dates = [fmt(0), fmt(-1), fmt(-5), fmt(-6), fmt(-7), fmt(-8)]
    expectEqual(AppDatabase.bestStreak(dates: dates), 4, "最长连击 4 天")
}

test("奖励汇总：学习后 XP/等级/成就都更新") {
    // 清理游戏成就键，避免本机真实数据污染 XP 断言
    let testDefaults = UserDefaults.standard
    for key in ["towerRuns", "towerWins", "towerPathCompleted", "towerCleared_knight",
                "towerCleared_mage", "towerCleared_rogue", "towerCleared_healer",
                "towerCleared_gambler", "towerCleared_demon", "towerDemonUnlocked",
                "towerDemonCollected", "towerCollected", "towerTombWins"] {
        testDefaults.removeObject(forKey: key)
    }
    let database = try makeTestDatabase()
    var summary = try database.rewardSummary(now: now0)
    expectEqual(summary.xp, 0, "初始 0 XP")
    expectEqual(summary.level, 1, "初始 1 级")

    try studyAll(in: database, rating: .good, dailyNewLimit: 10, now: now0)
    summary = try database.rewardSummary(now: now0)
    // 30（10 新词 × 3 XP）+ 30（成就“初来报到”解锁奖励）
    expectEqual(summary.xp, 60, "10 个新词 × 3 XP + 初来报到成就 30")
    expectEqual(summary.todayXP, 30, "今日 XP（成就经验不计入今日）")
    expectEqual(summary.learnedCount, 10, "已学 10 个")
    expectEqual(summary.streakDays, 1, "今日打卡 1 天")
    expect(summary.achievements.first { $0.id == "first" }?.unlocked == true, " 解锁初来报到")
    expect(summary.achievements.first { $0.id == "hundred" }?.unlocked == false, "百词集未解锁")
    
    // 标记掌握后额外 +10 XP
    try database.setCardState(wordId: 1, to: .mastered, now: now0)
    summary = try database.rewardSummary(now: now0)
    expectEqual(summary.masteredCount, 1, "1 个已掌握")
    expectEqual(summary.xp, 70, "掌握加成 +10（含成就 30）")
}

// MARK: - 上手引导

print("— 上手引导状态与多屏布局 —")

func onboarding(at step: OnboardingProgress.Step) -> OnboardingProgress {
    var progress = OnboardingProgress()
    progress.start()
    for _ in 0..<step.rawValue { progress.advance(ifCurrent: progress.revision) }
    return progress
}

test("引导完整导航：无互动也能走完，首尾不越界") {
    var progress = OnboardingProgress()
    expect(!progress.isActive, "默认未开始")
    expect(!progress.advance(ifCurrent: progress.revision), "未开始时不能推进")
    progress.start()
    expect(!progress.back(), "欢迎页不能后退")
    for step in OnboardingProgress.Step.allCases {
        expectEqual(progress.step, step, "按顺序访问每一步")
        let advanced = progress.advance(ifCurrent: progress.revision)
        expectEqual(advanced, step != .complete, "最后一步不能越界")
    }
    expectEqual(progress.step, .complete, "结束页保持稳定")
}

test("手动切步、后退和重新开始都会使旧回调失效") {
    var progress = onboarding(at: .study)
    let oldToken = progress.revision
    expect(progress.record(.studyRated), "学习步骤接受自评")
    expect(!progress.record(.studyRated), "重复自评不重复调度")
    expect(progress.advance(ifCurrent: oldToken), "手动下一步生效")
    expect(!progress.advance(ifCurrent: oldToken), "原自动推进不能再跳一步")
    expect(progress.back(), "可以回到学习步骤")
    expect(!progress.accepts(oldToken), "回到同一步也不能接受旧令牌")
    let beforeRestart = progress.revision
    progress.start()
    expect(!progress.accepts(beforeRestart), "重开会话丢弃旧任务")
    expect(progress.completedInteractions.isEmpty, "重看时清空互动记录")
}

test("互动按步骤匹配，不相关操作不推进") {
    let interactions: [(OnboardingProgress.Step, OnboardingProgress.Interaction)] = [
        (.study, .studyRated), (.quiz, .quizAnswered), (.opacityDemo, .opacityChanged),
        (.movement, .panelMoved), (.tripleClose, .tripleClosed)
    ]
    for (step, event) in interactions {
        var progress = onboarding(at: step)
        expect(progress.record(event), "当前步骤接受对应互动")
        expect(!progress.record(event), "同一步只鼓励一次")
        expectEqual(progress.step, step, "记录互动本身不会提前切换步骤")
    }
    var progress = onboarding(at: .library)
    for (_, event) in interactions { expect(!progress.record(event), "浏览词库时忽略其他互动") }
}

test("任意步骤结束后，延迟展示与自动推进均失效") {
    for step in OnboardingProgress.Step.allCases {
        var progress = onboarding(at: step)
        let token = progress.revision
        progress.stop()
        expect(!progress.accepts(token), "结束后不得重新弹窗")
        expect(!progress.advance(ifCurrent: token), "结束后不得继续推进")
        expect(!progress.back(), "结束后后退按钮的旧回调无效")
        expect(!progress.record(.tripleClosed), "结束后的窗口清理不算用户互动")
    }
}

test("菜单栏与屏幕边缘：气泡保持可见，箭头跟随真实锚点") {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 880)
    let size = CGSize(width: 388, height: 440)
    let menu = OnboardingPlacement.resolve(anchor: CGRect(x: 1400, y: 880, width: 24, height: 22),
                                           visibleFrame: screen, size: size, preferBelow: true)
    expectEqual(menu.arrow, .up, "菜单栏气泡置于图标下方")
    expect(screen.contains(CGRect(origin: menu.origin, size: size)), "右边缘气泡不越界")
    expect(menu.arrowOffset > 0, "贴边时箭头向图标方向偏移")
    expect(abs(menu.arrowOffset) <= size.width / 2 - 28, "箭头不离开气泡边缘")
    let left = OnboardingPlacement.resolve(anchor: CGRect(x: 8, y: 220, width: 340, height: 420),
                                           visibleFrame: screen, size: size)
    expectEqual(left.arrow, .left, "左边没有空间时放右边")
    let right = OnboardingPlacement.resolve(anchor: CGRect(x: 1090, y: 220, width: 340, height: 420),
                                            visibleFrame: screen, size: size)
    expectEqual(right.arrow, .right, "右边锚点的气泡放左边")
}

test("副屏负坐标、缺失锚点与小屏幕均可安全降级") {
    let screens = [CGRect(x: -1920, y: -200, width: 1920, height: 1000),
                   CGRect(x: 0, y: 0, width: 800, height: 600)]
    let size = CGSize(width: 388, height: 440)
    for screen in screens {
        let anchors: [CGRect?] = [nil, screen.insetBy(dx: 15, dy: 15),
                                 CGRect(x: screen.maxX - 340, y: screen.minY, width: 340, height: 420)]
        for anchor in anchors {
            let result = OnboardingPlacement.resolve(anchor: anchor, visibleFrame: screen, size: size)
            expect(screen.contains(CGRect(origin: result.origin, size: size)), "气泡不应出屏")
            if anchor == nil || anchor == screen.insetBy(dx: 15, dy: 15) {
                expectEqual(result.arrow, .none, "无锚点或无空位时不显示误导箭头")
            }
        }
    }
}

// MARK: - 稳定性与隔离回归

print("— 翻译请求、剪贴板和演示隔离 —")

test("最新选中优先：A→B→A，过期读词和翻译均不能回写") {
    var state = SelectionTranslationState()
    expect(state.beginRequest() == nil, "关闭状态不接受自动翻译")
    state.open()
    let a = state.beginRequest()!
    expect(state.accepts(a), "接受首次选中 A")
    let b = state.beginRequest()!
    expect(a.isCancelled, "选中 B 取消 A 的所有工作")
    expect(!state.accepts(a), "迟到的 A 不得覆盖 B")
    let aAgain = state.beginRequest()!
    expect(!state.accepts(b), "迟到的 B 不得覆盖新 A")
    expect(!state.accepts(a), "文本相同也不能复用最早 A 的结果")
    expect(state.accepts(aAgain), "仅最新 A 可更新")
    state.close()
    expect(aAgain.isCancelled, "关闭取消取词和网络")
    expect(!state.accepts(aAgain), "关闭后不能重新弹出")
    state.open()
    expect(!state.accepts(aAgain), "重开后旧窗口请求仍无效")
    let reopened = state.beginRequest()!
    expect(state.accepts(reopened), "重开可接受新请求")
}

test("取消任务幂等，取消后新增后备请求会立即取消") {
    let request = TranslationRequest()
    var calls = 0
    request.onCancel { calls += 1 }
    request.onCancel { calls += 1 }
    request.cancel()
    request.cancel()
    expectEqual(calls, 2, "每个取消回调只执行一次")
    request.onCancel { calls += 1 }
    expectEqual(calls, 3, "迟到的网络任务立即取消")
    expect(request.allowsClipboardRestore, "普通换词仍允许条件恢复")
    request.cancel(preservingClipboard: true)
    expect(!request.allowsClipboardRestore, "真实复制优先，旧事务不能恢复快照")
}

test("取消令牌支持并发注册与取消，不遗漏回调") {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0
        func increment() { lock.lock(); storage += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
    }
    let request = TranslationRequest()
    let counter = Counter()
    DispatchQueue.concurrentPerform(iterations: 100) { index in
        request.onCancel { counter.increment() }
        if index % 10 == 0 { request.cancel() }
    }
    request.cancel()
    expectEqual(counter.value, 100, "并发注册回调恰好一次")
}

test("剪贴板：旧计数不算新复制，二次变化禁止恢复") {
    var transaction = ClipboardTransaction(initialCount: 10)
    expect(!transaction.observe(10), "已有剪贴板不能当选区")
    expect(!transaction.mayRestore(currentCount: 10), "没有执行新复制不写剪贴板")
    expect(transaction.observe(11), "接受本次复制变化")
    expect(transaction.mayRestore(currentCount: 11), "仅本事务未被改动时可恢复")
    expect(!transaction.observe(12), "用户再次复制使事务过期")
    expect(!transaction.mayRestore(currentCount: 12), "不覆盖用户最新剪贴板")
    let newTransaction = ClipboardTransaction(initialCount: 12)
    expect(!newTransaction.mayRestore(currentCount: 12), "旧变化在新事务中也不是新复制")
}

test("HTML 文本兜底保留段落和字符，不包含脚本或样式") {
    let html = "<style>.hidden{color:red}</style><script>secret()</script><p>A&nbsp;&amp; B</p><div>&#x4E2D;&#25991;<br>Next</div>"
    let text = ClipboardHTMLText.decode(html)
    expect(text.contains("A & B"), "解析常用 HTML 实体")
    expect(text.contains("中文\nNext"), "解析数值实体并保留换行")
    expect(!text.contains("secret") && !text.contains("hidden"), "不翻译脚本和样式")
    expectEqual(ClipboardHTMLText.decode("&lt;tag&gt;"), "<tag>", "转义文字不是标签")
}

test("演示翻面、自评和拼写只改变示例状态") {
    var demo = OnboardingDemoState()
    expect(!demo.rate(3), "未翻面不记自评")
    demo.flip()
    expect(demo.isRevealed, "演示可翻面")
    expect(demo.rate(3), "支持示例自评")
    expectEqual(demo.rating, 3, "自评只记录在示例里")
    expect(!demo.rate(5), "演示不支持毕业写入")
    expect(!demo.choose(-1), "无效选项不越界")
    expect(!demo.choose(0), "答错可以重试")
    expect(demo.choose(OnboardingDemoState.correctOption), "示例选择题正确判分")
    demo.quizInput = " APPLE \n"
    expect(demo.submitSpelling(), "演示拼写忽略大小写和边缘空白")
    demo.quizInput = ""
    expect(!demo.submitSpelling(), "空答案不通过")
    _ = demo.adjustOpacity(-10)
    expectEqual(demo.opacity, 0, "演示透明度下限")
    expect(!demo.adjustOpacity(-1), "到下限不再虚报变化")
    _ = demo.adjustOpacity(10)
    expectEqual(demo.opacity, 1, "演示透明度上限")
    let fresh = OnboardingDemoState()
    expect(fresh.rating == nil && fresh.quizCorrect == nil, "演示实例彼此独立")
    expectEqual(fresh.opacity, 0.85, "新演示不沿用上次调整")
}

test("演示操作不写复习记录和 XP") {
    let database = try makeTestDatabase()
    let before = try database.rewardSummary(now: now0)
    var demo = OnboardingDemoState()
    demo.flip()
    _ = demo.rate(4)
    _ = demo.choose(1)
    _ = demo.adjustOpacity(-0.3)
    let after = try database.rewardSummary(now: now0)
    expectEqual(before.xp, after.xp, "演示没有 XP 写入")
    expectEqual(before.learnedCount, after.learnedCount, "演示没有已学状态变更")
    let items = try database.allItems()
    expect(items.allSatisfy { $0.card == nil }, "演示没有创建真实学习卡")
}

test("词根表初始化与旧键/新增键覆盖") {
    let roots = WordRootCatalog.meanings
    expect(roots.count > 200, "保留词根覆盖规模")
    expectEqual(roots["clam"], "喊/叫", "重复键保留原有释义")
    expectEqual(roots["spir"], "呼吸/精神", "保留原有完整含义")
    expectEqual(roots["techn"], "技术/工艺", "保留扩充词根")
    expect(roots.allSatisfy { !$0.key.isEmpty && !$0.value.isEmpty && $0.key == $0.key.lowercased() }, "词根条目完整且标准化")
}

test("设置窗口在屏幕四边和负坐标副屏内钳制") {
    for screen in [CGRect(x: 0, y: 20, width: 1440, height: 880),
                   CGRect(x: -1600, y: -300, width: 1600, height: 900)] {
        for origin in [CGPoint(x: screen.minX - 400, y: screen.maxY),
                       CGPoint(x: screen.maxX, y: screen.minY - 600),
                       CGPoint(x: screen.midX, y: screen.midY)] {
            let frame = WindowPlacement.clampedFrame(CGRect(origin: origin, size: CGSize(width: 320, height: 540)), in: screen)
            expect(screen.contains(frame), "设置窗口整体位于可视区")
            expectEqual(frame.size, CGSize(width: 320, height: 540), "正常屏幕不缩小设置")
        }
    }
    let small = CGRect(x: 0, y: 0, width: 300, height: 400)
    expectEqual(WindowPlacement.clampedFrame(CGRect(x: -100, y: -100, width: 1000, height: 1000), in: small), small,
                "窗口大于屏幕时缩到可视区")
}

// MARK: - 快捷键与备份安全

print("— 快捷键与备份事务 —")

func expectFailure(_ message: String, _ body: () throws -> Void) {
    do { try body(); expect(false, message) }
    catch { expect(true, message) }
}

test("快捷键必须完整匹配修饰键，未绑定不会触发") {
    let selection = ShortcutBinding(keyCode: 17, modifiers: 0x0800)
    expect(selection.matches(keyCode: 17, modifiers: 0x0800), "正确的 Option+T 匹配")
    expect(!selection.matches(keyCode: 17, modifiers: 0x1800), "Control+Option+T 不串到划词翻译")
    expect(!selection.matches(keyCode: 17, modifiers: 0x0100), "Command+T 不串到 Option+T")
    expect(!selection.matches(keyCode: 17, modifiers: 0), "裸字母不触发全局动作")
    expect(!selection.matches(keyCode: 18, modifiers: 0x0800), "不同键码不触发")
    expect(!ShortcutBinding.none.matches(keyCode: -1, modifiers: 0), "未绑定不会匹配")
    expect(ShortcutBinding(keyCode: 49, modifiers: 0).matches(keyCode: 49, modifiers: 0), "无修饰空格继续支持")
}

test("快捷键冲突释放会持久化未设置，不在重启时复活") {
    let first = ShortcutBinding(keyCode: 17, modifiers: 0x0800)
    let second = ShortcutBinding(keyCode: 17, modifiers: 0x1800)
    let old = ["selection": first, "input": second]
    let changed = ShortcutBinding.assigning(first, to: "input", in: old)
    expectEqual(changed["input"], first, "新动作得到绑定")
    expectEqual(changed["selection"], ShortcutBinding.none, "原动作明确清空，不删除 key")
    let restored = changed.mapValues { ShortcutBinding(storage: $0.storage)! }
    expectEqual(restored["selection"], ShortcutBinding.none, "往返存储后仍未设置")
    expectEqual(old["selection"], first, "取消录制不修改原字典")
    let cleared = ShortcutBinding.assigning(.none, to: "input", in: old)
    expectEqual(cleared["selection"], first, "清除一个动作不影响其他动作")
}

test("快捷键恢复：自定义优先于缺省，重复历史数据得到唯一绑定") {
    let normal = ShortcutBinding(keyCode: 17, modifiers: 0x0800)
    let modified = ShortcutBinding(keyCode: 17, modifiers: 0x1800)
    let defaults = ["selection": normal, "input": modified]
    let restored = ShortcutBinding.restoring(defaults: defaults, stored: ["input": normal.storage], order: ["selection", "input"])
    expectEqual(restored["input"], normal, "自定义键保留")
    expectEqual(restored["selection"], ShortcutBinding.none, "冲突的缺省键不能复活")
    let cleared = ShortcutBinding.restoring(defaults: defaults, stored: ["input": "-1:0"], order: ["selection", "input"])
    expectEqual(cleared["input"], ShortcutBinding.none, "清除绑定不能回落到默认")
    let repeated = ShortcutBinding.restoring(defaults: defaults, stored: ["input": normal.storage, "selection": normal.storage], order: ["selection", "input"])
    expectEqual(repeated.values.filter(\.isSet).count, 1, "历史重复值只保留一个动作")
    let stable = ShortcutBinding.restoring(defaults: defaults, stored: repeated.mapValues(\.storage), order: ["selection", "input"])
    expectEqual(stable, repeated, "重启恢复规则幂等")
}

test("无效快捷键导入值在进入系统 API 前拒绝") {
    for stored in ["-2:0", "128:2048", "17:-1", "17:999999999999", "17:2048:0", ":2048", "9999999999999999999999999:0"] {
        expect(ShortcutBinding(storage: stored) == nil, "拒绝损坏绑定 \(stored)")
    }
    expectEqual(ShortcutBinding(storage: "-1:0"), ShortcutBinding.none, "显式清空可往返")
    expectEqual(ShortcutBinding(storage: "17:6144")?.modifiers, 6144, "保留用户自定义组合，不自动迁移")
}

test("备份封装校验 app、version 和分组结构") {
    let data = try BackupArchive.encode(sections: ["settings": ["dailyNewLimit": 25]])
    let decoded = try BackupArchive.decode(data)
    expectEqual((decoded["settings"] as? [String: Int])?["dailyNewLimit"], 25, "保留每日新词量")
    let invalid: [[String: Any]] = [
        ["app": "Other", "version": 1, "sections": ["settings": [:]]],
        ["app": "DailyWord", "version": 2, "sections": ["settings": [:]]],
        ["app": "DailyWord", "version": true, "sections": ["settings": [:]]],
        ["app": "DailyWord", "version": 1, "sections": ["settings": []]],
        ["app": "DailyWord", "version": 1, "sections": ["unknown": [:]]]
    ]
    for object in invalid {
        expectFailure("拒绝无效备份封装") { _ = try BackupArchive.decode(JSONSerialization.data(withJSONObject: object)) }
    }
    expectFailure("未勾选任何项时不导出空备份") { _ = try BackupArchive.encode(sections: [:]) }
}

test("备份设置空值/二进制安全，非法值在写入前拒绝") {
    let changes = try BackupArchive.defaultsChanges(["wordColorRGBA": NSNull(), "blob": ["__data__": Data([1, 2]).base64EncodedString()], "other": 42],
                                                    allowedKeys: ["wordColorRGBA", "blob"])
    expect(changes["wordColorRGBA"] is NSNull, "顶层 null 保留恢复默认语义")
    expectEqual(changes["blob"] as? Data, Data([1, 2]), "二进制 marker 还原")
    expect(changes["other"] == nil, "非白名单字段不导入")
    expectFailure("拒绝坏 base64") { _ = try BackupArchive.defaultsChanges(["blob": ["__data__": "!@"]], allowedKeys: ["blob"]) }
    expectFailure("拒绝嵌套 null，不能传入 UserDefaults") { _ = try BackupArchive.defaultsChanges(["blob": ["x": NSNull()]], allowedKeys: ["blob"]) }
    for invalid in [["quizOpacity": 10], ["dailyNewLimit": 2.5], ["wordFontSize": -2], ["quizFontSize": true]] as [[String: Any]] {
        expectFailure("拒绝越界或错误类型设置") { try BackupArchive.validateSettings(invalid) }
    }
    expectFailure("拒绝无效快捷键值") { try BackupArchive.validateSettings(["hotKeyBindingsV2": ["togglePanel": "-4:-1"]]) }
    expectFailure("拒绝备份内重复快捷键") { try BackupArchive.validateSettings(["hotKeyBindingsV2": ["a": "17:2048", "b": "17:2048"]]) }
    try BackupArchive.validateSettings(["dailyNewLimit": 25, "studyOpacity": 0, "wordColorRGBA": [1.0, 0, 0, 1], "translateWholeSentence": true])
    expect(true, "正常设置仍可导入")
}

test("词库备份 JSON 往返：未删除为 null，时间不变") {
    let source = try makeTestDatabase()
    let card = StudyCard.fresh(wordId: 1, now: now0)
    try source.dbQueue.write { db in try card.insert(db) }
    let object = try source.vocabularySnapshot().jsonObject()
    let cards = object["studyCards"] as! [[String: Any]]
    expect(cards[0]["deleted_at"] is NSNull, "空删除日期是合法 JSON null")
    let snapshot = try VocabularySnapshot.decode(object)
    expectEqual(snapshot.studyCards.first, card, "所有卡片字段往返一致")
    let destination = try makeTestDatabase()
    let imported = try destination.importVocabularySnapshot(snapshot)
    expectEqual(imported.inserted, 1, "正常备份可导入")
    expectEqual(try destination.vocabularySnapshot().studyCards.first, card, "入库后卡片一致")
    var legacy = object
    var legacyCards = cards
    legacyCards[0]["deleted_at"] = 0
    legacy["studyCards"] = legacyCards
    expect(try VocabularySnapshot.decode(legacy).studyCards[0].deletedAt == nil, "兼容早期 0 删除标记")
}

test("熟练度本地优先，重复导入幂等，旧每日计数不覆盖新进度") {
    let database = try makeTestDatabase()
    let local = StudyCard.fresh(wordId: 1, now: now0)
    try database.dbQueue.write { db in
        try local.insert(db)
        try db.execute(sql: "INSERT INTO daily_stat VALUES (?, ?, ?, ?)", arguments: ["2026-09-11", 20, 10, now0])
    }
    var remote = StudyCard.fresh(wordId: 1, now: now0)
    remote.state = .mastered
    let newCard = StudyCard.fresh(wordId: 2, now: now0)
    let log = ReviewLog(uuid: "backup-log", cardUuid: remote.uuid, wordId: 1, rating: 3, stateBefore: "learning", reviewedAt: now0)
    let statsData = try JSONSerialization.data(withJSONObject: [["date": "2026-09-11", "new_learned": 5, "reviewed": 3, "modified_at": now0.timeIntervalSince1970]])
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
    let daily = try decoder.decode([DailyStat].self, from: statsData)
    let snapshot = VocabularySnapshot(studyCards: [remote, newCard], reviewLogs: [log], dailyStats: daily)
    let first = try database.importVocabularySnapshot(snapshot)
    expectEqual(first.inserted, 1, "只补缺失卡片")
    expectEqual(first.skipped, 1, "保留本地已重置的卡片")
    let again = try database.importVocabularySnapshot(snapshot)
    expectEqual(again.inserted, 0, "重复导入不新增")
    let result = try database.vocabularySnapshot()
    expectEqual(result.studyCards.first { $0.wordId == 1 }, local, "不以最高熟练度覆盖本地")
    expectEqual(result.reviewLogs.count, 1, "重复流水去重")
    expectEqual(result.reviewLogs.first?.cardUuid, local.uuid, "流水关联本地 UUID")
    expectEqual(result.dailyStats.first?.newLearned, 20, "旧备份不能降低新词计数")
    expectEqual(result.dailyStats.first?.reviewed, 10, "旧备份不能降低复习计数")
}

test("导入事务后半段失败时，卡片和设置均不留下半份数据") {
    let database = try makeTestDatabase()
    let suite = "DailyWord.BackupTest.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(20, forKey: "dailyNewLimit")
    try database.dbQueue.write { db in
        try db.execute(sql: "CREATE TEMP TRIGGER reject_test_log BEFORE INSERT ON review_log BEGIN SELECT RAISE(ABORT, 'test rollback'); END")
    }
    let card = StudyCard.fresh(wordId: 1, now: now0)
    let log = ReviewLog(uuid: "rollback-log", cardUuid: card.uuid, wordId: 1, rating: 3, stateBefore: "new", reviewedAt: now0)
    let snapshot = VocabularySnapshot(studyCards: [card], reviewLogs: [log], dailyStats: [])
    expectFailure("流水失败时整个导入失败") {
        _ = try database.applyBackup(snapshot: snapshot, defaultsChanges: ["dailyNewLimit": 30], defaults: defaults)
    }
    let result = try database.vocabularySnapshot()
    expect(result.studyCards.isEmpty && result.reviewLogs.isEmpty, "已插入卡片随事务回滚")
    expectEqual(defaults.integer(forKey: "dailyNewLimit"), 20, "数据库失败不改设置")
    _ = try database.applyBackup(snapshot: nil, defaultsChanges: ["dailyNewLimit": 30], defaults: defaults)
    expectEqual(defaults.integer(forKey: "dailyNewLimit"), 30, "仅导入设置仍支持")
    expectFailure("非法设置会在数据库提交前拒绝") {
        _ = try database.applyBackup(snapshot: VocabularySnapshot(studyCards: [card], reviewLogs: [], dailyStats: []),
                                     defaultsChanges: ["dailyNewLimit": -10], defaults: defaults)
    }
    expect(try database.vocabularySnapshot().studyCards.isEmpty, "校验失败没有写卡片")
}

test("坏数据不静默降级为默认值") {
    let card = StudyCard.fresh(wordId: 1, now: now0)
    let good = VocabularySnapshot(studyCards: [card], reviewLogs: [], dailyStats: [])
    var bad = try good.jsonObject()
    var cards = bad["studyCards"] as! [[String: Any]]
    cards[0]["state"] = "unknown"
    bad["studyCards"] = cards
    expectFailure("未知状态不能变成新词") { _ = try VocabularySnapshot.decode(bad) }
    expectFailure("null 数组不是空快照") { _ = try VocabularySnapshot.decode(["studyCards": NSNull()]) }
    expectFailure("重复单词不能部分写入") { try VocabularySnapshot(studyCards: [card, card], reviewLogs: [], dailyStats: []).validate() }
    let database = try makeTestDatabase()
    let missing = StudyCard.fresh(wordId: 999, now: now0)
    expectFailure("不同词库缺少词条时，整批回滚") {
        _ = try database.importVocabularySnapshot(VocabularySnapshot(studyCards: [card, missing], reviewLogs: [], dailyStats: []))
    }
    expect(try database.vocabularySnapshot().studyCards.isEmpty, "外键失败不留下前面的有效卡片")
}

// MARK: - 结果

print("")
print("断言通过 \(passed)，失败 \(failed)")
exit(failed == 0 ? 0 : 1)
