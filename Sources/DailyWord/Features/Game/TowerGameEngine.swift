import Foundation
import SwiftUI
import DailyWordCore

// MARK: - 游戏引擎

@MainActor
final class TowerGameEngine: ObservableObject {
    enum Phase: Equatable {
        case resumePrompt
        case realm
        case demonRealm      // 自断筋骨 1/100 走火入魔，坠入魔界
        case map
        case event(TowerEvent)
        case merchant
        case battle
        case stageClear
        case pathComplete
        case defeat
    }

    struct Question: Equatable {
        let kind: QuestionKind
        let word: Word
        let prompt: String
        let options: [String]
        let correctIndex: Int
        let spellHint: String
    }

    enum BattleMode: Equatable {
        case standard, trial, opportunity
    }

    struct Battle: Equatable {
        var node: NodeType
        var mode: BattleMode = .standard
        var enemyName: String
        var enemyIcon: String
        var enemyMaxHP: Int
        var enemyHP: Int
        var attack: Int
        var isTimed: Bool
        var timeLeft: Int
        var shieldAvailable: Bool
        var extraShieldAvailable: Bool
        var skipAvailable: Bool
        var coinReward: Int
        var ability: BossAbility = .none
        var skillsDisabled: Bool = false   // 鸡哥大招：本局职业技能失效
        var canRetreat: Bool = true        // 强制迎战/Boss 战不可撤退
        var isTomb: Bool = false           // 神秘关卡：地下墓穴
        var combo: Int = 0
        var answered: Int = 0              // 已答题数（用于 Boss 回血节律）
        var consecutiveWrong: Int = 0       // 连续答错计数（用于惩罚递增）
        var lastAnswerCorrect: Bool?
        var chosenIndex: Int?
    }

    @Published private(set) var phase: Phase = .realm
    @Published private(set) var hero: HeroClass = .knight
    @Published private(set) var difficulty: TowerDifficulty = .adventurer
    @Published private(set) var stage: TowerStage = TowerStage.all[0]
    @Published private(set) var hp = 0
    @Published private(set) var maxHP = 0
    /// 魔修反噬概率（%）：负血越深，受击灰飞烟灭概率越高（0 无风险）
    var demonBacklashChance: Int {
        guard hero == .demon else { return 0 }
        return min(60, max(0, (-hp - 5) * 3))
    }

    /// 装备耐久度 [itemId: 剩余次数]
    @Published private(set) var durability: [String: Int] = [:]
    @Published private(set) var petHP = 0
    @Published private(set) var spriteHP = 0
    @Published private(set) var petMaxHP = 0
    /// 撤退确认覆盖层是否显示
    @Published var retreatConfirming = false
    /// 技能预览：有技能的怪物进入战斗前展示说明
    @Published var showSkillPreview = false
    @Published private(set) var spriteMaxHP = 0
    @Published private(set) var floor = 1
    /// 灵泉冷却：上次灵泉出现楼层（连续节点不重复出灵泉）
    private var lastRestFloor: Int = -1
    @Published private(set) var choices: [NodeType] = []
    @Published private(set) var battle: Battle?
    @Published private(set) var question: Question?
    @Published var spellInput = ""
    @Published private(set) var toast: String?
    @Published private(set) var justClearedStageName = ""    // 刚通关的境界名（用于突破页展示）
    @Published private(set) var runInProgress = false        // 是否有进行中的修仙路（锁定角色）
    @Published private(set) var demonMode = false            // 魔化状态（魔界修炼）

    // 永久进度
    @Published private(set) var unlockedStage: Int
    @Published private(set) var pathCompleted: Bool
    @Published private(set) var winCount: Int
    @Published private(set) var coins: Int
    @Published private(set) var inventory: [OwnedItem] = []
    @Published private(set) var equipped: [String: String] = [:]   // equipKey → itemId
    @Published private(set) var collected: Set<String> = []
    @Published private(set) var merchantOffers: [GameItem] = []
    @Published private(set) var shopOffers: [GameItem] = []
    @Published private(set) var shopStamp: Date = .distantPast

    static let shopRefreshInterval: TimeInterval = 10 * 60   // 定时上新
    static let shopManualCost = 100                           // 金币刷新价（金币获取容易，100 起步）

    private let database: AppDatabase
    private var pool: [Word] = []          // 完整词库（难度升序），供干扰项使用
    private var orderedPool: [Word] = []   // 已背→未背、高频→低频排序
    /// 分类 → 词数缓存（避免每次生成地图全量扫描 1.7 万词导致卡顿）
    private var categoryCounts: [String: Int] = [:]
    /// 分类 → 词列表缓存（出题时直接取，避免全库扫描）
    private var categoryWords: [String: [Word]] = [:]
    private var usedCategoryIds: Set<String> = []
    private var recentWordIds: [Int64] = []
    private var shortcutPending = false        // 当前战斗是否为捷径（小Boss，胜后跳过一节点）
    private var timer: Timer?
    private var advanceTask: Task<Void, Never>?

