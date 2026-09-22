import Foundation
import GRDB

/// 成就
public struct Achievement: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let icon: String
    /// 解锁奖励经验
    public let xpReward: Int
    /// 当前进度 / 目标值
    public let progress: Int
    public let goal: Int
    /// 解锁日期（yyyy.MM.dd，未解锁为 nil）
    public let unlockedDate: String?
    /// 隐藏成就：未解锁时不在列表中展示（如魔修相关）
    public let hidden: Bool

    public var unlocked: Bool { progress >= goal }
    public var ratio: Double { goal > 0 ? min(1, Double(progress) / Double(goal)) : 0 }
    /// 神秘隐藏成就（未解锁时以 ??? 展示）
    public var isMystery: Bool { hidden && !unlocked }

    public init(id: String, title: String, detail: String, icon: String, xpReward: Int,
                progress: Int, goal: Int, unlockedDate: String? = nil, hidden: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
        self.xpReward = xpReward
        self.progress = progress
        self.goal = goal
        self.unlockedDate = unlockedDate
        self.hidden = hidden
    }
}

/// 奖励总览：经验、等级、连续打卡、成就
public struct RewardSummary: Equatable {
    public var xp: Int
    public var level: Int
    public var xpInLevel: Int
    public var xpForNextLevel: Int
    public var todayXP: Int
    public var streakDays: Int
    public var bestStreak: Int
    public var learnedCount: Int
    public var masteredCount: Int
    public var graduatedCount: Int
    /// 学习开始日期（yyyy-MM-dd，最早有学习动作的一天）
    public var firstStudyDate: String?
    public var achievements: [Achievement]

    public var levelProgress: Double {
        xpForNextLevel > 0 ? Double(xpInLevel) / Double(xpForNextLevel) : 0
    }

    /// 等级称号（最高 100 级）
    public var title: String {
        switch level {
        case 1: return "初学者"
        case 2...3: return "背词新手"
        case 4...6: return "词汇学徒"
        case 7...9: return "记忆达人"
        case 10...14: return "词海舵手"
        case 15...19: return "词海领航"
        case 20...29: return "词汇大师"
        case 30...39: return "词林高手"
        case 40...49: return "词库学者"
        case 50...59: return "词典编纂者"
        case 60...69: return "词神"
        case 70...79: return "词圣"
        case 80...89: return "词仙"
        case 90...99: return "词尊"
        default: return "词祖"
        }
    }

    public static let empty = RewardSummary(
        xp: 0, level: 1, xpInLevel: 0, xpForNextLevel: 100, todayXP: 0,
        streakDays: 0, bestStreak: 0, learnedCount: 0, masteredCount: 0, graduatedCount: 0,
        firstStudyDate: nil, achievements: []
    )
}

/// 奖励计算：全部从既有数据（复习流水 / 卡片 / 每日统计）推导，无需额外表
public enum RewardEngine {
    /// 单次复习的经验值
    /// 新学 +3、记得/太简单 +2、模糊 +1、忘记 +0（鼓励诚实自评）
    public static func xp(rating: Int, isNewWord: Bool) -> Int {
        if isNewWord { return 3 }
        switch rating {
        case 4, 3: return 2
        case 2: return 1
        default: return 0
        }
    }

    /// 每掌握一个词额外奖励
    public static let masteredBonus = 10

    /// 升到下一级所需经验（随等级递增）
    public static func xpForLevel(_ level: Int) -> Int {
        200 + (level - 1) * 120
    }

    /// 由总经验推出等级与级内进度
    public static func levelInfo(xp: Int) -> (level: Int, inLevel: Int, needed: Int) {
        var level = 1
        var remaining = xp
        while remaining >= xpForLevel(level) {
            remaining -= xpForLevel(level)
            level += 1
        }
        return (level, remaining, xpForLevel(level))
    }

