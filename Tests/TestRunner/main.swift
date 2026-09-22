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

// MARK: - 结果

print("")
print("断言通过 \(passed)，失败 \(failed)")
exit(failed == 0 ? 0 : 1)