    init(database: AppDatabase) {
        self.database = database
        unlockedStage = max(1, UserDefaults.standard.integer(forKey: "towerUnlockedStage"))
        pathCompleted = UserDefaults.standard.bool(forKey: "towerPathCompleted")
        runInProgress = UserDefaults.standard.dictionary(forKey: "towerSave") != nil
        winCount = UserDefaults.standard.integer(forKey: "towerWins")
        coins = UserDefaults.standard.integer(forKey: "towerCoins")
        durability = (UserDefaults.standard.dictionary(forKey: "towerDurability") as? [String: Int]) ?? [:]
        petHP = UserDefaults.standard.integer(forKey: "towerPetHP")
        spriteHP = UserDefaults.standard.integer(forKey: "towerSpriteHP")
        hero = HeroClass(rawValue: UserDefaults.standard.string(forKey: "towerHero") ?? "") ?? .knight
        collected = Set(UserDefaults.standard.stringArray(forKey: "towerCollected") ?? [])
        if let raw = UserDefaults.standard.array(forKey: "towerInventory") as? [[String: Any]] {
            inventory = raw.compactMap { dict in
                guard let id = dict["id"] as? String, let dur = dict["dur"] as? Int,
                      GameItem.item(id) != nil else { return nil }
                let acquired = (dict["at"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
                let expires = (dict["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
                return OwnedItem(id: id, durability: dur, acquiredAt: acquired, expiresAt: expires)
            }
            // 清理已过期道具
            inventory.removeAll { $0.isExpired }
        }
        if let raw = UserDefaults.standard.dictionary(forKey: "towerEquipped") as? [String: String] {
            for (key, itemId) in raw {
                guard let item = GameItem.item(itemId),
                      item.category.equipKey == key,
                      inventory.contains(where: { $0.id == itemId }) else { continue }
                equipped[key] = itemId
            }
        }
        shopStamp = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "towerShopStamp"))
        let savedIds = UserDefaults.standard.stringArray(forKey: "towerShopIds") ?? []
        shopOffers = savedIds.compactMap { GameItem.item($0) }
    }

    // MARK: - 永久数据存取

    private func persistWealth() {
        UserDefaults.standard.set(coins, forKey: "towerCoins")
        UserDefaults.standard.set(Array(collected), forKey: "towerCollected")
        UserDefaults.standard.set(inventory.map { owned -> [String: Any] in
            var dict: [String: Any] = ["id": owned.id, "dur": owned.durability,
                                       "at": owned.acquiredAt.timeIntervalSince1970]
            if let expires = owned.expiresAt { dict["exp"] = expires.timeIntervalSince1970 }
            return dict
        }, forKey: "towerInventory")
        UserDefaults.standard.set(equipped, forKey: "towerEquipped")
    }

    /// 移除已过期道具（进入游戏/层间调用）
    func purgeExpiredItems() {
        let expired = inventory.filter { $0.isExpired }
        guard !expired.isEmpty else { return }
        for owned in expired {
            if let key = owned.item?.category.equipKey, equipped[key] == owned.id {
                equipped[key] = nil
            }
        }
        inventory.removeAll { $0.isExpired }
        let names = expired.compactMap(\.item?.name).joined(separator: "、")
        toast = "⏳ \(names)的灵气消散了（道具到期）"
        persistWealth()
    }

    /// 道具限时规则：神秘商人的便宜货与秘宝掉落会带时限
    private func expiryDate(for item: GameItem, source: ItemSource) -> Date? {
        switch source {
        case .shop:
            return nil                                    // 商城购买：永久
        case .merchant:
            return item.tier >= .rare ? Date().addingTimeInterval(24 * 3600) : nil
        case .drop:
            return item.tier >= .legendary ? Date().addingTimeInterval(48 * 3600) : nil
        }
    }

    enum ItemSource { case shop, merchant, drop }

    // MARK: - 按稀有度概率抽取（高稀有度有隐藏境界门槛）

    private func rollItems(count: Int, stageGate: Int, excludeOwned: Bool) -> [GameItem] {
        var candidates = GameItem.catalog.filter { $0.tier.stageGate <= stageGate }
        if excludeOwned {
            candidates = candidates.filter { item in !inventory.contains(where: { $0.id == item.id }) }
        }
        var result: [GameItem] = []
        while result.count < count, !candidates.isEmpty {
            let total = candidates.reduce(0) { $0 + $1.tier.weight }
            var roll = Int.random(in: 0..<max(1, total))
            var picked: GameItem?
            for item in candidates {
                roll -= item.tier.weight
                if roll < 0 { picked = item; break }
            }
            guard let picked else { break }
            result.append(picked)
            candidates.removeAll { $0.id == picked.id }
        }
        return result
    }

    // MARK: - 云间商城（定时上新 + 金币刷新）

    var shopSecondsLeft: Int {
        max(0, Int(Self.shopRefreshInterval - Date().timeIntervalSince(shopStamp)))
    }

    func refreshShopIfNeeded() {
        if shopOffers.isEmpty || Date().timeIntervalSince(shopStamp) >= Self.shopRefreshInterval {
            regenerateShop()
        }
    }

    /// 金币立即刷新
    func paidRefreshShop() {
        guard coins >= Self.shopManualCost else { return }
        coins -= Self.shopManualCost
        regenerateShop()
        persistWealth()
    }

    private func regenerateShop() {
        shopOffers = rollItems(count: 8, stageGate: unlockedStage, excludeOwned: true)
        shopStamp = Date()
        UserDefaults.standard.set(shopStamp.timeIntervalSince1970, forKey: "towerShopStamp")
        UserDefaults.standard.set(shopOffers.map(\.id), forKey: "towerShopIds")
    }

    func buy(_ item: GameItem, discounted: Bool) {
        let price = discounted ? Int(Double(item.price) * 0.8) : item.price
        guard coins >= price, !inventory.contains(where: { $0.id == item.id }) else { return }
        coins -= price
        let source: ItemSource = discounted ? .merchant : .shop
        inventory.append(OwnedItem(id: item.id, durability: item.maxDurability,
                                   acquiredAt: Date(),
                                   expiresAt: expiryDate(for: item, source: source)))
        collected.insert(item.id)
        toast = "🛒 购入【\(item.name)】"
        persistWealth()
        merchantOffers.removeAll { $0.id == item.id }
        shopOffers.removeAll { $0.id == item.id }
        UserDefaults.standard.set(shopOffers.map(\.id), forKey: "towerShopIds")
    }

    func leaveMerchant() {
        nextFloor()
    }

    // MARK: - 装备/物品

    func usable(_ item: GameItem) -> Bool {
        item.restrictedTo == nil || item.restrictedTo == hero
    }

    func equip(_ owned: OwnedItem) {
        guard let item = owned.item, let key = item.category.equipKey else { return }
        equipped[key] = owned.id
        persistWealth()
    }

    func unequip(_ key: String) {
        equipped[key] = nil
        persistWealth()
    }

    func isEquipped(_ item: GameItem) -> Bool {
        guard let key = item.category.equipKey else { return false }
        return equipped[key] == item.id
    }

    func useConsumable(_ owned: OwnedItem) {
        guard let item = owned.item, item.category == .potion else { return }
        if item.healAmount > 0 {
            guard maxHP > 0 else { return }
            hp = item.healAmount >= 99 ? maxHP : min(maxHP, hp + item.healAmount)
            toast = "🍵 服下\(item.name)，生命 \(hp)/\(maxHP)"
        } else if item.timeBonus > 0 {
            guard var battle, battle.isTimed else { return }
            battle.timeLeft += item.timeBonus
            self.battle = battle
            toast = "⏳ \(item.name)生效，+\(item.timeBonus) 秒"
        } else { return }
        inventory.removeAll { $0.id == owned.id }
        persistWealth()
    }

    private var equipEffects: (damage: Int, defense: Int, extraShield: Bool, coin: Int, time: Int, regen: Int) {
        var result = (damage: 0, defense: 0, extraShield: false, coin: 0, time: 0, regen: 0)
        for (_, itemId) in equipped {
            guard let owned = inventory.first(where: { $0.id == itemId }),
                  let item = owned.item, usable(item) else { continue }
            result.damage += item.damageBonus
            result.defense += item.defenseBonus
            result.extraShield = result.extraShield || item.extraShield
            result.coin += item.coinBonus
            result.time += item.timeBonus
            result.regen += item.regenPerWin
        }
        return result
    }

    private func wearEquipment() {
        var broken: [String] = []
        for (key, itemId) in equipped {
            guard let index = inventory.firstIndex(where: { $0.id == itemId }),
                  let item = inventory[index].item, item.maxDurability < 99 else { continue }
            inventory[index].durability -= 1
            if inventory[index].durability <= 0 {
                broken.append(item.name)
                inventory.remove(at: index)
                equipped[key] = nil
            }
        }
        if !broken.isEmpty {
            toast = "💔 \(broken.joined(separator: "、"))耐久耗尽，碎裂了"
        }
        persistWealth()
    }

    private func gainItem(_ item: GameItem) {
        collected.insert(item.id)
        if inventory.contains(where: { $0.id == item.id }) {
            coins += item.price / 2
            toast = "🎁 重复的\(item.name)折算为 \(item.price / 2) 金币"
        } else {
            inventory.append(OwnedItem(id: item.id, durability: item.maxDurability,
                                       acquiredAt: Date(),
                                       expiresAt: expiryDate(for: item, source: .drop)))
            toast = "🎁 获得\(item.tier.label)【\(item.name)】！"
        }
        persistWealth()
    }

    // MARK: - 流程

    func openGame() {
        stopTimer()
        advanceTask?.cancel()
        toast = nil
        purgeExpiredItems()
        refreshDifficulty()
        refreshShopIfNeeded()
        // 保留 battle/question：窗口关闭再打开时回到原战斗（限时战斗由 resumeBattleTimer 恢复计时）
        if battle != nil {
            phase = .battle
        } else {
            phase = .realm   // 回首页“闯关之路”；有存档时仙道页提供继续/自断筋骨
        }
    }

    func backToRealm() {
        stopTimer()
        advanceTask?.cancel()
        battle = nil
        question = nil
        refreshShopIfNeeded()
        phase = .realm
    }

    func abandonRun() {
        clearSave()
        // 魔修放弃修仙路：身份一并结束，回到原始选人界面
        if hero == .demon {
            endDemon()
        }
        backToRealm()
    }

    /// 在仙道界面切换人物（持久化）
    /// 卸下当前角色不可用的限定装备（换角色/死亡重选后调用）
    func purgeInvalidEquipment() {
        var changed = false
        for (slot, itemId) in equipped {
            guard let item = GameItem.catalog.first(where: { $0.id == itemId }),
                  item.restrictedTo != nil, item.restrictedTo != hero else { continue }
            equipped.removeValue(forKey: slot)
            changed = true
        }
        if changed {
            persistWealth()
            toast = "⚠️ 已自动卸下当前角色无法使用的限定装备"
        }
    }

    func selectHero(_ heroClass: HeroClass) {
        hero = heroClass
        UserDefaults.standard.set(heroClass.rawValue, forKey: "towerHero")
        purgeInvalidEquipment()
    }

    /// 是否允许更换装备：仙道页/地图页（未进战斗）可；战斗/事件/商人类禁止；技能预览时允许
    var canChangeEquipment: Bool {
        switch phase {
        case .battle: return showSkillPreview   // 战斗中禁止，但技能预览时可
        case .event, .merchant: return false
        default: return true                    // 仙道页、地图、结算等可换装
        }
    }

    /// 隐藏职业解锁状态：通关全部 16 境（或全解锁调试标记）
    var demonUnlocked: Bool {
        UserDefaults.standard.bool(forKey: "towerDemonUnlocked")
    }

    /// 魔器是否揭示真实内容：魔修身份或已拥有（获得时即可见真名）
    func isDemonItemRevealed(_ item: GameItem) -> Bool {
        hero == .demon || collected.contains(item.id)
    }

    /// 掉落一件魔修装备（入背包 + 图鉴点亮）；获得时揭示真实内容
    func dropDemonItem() {
        let demonItems = GameItem.catalog.filter { $0.tier == .demon }
        guard let item = demonItems.randomElement() else { return }
        if !inventory.contains(where: { $0.id == item.id }) {
            inventory.append(OwnedItem(id: item.id, durability: item.maxDurability, acquiredAt: Date()))
        }
        collected.insert(item.id)
        persistWealth()
        UserDefaults.standard.set(
            GameItem.catalog.filter { $0.tier == .demon && collected.contains($0.id) }.count,
            forKey: "towerDemonCollected")
        toast = "😈 获得魔器【\(item.name)】：\(item.effectDesc)"
    }

    /// 转化魔修：隐藏职业以神秘方式现身（不死不灭之体）
    func becomeDemon(withItem: Bool) {
        hero = .demon
        maxHP = 0          // 魔修生命恒为 0 以下
        hp = 0
        UserDefaults.standard.set(true, forKey: "towerDemonUnlocked")
        UserDefaults.standard.set(hero.rawValue, forKey: "towerHero")
        persistWealth()
        if withItem {
            dropDemonItem()
            toast = "😈 你被魔气侵蚀，化身魔修！并获得一件神秘魔器！"
        } else {
            toast = "😈 黑暗中，魔修的意志在你体内苏醒……"
        }
    }

    /// 窗口关闭：暂停战斗计时并保存剩余时间
    func pauseBattleTimer() {
        guard phase == .battle, let battle, battle.isTimed else { return }
        stopTimer()
        UserDefaults.standard.set(battle.timeLeft, forKey: "towerBattleTimeLeft")
    }

    /// 窗口打开：恢复战斗计时
    func resumeBattleTimer() {
        guard phase == .battle, var battle, battle.isTimed else { return }
        let saved = UserDefaults.standard.integer(forKey: "towerBattleTimeLeft")
        if saved > 0, saved < battle.timeLeft { battle.timeLeft = saved }
        self.battle = battle
        UserDefaults.standard.removeObject(forKey: "towerBattleTimeLeft")
        startTimer()
    }

    private func refreshDifficulty() {
        let items = (try? database.allItems()) ?? []
        let learned = items.filter { $0.card != nil }.count
        let mastered = items.filter { $0.card?.state == .mastered }.count
        difficulty = TowerDifficulty.evaluate(learned: learned, mastered: mastered)
    }

    /// 启动预热：后台构建好的词库直接注入（避免进入游戏时卡顿）
    func injectPool(_ words: [Word], counts: [String: Int], categoryWords: [String: [Word]]) {
        orderedPool = words
        pool = words
        categoryCounts = counts
        self.categoryWords = categoryWords
    }

    /// 一次性全解锁：全部物品入背包、图鉴集齐、切换隐藏职业（魔修）
    func grantAllItemsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "towerAllItemsGranted") else { return }
        UserDefaults.standard.set(true, forKey: "towerAllItemsGranted")
        var granted = 0
        for item in GameItem.catalog {
            let owned = OwnedItem(id: item.id, durability: item.maxDurability, acquiredAt: Date())
            if inventory.contains(where: { $0.id == item.id }) { continue }
            inventory.append(owned)
            collected.insert(item.id)
            granted += 1
        }
        hero = .demon
        maxHP = 0          // 魔修生命恒为 0 以下
        hp = 0
        UserDefaults.standard.set(true, forKey: "towerDemonUnlocked")
        UserDefaults.standard.set(hero.rawValue, forKey: "towerHero")
        persistWealth()
        UserDefaults.standard.set(hero.rawValue, forKey: "towerHero")
        NSLog("修仙塔全解锁：\(granted) 件物品，隐藏职业魔修")
    }