    /// 修仙塔游戏成就（独立于学习成就总览，供游戏界面展示；含隐藏问号化与解锁日期补录）
    public static func towerAchievements() -> [Achievement] {
        let defaults = UserDefaults.standard
        var unlockedDates = (defaults.dictionary(forKey: "achievementUnlockedDates") as? [String: String]) ?? [:]
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy.MM.dd"
        let todayStr = dateFmt.string(from: Date())
        func ach(_ id: String, _ title: String, _ detail: String, _ icon: String,
                 _ xp: Int, _ p: Int, _ g: Int, _ hidden: Bool = false) -> Achievement {
            Achievement(id: id, title: title, detail: detail, icon: icon, xpReward: xp,
                        progress: p, goal: g, unlockedDate: unlockedDates[id], hidden: hidden)
        }
        let towerRuns = defaults.integer(forKey: "towerRuns")
        let towerWins = defaults.integer(forKey: "towerWins")
        let demonUnlocked = defaults.bool(forKey: "towerDemonUnlocked") ? 1 : 0
        let demonCollected = defaults.integer(forKey: "towerDemonCollected")
        let tombWins = defaults.integer(forKey: "towerTombWins")
        let collectedCount = defaults.stringArray(forKey: "towerCollected")?.count ?? 0
        let clearedKnight = defaults.bool(forKey: "towerCleared_knight") ? 1 : 0
        let clearedMage = defaults.bool(forKey: "towerCleared_mage") ? 1 : 0
        let clearedRogue = defaults.bool(forKey: "towerCleared_rogue") ? 1 : 0
        let clearedHealer = defaults.bool(forKey: "towerCleared_healer") ? 1 : 0
        let clearedGambler = defaults.bool(forKey: "towerCleared_gambler") ? 1 : 0
        let clearedDemon = defaults.bool(forKey: "towerCleared_demon") ? 1 : 0
        let allCleared = (clearedKnight + clearedMage + clearedRogue + clearedHealer + clearedGambler + clearedDemon) >= 6
        let pathCompleted = defaults.bool(forKey: "towerPathCompleted") ? 1 : 0
        let list: [Achievement] = [
            ach("towerFirst", "初入仙途", "初次进入修仙塔", "gamecontroller.fill", 50, towerRuns, 1),
            ach("towerWin", "首战告捷", "首次闯关成功", "flag.fill", 80, towerWins, 1),
            ach("tower10", "十战十胜", "累计闯关 10 次成功", "flag.circle.fill", 150, towerWins, 10),
            ach("win20", "二十连胜", "累计闯关 20 次成功", "flag.circle.fill", 120, towerWins, 20),
            ach("collector50", "图鉴小成", "收集 50 件物品", "square.grid.3x3.fill", 100, collectedCount, 50),
            ach("tombMaster", "墓穴探险", "首次通关地下墓穴", "moon.stars.fill", 80, tombWins, 1),
            ach("clearKnight", "剑士登顶", "以词剑士通关全部境界", "shield.lefthalf.filled", 300, clearedKnight, 1),
            ach("clearMage", "法师登顶", "以词法师通关全部境界", "wand.and.stars", 300, clearedMage, 1),
            ach("clearRogue", "行者登顶", "以词行者通关全部境界", "figure.walk.motion", 300, clearedRogue, 1),
            ach("clearHealer", "医者登顶", "以词医者通关全部境界", "cross.case.fill", 300, clearedHealer, 1),
            ach("clearGambler", "赌徒登顶", "以词赌徒通关全部境界", "die.face.5.fill", 300, clearedGambler, 1),
            ach("pathMaster", "问道巅峰", "任意角色通关全部境界", "mountain.2.fill", 500, pathCompleted, 1),
            ach("allCleared", "万法归一", "全部角色（含魔修）登顶", "crown.circle.fill", 1000, allCleared ? 1 : 0, 1, true),
            ach("demonAwaken", "魔气觉醒", "化身隐藏职业魔修", "flame.fill", 100, demonUnlocked, 1, true),
            ach("demonClear", "魔修登顶", "以魔修通关全部境界", "flame.circle.fill", 400, clearedDemon, 1, true),
            ach("demonCollector", "魔器齐集", "集齐 4 件神秘魔器", "diamond.fill", 200, demonCollected, 4, true),
            // 高级递进成就（完成基础后向更高挑战）
            ach("tower50", "五十战雄", "累计闯关 50 次成功", "flag.circle.fill", 250, towerWins, 50),
            ach("tower100", "百战宗师", "累计闯关 100 次成功", "flag.circle.fill", 400, towerWins, 100),
            ach("collector150", "图鉴大师", "收集 150 件物品", "square.grid.3x3.fill", 200, collectedCount, 150),
            ach("collector250", "全图鉴", "集齐全部 250 件物品（含魔器）", "square.grid.3x3.fill", 400, collectedCount, 250),
        ]
        // 补录新解锁成就日期
        for a in list where a.unlocked && unlockedDates[a.id] == nil {
            unlockedDates[a.id] = todayStr
        }
        defaults.set(unlockedDates, forKey: "achievementUnlockedDates")
        // 隐藏成就未解锁时以神秘问号占位
        return list.map { a -> Achievement in
            guard a.isMystery else { return a }
            return Achievement(id: a.id, title: "？？？", detail: "？？？", icon: "questionmark",
                               xpReward: a.xpReward, progress: 0, goal: a.goal,
                               unlockedDate: nil, hidden: true)
        }
    }

}