    private func loadPool() {
        // 已预热（启动后台注入）则直接使用，避免点击时卡顿
        if !orderedPool.isEmpty { return }
        let items = (try? database.allItems()) ?? []
        // 难度升序：背过的词在前（熟悉→简单），再未背的；同组内高频（常见）在前
        // → 新用户也能玩：从基础四级高频词开始；老用户先考背过的
        let sorted = items.sorted { a, b in
            let sa = a.card != nil ? 0 : 1
            let sb = b.card != nil ? 0 : 1
            if sa != sb { return sa < sb }
            let fa = a.word.frequency ?? Int.max
            let fb = b.word.frequency ?? Int.max
            return fa < fb
        }
        orderedPool = sorted.map(\.word)
        pool = orderedPool
        // 一次性构建分类缓存（生成地图/出题直接用，避免全量扫描）
        var counts: [String: Int] = [:]
        var words: [String: [Word]] = [:]
        for word in orderedPool {
            for category in WordCategory.all where category.matches(word) {
                counts[category.id, default: 0] += 1
                words[category.id, default: []].append(word)
            }
        }
        categoryCounts = counts
        categoryWords = words
    }

    /// 全程进度 0..1（跨整条修仙路累计楼层），驱动词库难度滑动窗口
    private var overallProgress: Double {
        let done = TowerStage.all.prefix(stage.index - 1).reduce(0) { $0 + $1.floors }
        let total = TowerStage.all.reduce(0) { $0 + $1.floors }
        guard total > 0 else { return 0 }
        return min(1, Double(done + floor) / Double(total))
    }

    /// 当前难度窗口：越往后越偏向“未背/低频”的难词
    private func difficultyWindow() -> [Word] {
        let n = orderedPool.count
        guard n > 0 else { return [] }
        let span = max(80, n / 5)
        if n <= span { return orderedPool }
        let center = Int(overallProgress * Double(n - 1))
        let lower = max(0, min(center - span / 2, n - span))
        return Array(orderedPool[lower..<(lower + span)])
    }

    /// 开启一整条修仙路（从凡人起，全程一个角色、生命共用）
    func start(as heroClass: HeroClass) {
        beginRun(as: heroClass, demonic: false)
    }

    private func beginRun(as heroClass: HeroClass, demonic: Bool) {
        clearSave()                    // 新一轮闯关之路：彻底重开（清残留存档）
        loadPool()
        guard pool.count >= 8 else { return }
        hero = heroClass
        purgeInvalidEquipment()
        demonMode = demonic
        stage = TowerStage.all[0]
        if heroClass == .demon {
            maxHP = 0          // 魔修：生命恒为 0 以下
            hp = 0
        } else {
            maxHP = heroClass.maxHP
            hp = maxHP
        }
        if hero == .demon {
            toast = "😈 不死不灭：生命恒为 0 以下；但魔气越深越危险——负血加深，受击灰飞烟灭的概率越高！"
        }
        floor = 1
        usedCategoryIds = []
        recentWordIds = []
        saveRun()
        makeChoices()
        phase = .map
    }

    // MARK: - 存档

    private var hasSave: Bool {
        UserDefaults.standard.dictionary(forKey: "towerSave") != nil
    }

    var savedFloorDescription: String {
        guard let save = UserDefaults.standard.dictionary(forKey: "towerSave"),
              let heroRaw = save["hero"] as? String,
              let heroClass = HeroClass(rawValue: heroRaw),
              let stageIndex = save["stage"] as? Int,
              let savedFloor = save["floor"] as? Int,
              let savedHP = save["hp"] as? Int,
              let savedStage = TowerStage.all.first(where: { $0.index == stageIndex }) else { return "" }
        return "\(savedStage.name) · \(heroClass.name) · 第 \(savedFloor) 层 · ❤️ \(savedHP)"
    }

    /// 魔修死亡：身份结束，回到最初的选择界面（道体重归凡尘）
    func endDemon() {
        hero = .knight
        maxHP = hero.maxHP
        hp = maxHP
        UserDefaults.standard.set(hero.rawValue, forKey: "towerHero")
        purgeInvalidEquipment()        // 魔器为魔修限定：身份结束自动卸下
        toast = "😵 魔修灰飞烟灭，道体重归凡尘……"
    }

    /// 一次性切到魔修身份（用户要求直接切换；标记防止重复）
    func ensureDemon() {
        // v1.2 强制切回一次（修复身份持久化后重新生效）
        if !UserDefaults.standard.bool(forKey: "towerDemonAppliedV3") {
            UserDefaults.standard.set(true, forKey: "towerDemonAppliedV3")
            becomeDemon(withItem: false)
            return
        }
        guard !UserDefaults.standard.bool(forKey: "towerDemonApplied") else { return }
        UserDefaults.standard.set(true, forKey: "towerDemonApplied")
        becomeDemon(withItem: true)
    }

    /// 立即保存当前闯关进度（供关闭窗口/三击关闭时调用）
    func saveProgressNow() {
        saveRun()
    }

    private func saveRun() {
        UserDefaults.standard.set(
            ["hero": hero.rawValue, "hp": hp, "maxHP": maxHP,
             "floor": floor, "stage": stage.index, "usedCats": Array(usedCategoryIds),
             "demon": demonMode],
            forKey: "towerSave")
        runInProgress = true
    }

    private func clearSave() {
        UserDefaults.standard.removeObject(forKey: "towerSave")
        runInProgress = false
    }

    /// 自断筋骨·重踏修仙路：放弃当前进度，可重选角色；背包/穿戴/图鉴/金币均保留
    /// —— 服 1/100 概率走火入魔，坠入魔界
    func selfCripple() {
        clearSave()
        // 自断筋骨：1/2 魔修觉醒（临时测试概率）；未觉醒则直接回到原始选人界面
        if Int.random(in: 0..<2) == 0 {
            becomeDemon(withItem: false)
            demonMode = true
            phase = .demonRealm
        } else {
            // 未觉醒：道体重归凡尘（若曾是魔修），直接回到选人重来界面
            if hero == .demon {
                endDemon()
            }
            demonMode = false
            phase = .realm
        }
    }

    /// 坠入魔界：以魔入道，开启魔化之旅
    func enterDemonRealm() {
        beginRun(as: hero, demonic: true)
    }