public extension AppDatabase {
    /// 汇总奖励数据
    func rewardSummary(now: Date = Date()) throws -> RewardSummary {
        try dbQueue.read { db in
            // 经验：复习流水（区分新学）+ 已掌握加成
            let rows = try Row.fetchAll(db, sql: """
                SELECT rating, state_before = 'new' AS is_new, COUNT(*) AS c
                FROM review_log GROUP BY rating, is_new
                """)
            var xp = 0
            for row in rows {
                let rating: Int = row["rating"]
                let isNew: Bool = row["is_new"]
                let count: Int = row["c"]
                xp += RewardEngine.xp(rating: rating, isNewWord: isNew) * count
            }

            let masteredCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM study_card WHERE state = 'mastered'") ?? 0
            xp += masteredCount * RewardEngine.masteredBonus

            let learnedCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM study_card") ?? 0
            // 游戏成就数据
            let towerRuns = UserDefaults.standard.integer(forKey: "towerRuns")
            let towerWins = UserDefaults.standard.integer(forKey: "towerWins")
            let demonUnlocked = UserDefaults.standard.bool(forKey: "towerDemonUnlocked") ? 1 : 0
            let demonCollected = UserDefaults.standard.integer(forKey: "towerDemonCollected")
            let tombWins = UserDefaults.standard.integer(forKey: "towerTombWins")
            let collectedCount = UserDefaults.standard.stringArray(forKey: "towerCollected")?.count ?? 0
            // 各角色通关标记（通关 16 境记录）
            let clearedKnight = UserDefaults.standard.bool(forKey: "towerCleared_knight") ? 1 : 0
            let clearedMage = UserDefaults.standard.bool(forKey: "towerCleared_mage") ? 1 : 0
            let clearedRogue = UserDefaults.standard.bool(forKey: "towerCleared_rogue") ? 1 : 0
            let clearedHealer = UserDefaults.standard.bool(forKey: "towerCleared_healer") ? 1 : 0
            let clearedGambler = UserDefaults.standard.bool(forKey: "towerCleared_gambler") ? 1 : 0
            let clearedDemon = UserDefaults.standard.bool(forKey: "towerCleared_demon") ? 1 : 0
            let allCleared = (clearedKnight + clearedMage + clearedRogue + clearedHealer + clearedGambler + clearedDemon) >= 6
            let pathCompleted = UserDefaults.standard.bool(forKey: "towerPathCompleted") ? 1 : 0

            // 毕业词数（已 suspend）
            let graduatedCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM study_card WHERE state = 'suspended'") ?? 0

            // 今日经验
            let startOfDay = Calendar.current.startOfDay(for: now)
            let todayRows = try Row.fetchAll(db, sql: """
                SELECT rating, state_before = 'new' AS is_new, COUNT(*) AS c
                FROM review_log WHERE reviewed_at >= ? GROUP BY rating, is_new
                """, arguments: [startOfDay])
            var todayXP = 0
            for row in todayRows {
                let rating: Int = row["rating"]
                let isNew: Bool = row["is_new"]
                let count: Int = row["c"]
                todayXP += RewardEngine.xp(rating: rating, isNewWord: isNew) * count
            }

            // 打卡日期（有学习动作的日子）
            let dates = try String.fetchAll(
                db, sql: "SELECT date FROM daily_stat WHERE reviewed > 0 ORDER BY date DESC")
            let streak = Self.currentStreak(dates: dates, now: now)
            let best = Self.bestStreak(dates: dates)

            let todayReviewed = try Int.fetchOne(
                db, sql: "SELECT reviewed FROM daily_stat WHERE date = ?",
                arguments: [DailyStat.localDateString(for: now)]) ?? 0

            let info = RewardEngine.levelInfo(xp: xp)

            // 成就解锁日期记录（首次解锁时落库，之后不再变化）
            let defaults = UserDefaults.standard
            var unlockedDates = (defaults.dictionary(forKey: "achievementUnlockedDates") as? [String: String]) ?? [:]
            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy.MM.dd"
            let todayStr = dateFmt.string(from: now)
            func ach(_ id: String, _ title: String, _ detail: String, _ icon: String,
                     _ xp: Int, _ p: Int, _ g: Int, _ hidden: Bool = false) -> Achievement {
                Achievement(id: id, title: title, detail: detail, icon: icon, xpReward: xp,
                            progress: p, goal: g, unlockedDate: unlockedDates[id], hidden: hidden)
            }
            let allAchievements: [Achievement] = [
                ach("first", "初来报到", "学习第 1 个单词", "flag.fill", 30, min(learnedCount, 1), 1),
                ach("hundred", "百词集", "累计学习 100 个单词", "book.fill", 60, learnedCount, 100),
                ach("fivehundred", "五百里", "累计学习 500 个单词", "books.vertical.fill", 120, learnedCount, 500),
                ach("thousand", "千词汇", "累计学习 1000 个单词", "books.vertical.fill", 200, learnedCount, 1000),
                ach("twothousand", "两千词库", "累计学习 2000 个单词", "character.book.closed.fill", 300, learnedCount, 2000),
                ach("fivethousand", "五千词海", "累计学习 5000 个单词", "text.book.closed.fill", 400, learnedCount, 5000),
                ach("tenthousand", "万词通", "累计学习 10000 个单词", "globe", 500, learnedCount, 10000),
                ach("mastered50", "掌握有道", "掌握 50 个单词", "star.fill", 60, masteredCount, 50),
                ach("mastered200", "掌握精通", "掌握 200 个单词", "star.circle.fill", 150, masteredCount, 200),
                ach("mastered500", "掌握大师", "掌握 500 个单词", "sparkles", 250, masteredCount, 500),
                ach("streak3", "三日不辍", "连续打卡 3 天", "flame.fill", 40, streak, 3),
                ach("streak7", "七日之约", "连续打卡 7 天", "flame.circle.fill", 80, streak, 7),
                ach("streak30", "月度坚持", "连续打卡 30 天", "crown.fill", 150, streak, 30),
                ach("streak100", "百日炼词", "连续打卡 100 天", "crown.circle.fill", 300, streak, 100),
                ach("today50", "今日勤奋", "单日完成 50 次复习", "bolt.fill", 50, todayReviewed, 50),
                ach("today100", "今日学霸", "单日完成 100 次复习", "bolt.circle.fill", 100, todayReviewed, 100),
                ach("level10", "十级学者", "达到 10 级", "graduationcap.fill", 80, info.level, 10),
                ach("level25", "廿五级能", "达到 25 级", "graduationcap.circle.fill", 150, info.level, 25),
                ach("level50", "半百学尊", "达到 50 级", "person.fill", 300, info.level, 50),
                ach("level100", "百级词祖", "达到 100 级", "crown.fill", 500, info.level, 100),
                ach("graduate10", "初出茅庐", "毕业 10 个单词", "checkmark.circle", 50, graduatedCount, 10),
                ach("graduate50", "小有所成", "毕业 50 个单词", "checkmark.circle.fill", 120, graduatedCount, 50),
                ach("graduate200", "学有所成", "毕业 200 个单词", "hand.thumbsup.fill", 250, graduatedCount, 200),
                ach("graduate500", "桃李满园", "毕业 500 个单词", "star.circle.fill", 400, graduatedCount, 500),
            ]
            // 隐藏成就未解锁时以神秘问号占位展示（解锁后显示真容）
            let achievements = allAchievements.map { a -> Achievement in
                guard a.isMystery else { return a }
                return Achievement(id: a.id, title: "？？？", detail: "？？？", icon: "questionmark",
                                   xpReward: a.xpReward, progress: 0, goal: a.goal,
                                   unlockedDate: nil, hidden: true)
            }

            // 补录新解锁成就的日期（首次解锁时记录）
            for a in achievements where a.unlocked && unlockedDates[a.id] == nil {
                unlockedDates[a.id] = todayStr
            }
            defaults.set(unlockedDates, forKey: "achievementUnlockedDates")

            // 学习开始日（最早有学习动作的日期，格式统一为 yyyy.MM.dd）
            let firstStudyDate = dates.last?.replacingOccurrences(of: "-", with: ".")

            // 成就解锁经验（已解锁即计入总经验；游戏成就在修仙塔面板独立展示，XP 同样计入）
            let achievementXP = achievements.filter(\.unlocked).reduce(0) { $0 + $1.xpReward }
            let gameXP = RewardEngine.towerAchievements().filter(\.unlocked).reduce(0) { $0 + $1.xpReward }
            xp += achievementXP + gameXP

            // 重新计算等级（成就经验也计入总经验）
            let finalInfo = RewardEngine.levelInfo(xp: xp)

            return RewardSummary(
                xp: xp, level: finalInfo.level, xpInLevel: finalInfo.inLevel, xpForNextLevel: finalInfo.needed,
                todayXP: todayXP, streakDays: streak, bestStreak: best,
                learnedCount: learnedCount, masteredCount: masteredCount,
                graduatedCount: graduatedCount, firstStudyDate: firstStudyDate,
                achievements: achievements
            )
        }
    }


    /// 当前连续打卡天数（今天没学也算：只要昨天有，连击仍在）
    static func currentStreak(dates: [String], now: Date = Date()) -> Int {
        let set = Set(dates)
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: now)
        // 今天没打卡则从昨天开始数（今天还有机会补）
        if !set.contains(DailyStat.localDateString(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while set.contains(DailyStat.localDateString(for: day)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// 历史最长连续天数
    static func bestStreak(dates: [String]) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let days = dates.compactMap(formatter.date(from:)).sorted()
        guard !days.isEmpty else { return 0 }

        let calendar = Calendar.current
        var best = 1
        var current = 1
        for index in 1..<days.count {
            let gap = calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day ?? 0
            if gap == 1 {
                current += 1
                best = max(best, current)
            } else if gap > 1 {
                current = 1
            }
        }
        return best
    }
}