    /// 抵住心魔，回到仙道
    func resistDemon() {
        demonMode = false
        // 抵住心魔：拒绝魔修身份，直接回到最初的选择界面
        if hero == .demon {
            endDemon()
        }
        phase = .realm
        // 异步强制刷新：避免主题/背景切换竞态导致文字不可见
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func continueRun() {
        guard let save = UserDefaults.standard.dictionary(forKey: "towerSave"),
              let heroRaw = save["hero"] as? String,
              let heroClass = HeroClass(rawValue: heroRaw),
              let stageIndex = save["stage"] as? Int,
              let savedFloor = save["floor"] as? Int,
              let savedHP = save["hp"] as? Int,
              let savedMaxHP = save["maxHP"] as? Int,
              let savedStage = TowerStage.all.first(where: { $0.index == stageIndex }) else {
            phase = .realm
            return
        }
        loadPool()
        guard pool.count >= 8 else { return }
        hero = heroClass
        demonMode = (save["demon"] as? Bool) ?? false
        stage = savedStage
        maxHP = savedMaxHP
        hp = min(savedHP, savedMaxHP)
        floor = min(savedFloor, savedStage.floors)
        usedCategoryIds = Set(save["usedCats"] as? [String] ?? [])
        recentWordIds = []
        makeChoices()
        phase = .map
    }

    func abandonSave() {
        clearSave()
        phase = .realm
    }

    // MARK: - 分支生成

    private var availableCategories: [WordCategory] {
        WordCategory.all.filter { category in
            !usedCategoryIds.contains(category.id)
                && (categoryCounts[category.id] ?? 0) >= 8
        }
    }

    private var availableKinds: [QuestionKind] {
        var kinds: [QuestionKind] = [.enToCn, .cnToEn, .spell]
        if pool.filter({ ($0.definitionEn ?? "").count > 10 }).count >= 12 {
            kinds.append(.engDef)
        }
        return kinds
    }

    private func randomKind() -> QuestionKind {
        availableKinds.randomElement() ?? .enToCn
    }

    private func makeChoices() {
        toast = nil
        if floor >= stage.floors {
            choices = [.boss]
            return
        }
        // 岔路：从第 2 节点起可能出现“捷径 vs 绕行”（距边界还有至少 2 步时）
        let canBranch = floor >= 2 && floor + 1 < stage.floors
        if canBranch && Int.random(in: 0..<100) < 55 {
            var routes: [NodeType] = [
                .elite(kind: randomKind()),                       // 捷径：短而难（小Boss）
                .battle(category: nil, kind: randomKind())         // 绕行：长而易
            ]
            if let category = availableCategories.shuffled().first {
                routes.append(.battle(category: category, kind: randomKind()))
            }
            if (hp <= maxHP / 2 || (hero == .demon && hp <= -3)), floor != lastRestFloor {
                // 灵泉概率：血越低越高，封顶 10%
                let restChance = hero == .demon
                    ? min(10, max(2, -hp * 2))
                    : min(10, max(2, Int((1 - Double(hp) / Double(max(1, maxHP))) * 12)))
                if Int.random(in: 0..<100) < restChance { routes.append(.rest) }
            }
            var unique: [NodeType] = []
            for node in routes where !unique.contains(node) { unique.append(node) }
            choices = Array(unique.prefix(3))
            return
        }

        var candidates: [NodeType] = [.battle(category: nil, kind: randomKind())]
        for category in availableCategories.shuffled().prefix(2) {
            candidates.append(.battle(category: category, kind: randomKind()))
        }
        if floor >= 3 { candidates.append(.elite(kind: randomKind())) }
        if floor >= 2 { candidates.append(.timedTrial(kind: randomKind())) }
        if (hp <= maxHP / 2 || (hero == .demon && hp <= -3)), floor != lastRestFloor {
            let restChance = hero == .demon
                ? min(10, max(2, -hp * 2))
                : min(10, max(2, Int((1 - Double(hp) / Double(max(1, maxHP))) * 12)))
            if Int.random(in: 0..<100) < restChance { candidates.append(.rest) }
        }
        if floor >= 2 && Int.random(in: 0..<100) < 30 { candidates.append(.merchant) }

        var unique: [NodeType] = []
        for node in candidates.shuffled() where !unique.contains(node) {
            unique.append(node)
        }
        choices = Array(unique.prefix(3))
    }

    func choose(_ node: NodeType) {
        guard phase == .map else { return }
        switch node {
        case .rest:
            hp = min(maxHP, hp + 15)
            lastRestFloor = floor
            toast = hero == .demon
                ? "🔥 魔气滋养，回复 15 点（当前 \(hp)）"
                : "💧 灵泉涤体，恢复 15 点生命（\(hp)/\(maxHP)）"
            // 灵泉不消耗节点楼层：回血后继续在当前楼层选下一个节点
            saveRun()
            makeChoices()
            phase = .map
            return
            nextFloor()
        case .merchant:
            merchantOffers = rollItems(count: 3, stageGate: stage.index, excludeOwned: true)
            phase = .merchant
        case .battle(let category, _):
            if let category { usedCategoryIds.insert(category.id) }
            shortcutPending = false
            enterBattle(node, mode: .standard)
        case .elite:
            // 捷径：小 Boss 难，但胜利后直接跳过一个节点（路短）
            shortcutPending = true
            enterBattle(node, mode: .standard)
        default:
            shortcutPending = false
            enterBattle(node, mode: .standard)
        }
    }

    private func nextFloor() {
        floor += 1
        saveRun()
        if floor < stage.floors, floor > 1, Int.random(in: 0..<100) < 22 {
            let event: TowerEvent = [.forced, .opportunity, .trial].randomElement()!
            phase = .event(event)
            return
        }
        makeChoices()
        phase = .map
    }

    // MARK: - 突发事件

    func acceptEvent(_ event: TowerEvent) {
        switch event {
        case .forced:
            enterBattle(.battle(category: nil, kind: randomKind()), mode: .standard, eventBoost: true, canRetreat: false)
        case .opportunity:
            enterBattle(.elite(kind: randomKind()), mode: .opportunity)
        case .trial:
            enterBattle(.timedTrial(kind: randomKind()), mode: .trial)
        }
    }

    func declineEvent(_ event: TowerEvent) {
        guard event != .forced else { return }
        makeChoices()
        phase = .map
        toast = "你绕开了\(event == .opportunity ? "秘宝洞窟" : "灵光")，继续赶路"
    }

    // MARK: - 战斗

    private func enterBattle(_ node: NodeType, mode: BattleMode, eventBoost: Bool = false, canRetreat: Bool = true) {
        let power = stage.index                    // 1..16，随境界线性成长
        let floorBonus = (floor - 1) / 2          // 境内楼层递增
        var enemyName: String
        var enemyIcon: String
        var enemyHP: Int
        var attack: Int
        var timed = false
        var timeLimit = 0
        var reward = 0
        var ability: BossAbility = .none

        switch node {
        case .elite:
            enemyName = mode == .opportunity ? "秘宝守卫" : stage.eliteName
            enemyIcon = "flame.fill"
            enemyHP = 6 + power * 3 / 2 + floorBonus
            attack = 3 + power / 3
            reward = 6 + power * 2
        case .timedTrial:
            enemyName = mode == .trial ? "灵光幻影" : "秘境守卫"
            enemyIcon = "timer"
            enemyHP = mode == .trial ? (3 + power / 3) : 5 + power
            attack = 2 + power / 2          // 小怪攻击提速
            timed = true
            timeLimit = mode == .trial ? 20 : 45
            reward = mode == .trial ? 10 : 12 + power * 2
        case .boss:
            enemyName = stage.bossName
            enemyIcon = stage.bossIcon
            enemyHP = stage.bossHP
            attack = 4 + power / 2
            timed = stage.bossTime > 0        // 非所有 Boss 都限时（bossTime 0 = 不限时持久战）
            timeLimit = max(30, stage.bossTime + (hero == .mage ? 15 : 0) + difficulty.bossTimeMod)
            reward = 15 + power * 5
            ability = stage.bossAbility
        case .battle(let category, _):
            let minion = stage.minions.randomElement()!
            enemyName = minion.name
            enemyIcon = minion.icon
            enemyHP = (category != nil ? 3 : 4) + power + floorBonus
            attack = 2 + power / 2          // 小怪攻击提速
            reward = 2 + power
        default:
            return
        }

        // 神秘关卡：地下墓穴（普通职业 1/1000；魔修与墓穴契合，感知概率 1/200；非 Boss 战）
        let tombRoll = hero == .demon ? 200 : 1000
        let inTomb = node != .boss && Int.random(in: 0..<tombRoll) == 0
        if inTomb {
            // 地下墓穴：神秘关卡的难度与奖励（守卫更强）
            enemyHP = Int(Double(enemyHP) * 1.6)
            attack += 3
            reward *= 2
        }
        if eventBoost {
            enemyHP += 1
            reward += 5
        }
        if mode == .opportunity { reward = 14 + stage.index * 3 }

        enemyHP = max(3, enemyHP + difficulty.enemyHPMod)
        attack = max(2, attack + difficulty.attackMod)
        if timed { timeLimit += equipEffects.time }

        let disabled = ability == .disableSkill
        let retreatAllowed = canRetreat && node != .boss
        // 魔修视角：敌人多为正道修士，偶尔遭遇同族魔道（15% 保持原名）
        if hero == .demon, !inTomb, Int.random(in: 0..<100) >= 15 {
            switch node {
            case .boss:
                enemyName = Self.demonEnemyBosses[stage.index % Self.demonEnemyBosses.count]
            case .elite:
                enemyName = Self.demonEnemyElites.randomElement() ?? enemyName
            default:
                enemyName = Self.demonEnemyMinions.randomElement() ?? enemyName
            }
        }
        battle = Battle(
            node: node,
            mode: mode,
            enemyName: inTomb ? "墓穴守卫" : enemyName,
            enemyIcon: inTomb ? "figure.martial.arts" : enemyIcon,
            enemyMaxHP: enemyHP,
            enemyHP: enemyHP,
            attack: attack,
            isTimed: timed,
            timeLeft: timed ? max(15, timeLimit) : 0,
            shieldAvailable: hero == .knight && !disabled,
            extraShieldAvailable: equipEffects.extraShield,
            skipAvailable: hero == .rogue && !disabled,
            coinReward: reward,
            ability: ability,
            skillsDisabled: disabled,
            canRetreat: retreatAllowed,
            isTomb: inTomb
        )
        spellInput = ""
        phase = .battle
        if ability != .none { showSkillPreview = true }   // 有技能怪物进入战斗前弹出预览
        if inTomb { toast = "⚰️ 你误入神秘关卡——地下墓穴！" }
        if disabled { toast = "🏀 \(enemyName)：唱！跳！rap！篮球！——你的技能被封印了！" }
        nextQuestion()
        if timed { startTimer() }
    }

    private func questionPool(for node: NodeType) -> [Word] {
        let window = difficultyWindow()
        let base = window.isEmpty ? pool : window
        if case .battle(let category?, _) = node {
            // 优先窗口内同类（用 Set 快速过滤缓存）
            let windowSet = Set(window.map(\.id))
            let catWords = categoryWords[category.id] ?? []
            let filtered = catWords.filter { windowSet.contains($0.id) }
            if filtered.count >= 6 { return filtered }
            // 窗口内不足，直接取缓存的全库同类（无扫描）
            if catWords.count >= 6 { return catWords }
        }
        return base
    }

    private func nodeKind(_ node: NodeType) -> QuestionKind {
        switch node {
        case .battle(_, let kind): return kind
        case .elite(let kind): return kind
        case .timedTrial(let kind): return kind
        default: return .enToCn
        }
    }

    private func nextQuestion() {
        guard let battle else { return }
        let kind = nodeKind(battle.node)
        var candidates = questionPool(for: battle.node)
        if kind == .engDef {
            candidates = candidates.filter { ($0.definitionEn ?? "").count > 10 }
            if candidates.count < 8 { candidates = questionPool(for: battle.node) }
        }
        let fresh = candidates.filter { word in !recentWordIds.contains(word.id) }
        guard let word = (fresh.isEmpty ? candidates : fresh).randomElement() else { return }
        recentWordIds.append(word.id)
        if recentWordIds.count > 10 { recentWordIds.removeFirst() }

        let cnDef = Self.firstLine(word.definitionCn)
        switch kind {
        case .enToCn:
            var options = Array(Set(pool.map { Self.firstLine($0.definitionCn) }.filter { $0 != cnDef })
                .shuffled().prefix(3))
            let index = Int.random(in: 0...options.count)
            options.insert(cnDef, at: index)
            question = Question(kind: kind, word: word, prompt: word.headword,
                                options: options, correctIndex: index, spellHint: "")
        case .cnToEn:
            var options = Array(Set(pool.map(\.headword).filter { $0 != word.headword })
                .shuffled().prefix(3))
            let index = Int.random(in: 0...options.count)
            options.insert(word.headword, at: index)
            question = Question(kind: kind, word: word, prompt: cnDef,
                                options: options, correctIndex: index, spellHint: "")
        case .spell:
            let first = word.headword.prefix(1)
            question = Question(kind: kind, word: word, prompt: cnDef, options: [], correctIndex: 0,
                                spellHint: "提示：首字母 \(first) · 共 \(word.headword.count) 个字母")
        case .engDef:
            let engDef = Self.firstLine(word.definitionEn ?? "")
            var options = Array(Set(pool.map(\.headword).filter { $0 != word.headword })
                .shuffled().prefix(3))
            let index = Int.random(in: 0...options.count)
            options.insert(word.headword, at: index)
            question = Question(kind: kind, word: word, prompt: engDef,
                                options: options, correctIndex: index, spellHint: "")
        }
        spellInput = ""
        self.battle?.lastAnswerCorrect = nil
        self.battle?.chosenIndex = nil
    }

    static func firstLine(_ definition: String) -> String {
        definition.split(separator: "\n").first.map(String.init) ?? definition
    }

    func answer(_ index: Int) {
        guard let question, !question.options.isEmpty else { return }
        resolveAnswer(correct: index == question.correctIndex, chosen: index)
    }

    func submitSpell() {
        guard let question, question.kind == .spell else { return }
        let text = spellInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        resolveAnswer(correct: text.compare(question.word.headword, options: .caseInsensitive) == .orderedSame,
                      chosen: nil)
    }

    private func resolveAnswer(correct: Bool, chosen: Int?) {
        guard phase == .battle, var battle, let question,
              battle.lastAnswerCorrect == nil else { return }
        battle.chosenIndex = chosen
        battle.answered += 1
        let skillOn = !battle.skillsDisabled       // 鸡哥封印时为 false

        if correct {
            battle.combo += 1
            var damage = (skillOn && hero == .gambler) ? 2 : 1
            if skillOn && hero == .mage && battle.combo >= 3 { damage += 1 }
            damage += equipEffects.damage
            if hero == .demon { damage += max(0, -hp) / 3 }   // 不死不灭：负血越深攻击越狂
            if demonMode { damage += 2 }               // 魔功：命中伤害 +2
            var dealt = damage
            if battle.ability == .dodge && Int.random(in: 0..<10) < 3 {
                dealt = 0                                // 幻影闪避：30% 免疫
                toast = "💨 \(battle.enemyName)身影一闪，闪避了这次攻击！"
            }
            if battle.ability == .ironwall, battle.answered > 0, battle.answered % 4 == 0 {
                dealt = 0                                // 铁壁：每 4 题免疫一次
                toast = "🛡️ \(battle.enemyName)铁壁一震，弹开了攻击！"
            }
            battle.enemyHP = max(0, battle.enemyHP - dealt)
            battle.consecutiveWrong = 0
            battle.lastAnswerCorrect = true
            // 毒雾：答对后侵蚀玩家 1 血
            if battle.ability == .venom && Int.random(in: 0..<100) < 40 {
                hp = hero == .demon ? hp - 1 : max(1, hp - 1)
                toast = "☠️ 毒雾侵蚀，-1 血！"
            }
            if skillOn && hero == .healer && battle.combo % 2 == 0 {
                hp = min(maxHP, hp + 1)
            }
            if hero == .demon {
                hp = min(0, hp + 1)          // 魔气回涌：答对回升 1 点（至 0）
            }
        } else {
            battle.combo = 0
                battle.consecutiveWrong += 1
            battle.lastAnswerCorrect = false
            if battle.mode == .trial {
                // 突发挑战：答错无惩罚
            } else if battle.shieldAvailable {
                battle.shieldAvailable = false
            } else if battle.extraShieldAvailable {
                battle.extraShieldAvailable = false
                toast = "🛡 护体宝物替你挡下了这一击"
            } else {
                var hit = max(1, battle.attack + (skillOn && hero == .gambler ? 1 : 0) - equipEffects.defense)
                let stagePenalty = max(0, (stage.index - 4) / 5) + (stage.index >= 14 ? 1 : 0)
                hit += stagePenalty
                if battle.consecutiveWrong >= 3 { hit += battle.consecutiveWrong - 2 }
                if battle.ability == .berserk { hit += battle.answered / 3 }   // 狂暴：每 3 题 +1 攻
                if battle.ability == .doubleHit { hit *= 2 }   // 马保国：闪电五连鞭
                if demonMode { hit += 1 }                       // 魔气反噬：答错多掉 1 血
                hp = hero == .demon ? hp - hit : max(0, hp - hit)
                if battle.ability == .lifesteal, battle.enemyHP > 0 {
                    battle.enemyHP = min(battle.enemyMaxHP, battle.enemyHP + 1)   // 吸血：以战养战
                }
                // 魔气反噬：魔修负血越深，受击灰飞烟灭概率越高（随机，非固定死亡线）
                if hero == .demon, demonBacklashChance > 0,
                   Int.random(in: 0..<100) < demonBacklashChance {
                    hp = -99
                    toast = "💀 魔气反噬！魔体崩解，灰飞烟灭……（反噬概率 \(demonBacklashChance)%）"
                    finishRun(victory: false)
                    return
                }
            }
            // 时间吞噬：答错额外扣时间
            if battle.ability == .timeDrain && battle.isTimed {
                battle.timeLeft = max(1, battle.timeLeft - 5)
            }
        }

        // Boss 不死身法：每答 3 题回 1 血
        if battle.ability == .regen && battle.enemyHP > 0 && battle.answered % 3 == 0 {
            battle.enemyHP = min(battle.enemyMaxHP, battle.enemyHP + 1)
        }
        self.battle = battle
        SpeechService.shared.speak(question.word.headword)

        if hp <= 0, hero != .demon {
            finishRun(victory: false)
            return
        }

        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((correct ? 0.7 : 1.3) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.afterAnswer()
        }
    }

    private func afterAnswer() {
        guard let battle else { return }
        if battle.enemyHP <= 0 {
            stopTimer()
            winBattle(battle)
        } else {
            nextQuestion()
        }
    }

    private func winBattle(_ battle: Battle) {
        var earned = battle.coinReward + equipEffects.coin
        if demonMode { earned *= 2 }               // 魔界：金币翻倍
        var messages: [String] = []

        switch battle.mode {
        case .opportunity:
            if let drop = rollItems(count: 1, stageGate: stage.index, excludeOwned: false).first {
                gainItem(drop)
                if let last = toast { messages.append(last) }
            }
            if Int.random(in: 0..<100) < 35 {
                let curse = min(hp - 1, 4)
                if curse > 0 {
                    hp = hero == .demon ? min(0, hp - curse) : hp - curse
                    messages.append("☠️ 秘宝上附着诅咒，损失 \(curse) 点生命！")
                }
            }
        case .trial:
            messages.append("💡 灵光入体，心神一振")
        case .standard:
            break
        }

        // 普通战斗：低阶 8% 概率掉落（增加战斗正反馈）
        if !battle.isTomb, battle.node != .boss, Int.random(in: 0..<100) < 8 {
            if let drop = rollItems(count: 1, stageGate: 0, excludeOwned: false).first {
                gainItem(drop)
                if let last = toast { messages.append(last) }
            }
        }
        // 地下墓穴胜利：1/50 掉落神秘魔器
        if battle.isTomb {
            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "towerTombWins") + 1,
                                      forKey: "towerTombWins")
            if Int.random(in: 0..<50) == 0 {
                dropDemonItem()
                if let last = toast { messages.append(last) }
            }
        }

        let regen = equipEffects.regen
        if regen > 0, hp < maxHP {
            hp = min(maxHP, hp + regen)
            messages.append("🧚 精灵治愈 +\(regen)")
        }
        // 魔修胜利回涌：向 0 回升 3 点（中和无法回血的难度）
        if hero == .demon, hp < 0 {
            hp = min(0, hp + 3)
            messages.append("🔥 魔气回涌 +3")
        }

        coins += earned
        messages.insert("💰 +\(earned) 金币", at: 0)
        wearEquipment()
        if let wear = toast, !messages.contains(wear) { messages.append(wear) }
        persistWealth()

        self.battle = nil
        question = nil

        if battle.node == .boss {
            finishRun(victory: true)
        } else {
            // 捷径（小Boss）胜利：多前进一个节点
            if shortcutPending, case .elite = battle.node, floor + 1 < stage.floors {
                floor += 2
                messages.append("🏹 捷径得通，跳过一程！")
            } else {
                floor += 1
            }
            shortcutPending = false
            saveRun()
            makeChoices()
            phase = .map
            toast = messages.joined(separator: "  ")
        }
    }

    func skipQuestion() {
        guard phase == .battle, var battle, battle.skipAvailable,
              battle.lastAnswerCorrect == nil else { return }
        battle.skipAvailable = false
        self.battle = battle
        nextQuestion()
    }

    /// 关闭技能预览（玩家已了解，继续战斗）
    func dismissSkillPreview() {
        showSkillPreview = false
    }

    /// 请求撤退（显示游戏内确认层）
    func requestRetreat() {
        guard phase == .battle, let battle, battle.canRetreat else { return }
        retreatConfirming = true
    }
    func cancelRetreat() {
        retreatConfirming = false
    }

    /// 撤退惩罚描述
    func retreatPenalty() -> String {
        let f = floor
        var p = ["💰 -\(3 + Int.random(in: 0...f))金", "❤️ -\(Int.random(in: 1...max(1,f/2)))血"]
        if let w = equipped["weapon"], durability[w] ?? 0 > 0 {
            p.append("⚔️ 武器耐久 -\(1 + Int.random(in: 0...2))")
        }
        if petMaxHP > 0 || spriteMaxHP > 0 { p.append("🧚 宠物/精灵受伤") }
        return "撤退损失：\n" + p.joined(separator: " ")
    }

    /// 确认撤退（含随机损失），由视图在确认后调用
    func fleeBattle() {
        guard phase == .battle, let battle, battle.canRetreat else { return }
        retreatConfirming = false
        stopTimer()
        advanceTask?.cancel()
        let f = floor
        let coinLoss = 3 + Int.random(in: 0...f)
        let hpLoss = Int.random(in: 1...max(1, f / 2))
        coins = max(0, coins - coinLoss)
        hp = hero == .demon ? hp - hpLoss : max(1, hp - hpLoss)
        var lossLog = ["💰-\(coinLoss)金", "❤️-\(hpLoss)血"]
        // 装备耐久：按品阶磨损，高阶磨损更低
        func tierWear(_ tier: ItemTier) -> Int {
            switch tier {
            case .low: return 2          // 低阶磨损减半
            case .mid: return 3
            case .high: return 2
            case .rare: return 1
            case .legendary, .goldLegend: return 1
            case .demon: return 1
            }
        }
        for (slot, itemId) in equipped {
            guard let g = GameItem.catalog.first(where: { $0.id == itemId }),
                  g.category.equipKey != nil else { continue }
            let wear = tierWear(g.tier)
            if let cur = durability[itemId] {
                let nd = cur - wear
                if nd <= 0 {
                    durability.removeValue(forKey: itemId); equipped.removeValue(forKey: slot)
                } else { durability[itemId] = nd }
            }
        }
        // 极低概率直接掉落装备（1/10000）
        if Int.random(in: 1...10000) == 1, let oi = inventory.randomElement(),
           let gi = oi.item, gi.category.equipKey != nil {
            inventory.removeAll { $0.id == oi.id }
            toast = (toast ?? "") + " 遗失了\(gi.name)"
        }
        // 宠物/精灵受伤
        if petHP > 0 { petHP = max(0, petHP - Int.random(in: 1...3)) }
        if spriteHP > 0 { spriteHP = max(0, spriteHP - Int.random(in: 1...3)) }
        if petHP == 0 { equipped["pet"] = nil; toast = (toast ?? "") + " 🐾 宠物离去" }
        if spriteHP == 0 { equipped["sprite"] = nil; toast = (toast ?? "") + " 🌟 精灵消散" }
        self.battle = nil
        question = nil
        persistAll()
        makeChoices()
        phase = .map
        toast = "🏃 撤退完成，损失：" + lossLog.joined(separator: " ")
        // 撤退结束本次挑战：1/50 魔修觉醒
        if Int.random(in: 0..<50) == 0 {
            becomeDemon(withItem: false)
        }
    }

    private func persistAll() {
        UserDefaults.standard.set(coins, forKey: "towerCoins")
        UserDefaults.standard.set(durability, forKey: "towerDurability")
        UserDefaults.standard.set(petHP, forKey: "towerPetHP")
        UserDefaults.standard.set(spriteHP, forKey: "towerSpriteHP")
    }

    // MARK: - 魔修敌人阵营

    /// 魔修视角：正道小怪名池
    private static let demonEnemyMinions = ["仙门弟子", "降魔道人", "捉妖修士", "镇妖卫", "降妖剑客", "浩然书生"]
    /// 魔修视角：正道精英名池
    private static let demonEnemyElites = ["仙门长老", "降魔真人", "除妖天师", "伏魔剑仙"]
    /// 魔修视角：正道 Boss 名池（按境界轮换）
    private static let demonEnemyBosses = ["伏魔仙尊", "斩妖天师", "正道魁首", "浩然剑仙",
                                           "天罚尊者", "降龙真人", "紫霄道尊", "诛仙老祖"]

    // MARK: - 计时

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard phase == .battle, var battle, battle.isTimed else { return }
        battle.timeLeft -= 1
        self.battle = battle
        if battle.timeLeft <= 0 {
            stopTimer()
            if battle.mode == .trial {
                self.battle = nil
                question = nil
                makeChoices()
                phase = .map
                toast = "💨 灵光消散了，未获奖励"
            } else {
                finishRun(victory: false)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 结算

    private func finishRun(victory: Bool) {
        stopTimer()
        advanceTask?.cancel()
        persistWealth()

        guard victory else {
            clearSave()
            // 魔修死亡：身份结束，回到最初的选择界面
            if hero == .demon {
                endDemon()
                phase = .defeat
                return
            }
            // 魔修觉醒：失败 1/10 化身魔修并获得魔器；否则 1/50 化身魔修
            let roll = Int.random(in: 0..<1000)
            if roll < 100 {
                becomeDemon(withItem: true)
            } else if roll < 120 {
                becomeDemon(withItem: false)
            }
            phase = .defeat
            return
        }

        winCount += 1
        UserDefaults.standard.set(winCount, forKey: "towerWins")
        coins += 15 + stage.index * 5

        if stage.index >= TowerStage.all.count {
            clearSave()
            pathCompleted = true
            UserDefaults.standard.set(true, forKey: "towerPathCompleted")
            UserDefaults.standard.set(true, forKey: "towerCleared_\(hero.rawValue)")   // 记录通关角色
            UserDefaults.standard.set(true, forKey: "towerDemonUnlocked")   // 通关全部境界解锁魔修
            persistWealth()
            phase = .pathComplete
        } else {
            unlockedStage = max(unlockedStage, stage.index + 1)
            UserDefaults.standard.set(unlockedStage, forKey: "towerUnlockedStage")
            // 先推进到下一境的状态并存档（生命延续），这样玩家可以现在走或下次继续
            justClearedStageName = stage.name
            advanceStageState()
            persistWealth()
            phase = .stageClear
        }
    }

    /// 推进到下一境：沿用同一角色，**生命延续不重置**，仅得少量突破奖励
    private func advanceStageState() {
        guard let next = TowerStage.all.first(where: { $0.index == stage.index + 1 }) else { return }
        stage = next
        floor = 1
        usedCategoryIds = []
        recentWordIds = []
        if hero != .demon { maxHP += 5 }  // 境界突破，根基更厚（魔修恒 0）
        hp = min(hero == .demon ? 0 : maxHP, hp + max(12, maxHP * 2 / 5))  // 突破回复约四成（生命仍跨境共用）
        saveRun()
    }

    /// 在突破页点“继续”：状态已在 finishRun 里推进到下一境，这里只需进入地图
    func continueToNextStage() {
        makeChoices()
        phase = .map
    }
}
