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
        var pairs: [MatchPair] = []   // 词义连线配对（4 词 × 4 释义）
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
        var perfect = false                 // 本题完美判定（连击 ≥3，伤害 ×1.5）
        var weakened = false                // 破绽：组首领攻击减半
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
    /// 灵泉冷却：上次灵泉出现楼层（连续节点/事件不重复）
    private var lastRestFloor: Int = -1
    private var lastEventSpringFloor: Int = -1
    @Published private(set) var choices: [NodeType] = []
    @Published private(set) var battle: Battle?
    @Published private(set) var question: Question?
    @Published var spellInput = ""
    /// 词义连线：玩家已完成的配对（词 → 释义）
    @Published var matchAnswers: [String: String] = [:]
    @Published private(set) var toast: String?
    @Published private(set) var justClearedStageName = ""    // 刚通关的境界名（用于突破页展示）
    @Published private(set) var runInProgress = false        // 是否有进行中的修仙路（锁定角色）
    @Published private(set) var demonMode = false            // 魔化状态（魔界修炼）
    /// 关卡组：单节点 = 连续多场战斗（2~5 关）
    @Published private(set) var groupTotal = 0    // 关卡组总关数（0 = 非关卡组）
    @Published private(set) var groupIndex = 0   // 当前第几关（1-based）
    /// 组内选择：每战后玩家选择继续/休息/突击
    @Published private(set) var groupChoices: [GroupChoice] = []
    private var groupStages: [NodeType] = []     // 组内子关卡序列
    private var groupEnemyName: String?          // 组内统一敌人名（贯穿全组）
    private var groupEnemyIcon: String?          // 组内统一敌人图标
    private var groupTomb = false                // 组是否为地下墓穴（组内统一判定一次）
    /// 分叉口（S2）：本境固定楼层展开 2~3 条候选路线
    @Published private(set) var branchRoutes: [RouteType] = []   // 当前分叉口候选路线
    private var usedRoutes: Set<RouteType> = []                  // 本分叉口已走过的路线（灰显）
    private var branchFloors: Set<Int> = []                      // 本境分叉口楼层（中段与后段至少各一）
    private var currentRoute: RouteType = .steady                // 当前关卡组所属路线
    /// 路线差异化参数（险路/秘路生效，平路为默认值）
    private var groupDifficulty = 1.0    // 敌人血攻倍率（险路 1.3，秘路 0.8~1.5 随机）
    private var groupRewardMult = 1.0    // 组奖励金币倍率（险路 2.0，秘路 0.5~3.0 随机）
    private var groupTierBoost = 1.0     // 组通关掉落高品阶权重（险路 1.2）
    private var groupCanRetreat = true   // 组内各关是否允许撤退（唯一选项时强制战斗）
    /// 进入战斗/路线前的地图选择界面（撤退后原样恢复，不刷新关卡）
    private var preGroupChoices: [NodeType] = []
    private var preGroupRoutes: [RouteType] = []
    /// 事件专属标记
    private var eventRobber = false   // 劫匪拦路：失败扣金币不死亡
    private var eventWordTide = false // 词妖潮：组完成不推进楼层
    private var eventEarBomb = false  // 魔音灌耳：奖励后不推进楼层
    private var eventMindTrial = false // 心魔幻境：同前
    /// 事件 buff/debuff（下一个节点组生效）
    private var eventDamageBuff = 0    // 下个节点组伤害 +N（词灵求救/天降奇遇）
    private var eventPenaltyBuff = 0   // 下个节点组答错额外 +N（境界压制）
    /// 关卡组的词汇分类（特定词汇节点如"衣物试炼"：组内所有小关都用该分类出题）
    private var groupCategory: WordCategory?
    /// 组内完美统计（S4 破绽机制：组首领战完美率 ≥60% 触发攻击减半）
    private var groupPerfectCount = 0    // 组内完美（连击 ≥3）次数
    private var groupAnswered = 0        // 组内答题总数

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

    private func rollItems(count: Int, stageGate: Int, excludeOwned: Bool, tierBoost: Double = 1.0) -> [GameItem] {
        var candidates = GameItem.catalog.filter { $0.tier.stageGate <= stageGate }
        if excludeOwned {
            candidates = candidates.filter { item in !inventory.contains(where: { $0.id == item.id }) }
        }
        var result: [GameItem] = []
        while result.count < count, !candidates.isEmpty {
            // tierBoost > 1：高品阶权重放大（险路组通关掉落）
            let total = candidates.reduce(0) { $0 + Int(Double($1.tier.weight) * tierBoost) }
            var roll = Int.random(in: 0..<max(1, total))
            var picked: GameItem?
            for item in candidates {
                roll -= Int(Double(item.tier.weight) * tierBoost)
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
        if groupTotal > 0 {
            // 组内商人：离开后显示组内选择（继续/休息/突击）
            var messages: [String] = ["🛒 购入物品"]
            groupIndex += 1
            if groupIndex < groupTotal {
                makeGroupChoices()
                phase = .map
                toast = messages.joined(separator: "  ")
            } else {
                finishGroup(messages: &messages)
                floor += 1
                proceedToMap(messages: messages)
            }
        } else {
            nextFloor()
        }
    }

    // MARK: - 装备/物品

    func usable(_ item: GameItem) -> Bool {
        item.restrictedTo == nil || item.restrictedTo == hero
    }

    func equip(_ owned: OwnedItem) {
        guard let item = owned.item, let key = item.category.equipKey else { return }
        equipped[key] = owned.id
        // 宠物/精灵：根据品阶设定生命点
        if item.category == .pet {
            petMaxHP = tierToPetMaxHP(item.tier)
            petHP = petMaxHP
        } else if item.category == .sprite {
            spriteMaxHP = tierToPetMaxHP(item.tier)
            spriteHP = spriteMaxHP
        }
        persistWealth()
    }

    func unequip(_ key: String) {
        equipped[key] = nil
        if key == "pet" { petHP = 0; petMaxHP = 0 }
        if key == "sprite" { spriteHP = 0; spriteMaxHP = 0 }
        persistWealth()
    }

    /// 宠物/精灵品阶→基础生命（低 6 / 中 10 / 高 14 / 稀 18 / 传奇+ 22 / 魔器 26）
    private func tierToPetMaxHP(_ tier: ItemTier) -> Int {
        switch tier {
        case .low: return 6
        case .mid: return 10
        case .high: return 14
        case .rare: return 18
        case .legendary, .goldLegend: return 22
        case .demon: return 26
        }
    }

    /// 从已装备项刷新宠物/精灵最大生命与当前生命（闯关之路重启时调用）
    private func refreshPetSpriteHP() {
        if let petId = equipped["pet"],
           let owned = inventory.first(where: { $0.id == petId }),
           let item = owned.item, item.category == .pet {
            petMaxHP = tierToPetMaxHP(item.tier)
            petHP = petMaxHP
        } else {
            petHP = 0; petMaxHP = 0
        }
        if let spriteId = equipped["sprite"],
           let owned = inventory.first(where: { $0.id == spriteId }),
           let item = owned.item, item.category == .sprite {
            spriteMaxHP = tierToPetMaxHP(item.tier)
            spriteHP = spriteMaxHP
        } else {
            spriteHP = 0; spriteMaxHP = 0
        }
        persistAll()
    }

    // MARK: - 宠物/精灵状态与战斗技能

    /// 状态枚举（按 HP 比例）
    enum PetSpriteState: Equatable { case healthy, injured, critical, gone }

    /// 宠物当前状态
    var petState: PetSpriteState {
        guard petMaxHP > 0 else { return .gone }
        let ratio = Double(petHP) / Double(petMaxHP)
        if ratio > 0.66 { return .healthy }
        if ratio > 0.33 { return .injured }
        return .critical
    }

    /// 精灵当前状态
    var spriteState: PetSpriteState {
        guard spriteMaxHP > 0 else { return .gone }
        let ratio = Double(spriteHP) / Double(spriteMaxHP)
        if ratio > 0.66 { return .healthy }
        if ratio > 0.33 { return .injured }
        return .critical
    }

    /// 根据状态计算技能触发概率（健康 35% / 受伤 20% / 濒死 8%）
    private func petSkillChance(_ state: PetSpriteState) -> Int {
        switch state { case .healthy: return 35; case .injured: return 20; case .critical: return 8; case .gone: return 0 }
    }

    /// 答对时触发宠物/精灵技能（各品阶自带效果随机激活）
    private func activatePetSpriteSkill(battle: inout Battle) -> String? {
        // 先检查宠物
        if let petId = equipped["pet"], petHP > 0,
           let owned = inventory.first(where: { $0.id == petId }),
           let item = owned.item, item.category == .pet,
           Int.random(in: 0..<100) < petSkillChance(petState) {
            petHP = max(0, petHP - 1)  // 使用技能消耗 1 血
            if let msg = applyPetSkill(item, battle: &battle) { return "🐾 \(msg)" }
        }
        // 再检查精灵
        if let spriteId = equipped["sprite"], spriteHP > 0,
           let owned = inventory.first(where: { $0.id == spriteId }),
           let item = owned.item, item.category == .sprite,
           Int.random(in: 0..<100) < petSkillChance(spriteState) {
            spriteHP = max(0, spriteHP - 1)  // 使用技能消耗 1 血
            if let msg = applyPetSkill(item, battle: &battle) { return "✨ \(msg)" }
        }
        return nil
    }

    /// 应用宠物/精灵技能效果（按物品自身属性）
    private func applyPetSkill(_ item: GameItem, battle: inout Battle) -> String? {
        if item.damageBonus > 0 {
            battle.enemyHP = max(0, battle.enemyHP - item.damageBonus)
            return "\(item.name)助攻 +\(item.damageBonus) 伤害！"
        }
        if item.regenPerWin > 0 {
            hp = min(maxHP, hp + item.regenPerWin)
            return "\(item.name)治疗 +\(item.regenPerWin)"
        }
        if item.coinBonus > 0 {
            coins += item.coinBonus
            return "\(item.name)寻得 +\(item.coinBonus) 金币"
        }
        if item.defenseBonus > 0 {
            battle.shieldAvailable = true
            return "\(item.name)护主，下次免伤"
        }
        if item.timeBonus > 0, battle.isTimed {
            battle.timeLeft += item.timeBonus
            return "\(item.name)延滞 +\(item.timeBonus) 秒"
        }
        return nil
    }

    /// 答错时宠物/精灵承受 1 点伤害；0 血时自动离去
    private func damagePetSpriteOnWrong() {
        if petHP > 0 {
            petHP = max(0, petHP - 1)
            if petHP == 0 {
                equipped["pet"] = nil
                toast = "🐾 宠物力竭离去…"
            }
        }
        if spriteHP > 0 {
            spriteHP = max(0, spriteHP - 1)
            if spriteHP == 0 {
                equipped["sprite"] = nil
                toast = "✨ 精灵灵力散尽…"
            }
        }
        if petHP == 0 || spriteHP == 0 { persistWealth() }
    }

    /// 检查宠物/精灵是否 HP=0（战斗结束后清理）
    private func checkPetSpriteDeath() {
        if petHP == 0, equipped["pet"] != nil {
            equipped["pet"] = nil
            toast = (toast ?? "") + " 🐾 宠物力竭离去"
        }
        if spriteHP == 0, equipped["sprite"] != nil {
            equipped["sprite"] = nil
            toast = (toast ?? "") + " ✨ 精灵灵力散尽"
        }
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
        resetGroup()                 // 回首页：结束进行中的关卡组
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

    /// 清空所有运行时状态（每次重新开始/继续闯关之路时调用；背包/金币/穿戴/图鉴等永久数据保留）
    private func resetRunState() {
        stopTimer()
        advanceTask?.cancel()
        battle = nil
        question = nil
        spellInput = ""
        choices = []
        preGroupChoices = []
        preGroupRoutes = []
        eventRobber = false
        eventWordTide = false
        eventEarBomb = false
        eventMindTrial = false
        eventDamageBuff = 0
        eventPenaltyBuff = 0
        resetGroup()
        branchRoutes = []
        usedRoutes = []
        branchFloors = []
        usedCategoryIds = []
        recentWordIds = []
        lastRestFloor = -1          // 灵泉冷却重置
        lastEventSpringFloor = -1
        shortcutPending = false
        retreatConfirming = false
        showSkillPreview = false
        justClearedStageName = ""
        demonMode = false
        toast = nil
        UserDefaults.standard.removeObject(forKey: "towerBattleTimeLeft")
    }

    private func beginRun(as heroClass: HeroClass, demonic: Bool) {
        clearSave()                    // 新一轮闯关之路：彻底重开（清残留存档）
        resetRunState()                // 清空所有运行时状态（战斗/组/地图/冷却等）
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
        // 重置宠物/精灵生命（重新从已装备项读取）
        refreshPetSpriteHP()
        // 重新开始：解锁进度回到凡人，闯关之路从第一境重新显示（通关记录 winCount 保留）
        unlockedStage = 1
        pathCompleted = false
        UserDefaults.standard.set(unlockedStage, forKey: "towerUnlockedStage")
        UserDefaults.standard.set(false, forKey: "towerPathCompleted")
        floor = 1
        branchFloors = Self.makeBranchFloors(floors: stage.floors)   // 本境分叉口楼层
        saveRun()
        makeChoices()
        phase = .map
        if hero == .demon {
            toast = "😈 不死不灭：生命恒为 0 以下；但魔气越深越危险——负血加深，受击灰飞烟灭的概率越高！"
        }
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
        resetRunState()                 // 清空运行时残留状态（战斗/组/冷却等）
        hero = heroClass
        demonMode = (save["demon"] as? Bool) ?? false
        stage = savedStage
        maxHP = savedMaxHP
        hp = min(savedHP, savedMaxHP)
        floor = min(savedFloor, savedStage.floors)
        usedCategoryIds = Set(save["usedCats"] as? [String] ?? [])
        recentWordIds = []
        branchFloors = Self.makeBranchFloors(floors: stage.floors)
        usedRoutes = []
        branchRoutes = []
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
        QuestionKind.available(stageIndex: stage.index)
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
        // S2 分叉口：本境固定楼层展开路线选择（险路/平路/秘路）
        if branchFloors.contains(floor) {
            makeBranchRoutes()
            return
        }

        var candidates: [NodeType] = [.battle(category: nil, kind: randomKind())]
        for category in availableCategories.shuffled().prefix(2) {
            candidates.append(.battle(category: category, kind: randomKind()))
        }
        if floor >= 3 { candidates.append(.elite(kind: randomKind())) }
        if floor >= 2 { candidates.append(.timedTrial(kind: randomKind())) }
        if (hp * 2 <= maxHP || (hero == .demon && hp <= -3)), floor != lastRestFloor {
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
        // 撤退限制：当前只剩一个可选节点时必须打（不可撤退）
        let forced = choices.count == 1
        // 暂存当前选择界面（撤退后原样恢复，不刷新关卡）
        preGroupChoices = choices
        preGroupRoutes = []
        switch node {
        case .rest:
            hp = min(maxHP, hp + 15)
            lastRestFloor = floor
            // 宠物/精灵同享灵泉滋养：各恢复一半生命
            if petMaxHP > 0 { petHP = min(petMaxHP, petHP + max(1, petMaxHP / 2)) }
            if spriteMaxHP > 0 { spriteHP = min(spriteMaxHP, spriteHP + max(1, spriteMaxHP / 2)) }
            toast = hero == .demon
                ? "🔥 魔气滋养，回复 15 点（当前 \(hp)）"
                : "💧 灵泉涤体，恢复 15 点生命（\(hp)/\(maxHP)）"
            // 灵泉不消耗节点楼层：回血后继续在当前楼层选下一个节点
            saveRun()
            persistAll()          // 宠物/精灵生命持久化
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
            startGroup(node: node, canRetreat: !forced)
        case .elite:
            // 捷径：小 Boss 难，但胜利后直接跳过一个节点（路短）
            shortcutPending = true
            enterBattle(node, mode: .standard, canRetreat: !forced)
        default:
            shortcutPending = false
            enterBattle(node, mode: .standard, canRetreat: !forced)
        }
    }

    // MARK: - 关卡组（单节点 = 2~5 场连续战斗）

    /// 当前境界段位的关卡组关数（1~4 境 2 关 … 14~16 境 5 关）
    var groupCount: Int {
        switch stage.index {
        case 1...4: return 2
        case 5...9: return 3
        case 10...13: return 4
        default: return 5
        }
    }

    /// 指定节点的关卡组关数（仅 battle 节点是关卡组；其余返回 0）
    func groupCount(for node: NodeType) -> Int {
        guard case .battle = node else { return 0 }
        return groupCount
    }

    /// 启动关卡组：统一敌人名/图标贯穿全组 + 应用路线差异化参数
    private func beginGroup(stages: [NodeType], difficulty: Double, rewardMult: Double, tierBoost: Double,
                            canRetreat: Bool = true, category: WordCategory? = nil) {
        groupCanRetreat = canRetreat   // 组内各关撤退许可（唯一选项时强制战斗）
        groupCategory = category       // 特定词汇分类贯穿全组（精英/限时关也出同类词）
        let minion = stage.minions.randomElement()!
        // 地下墓穴：组内统一判定一次，全组一致（避免中途换名/换图标）
        groupTomb = Int.random(in: 0..<(hero == .demon ? 200 : 1000)) == 0
        // 组内敌人：同一名字/图标贯穿全组（魔修视角在此统一改名一次）
        var name = minion.name
        if hero == .demon, !groupTomb, Int.random(in: 0..<100) >= 15 {
            name = Self.demonEnemyMinions.randomElement() ?? name
        }
        groupEnemyName = name
        groupEnemyIcon = minion.icon
        groupDifficulty = difficulty
        groupRewardMult = rewardMult
        groupTierBoost = tierBoost
        groupStages = stages
        groupTotal = groupStages.count
        groupIndex = 1
        // 用 advanceGroup 启动：组首关也可能是灵泉/商人（秘路混合组）
        var bootMessages: [String] = []
        advanceGroup(messages: &bootMessages)
        if phase == .battle, !bootMessages.isEmpty {
            toast = bootMessages.joined(separator: "  ")
        }
    }

    /// 普通节点启动关卡组：按境界段位生成 2~5 关，标准难度/收益
    private func startGroup(node: NodeType, canRetreat: Bool = true) {
        let category: WordCategory?
        if case .battle(let cat, _) = node { category = cat } else { category = nil }
        beginGroup(stages: makeGroupStages(for: node), difficulty: 1.0, rewardMult: 1.0, tierBoost: 1.0,
                   canRetreat: canRetreat, category: category)
    }

    /// 组内子关卡序列（普通×N + 精英/限时 + 收尾/组首领）
    /// 组内小关混合题型：第一关与节点显示一致，后续关随机题型（避免整组同一种类型）
    private func makeGroupStages(for node: NodeType) -> [NodeType] {
        guard case .battle(let category, let kind) = node else { return [] }
        let normal = NodeType.battle(category: category, kind: kind)                    // 第一关：节点题型
        let normalB = NodeType.battle(category: category, kind: randomKind())           // 后续普通关：随机题型
        let elite = NodeType.elite(kind: randomKind())
        let timed = NodeType.timedTrial(kind: randomKind())
        switch stage.index {
        case 1...4:   // 2 关：普通×1 + 收尾×1
            return [normal, elite]
        case 5...9:   // 3 关：普通×2 + 精英×1
            return [normal, normalB, elite]
        case 10...13: // 4 关：普通×2 + 玩法/限时×1 + 精英×1
            return [normal, normalB, Bool.random() ? timed : NodeType.battle(category: category, kind: randomKind()), elite]
        default:      // 5 关：普通×2 + 限时×1 + 玩法/精英×1 + 组首领×1
            return [normal, normalB, timed,
                    Bool.random() ? NodeType.battle(category: category, kind: randomKind()) : elite, elite]
        }
    }

    /// 关卡组通关回血（按段位；魔修 maxHP=0 自动向 0 回升）
    private func groupClearHeal() -> Int {
        switch stage.index {
        case 1...4: return 8
        case 5...9: return 5
        case 10...13: return 3
        default: return 0
        }
    }

    /// 结束关卡组（组通关 / 撤退 / 死亡时调用，清空组进度）
    private func resetGroup() {
        groupStages = []
        groupTotal = 0
        groupIndex = 0
        groupChoices = []
        groupEnemyName = nil
        groupEnemyIcon = nil
        groupTomb = false
        groupDifficulty = 1.0
        groupRewardMult = 1.0
        groupTierBoost = 1.0
        groupCanRetreat = true
        groupCategory = nil
        eventDamageBuff = 0
        eventPenaltyBuff = 0
        groupPerfectCount = 0
        groupAnswered = 0
        currentRoute = .steady
    }

    // MARK: - 分叉口（S2：路线选择）

    /// 本境分叉口楼层：1~3 个（地图中段与后段至少各一），太短的地图不设
    static func makeBranchFloors(floors: Int) -> Set<Int> {
        guard floors >= 4 else { return [] }
        var set: Set<Int> = []
        let mid = max(2, floors / 2)
        let late = max(mid + 1, min(floors - 1, floors * 3 / 4))
        set.insert(mid)
        if late <= floors - 1 { set.insert(late) }
        // 第三处约 1/3 概率（生成时固定，撤退后不变）
        if set.count < 3, Int.random(in: 0..<3) == 0,
           let extra = (2..<floors).filter({ !set.contains($0) }).randomElement() {
            set.insert(extra)
        }
        return set
    }

    /// 生成分叉口候选路线（险路 + 平路 + 40% 秘路；已走过的灰显不可重复选）
    private func makeBranchRoutes() {
        var routes: [RouteType] = [.perilous, .steady]
        if Int.random(in: 0..<100) < 40 { routes.append(.mystery) }
        // 全部路线都尝试过：重置（避免卡死在分叉口）
        if routes.allSatisfy({ usedRoutes.contains($0) }) {
            usedRoutes.removeAll()
        }
        branchRoutes = routes
        choices = []
    }

    /// 已走过的路线（灰显不可重复选）
    func isRouteUsed(_ route: RouteType) -> Bool {
        usedRoutes.contains(route)
    }

    /// 选择路线：启动差异化关卡组（险路强收益 / 平路标准 / 秘路随机）
    func chooseRoute(_ route: RouteType) {
        guard phase == .map, !branchRoutes.isEmpty, !isRouteUsed(route) else { return }
        // 暂存当前分叉口路线界面（撤退后原样恢复，不刷新关卡）
        preGroupRoutes = branchRoutes
        preGroupChoices = []
        // 撤退限制：可用路线只剩一条时强制战斗（不可撤退）
        let availableCount = branchRoutes.filter { !usedRoutes.contains($0) }.count
        usedRoutes.insert(route)
        branchRoutes = []
        currentRoute = route
        let kind = randomKind()
        switch route {
        case .perilous:
            // 2 关（组首领强）：普通 + 精英；敌人 +30% 血攻；组奖励 ×2；高品阶掉落 ↑
            beginGroup(stages: [.battle(category: nil, kind: kind), .elite(kind: kind)],
                       difficulty: 1.3, rewardMult: 2.0, tierBoost: 1.2, canRetreat: availableCount > 1)
        case .steady:
            // 3 关：普通×2 + 精英；标准难度/收益
            beginGroup(stages: [.battle(category: nil, kind: kind),
                                .battle(category: nil, kind: kind),
                                .elite(kind: kind)],
                       difficulty: 1.0, rewardMult: 1.0, tierBoost: 1.0, canRetreat: availableCount > 1)
        case .mystery:
            // 随机 2~4 关：普通/限时/灵泉/商人混合 + 组首领；难度/收益随机（可能大赚或血亏）
            var stages: [NodeType] = []
            let count = Int.random(in: 2...4)
            for i in 0..<count {
                if i == count - 1 {
                    stages.append(.elite(kind: kind))     // 组首领必在
                } else {
                    let roll = Int.random(in: 0..<100)
                    if roll < 15 {
                        stages.append(.rest)              // 组内灵泉：自动回血
                    } else if roll < 30 {
                        stages.append(.merchant)          // 组内商人：弹商店
                    } else if roll < 55 {
                        stages.append(.timedTrial(kind: kind))
                    } else {
                        stages.append(.battle(category: nil, kind: kind))
                    }
                }
            }
            beginGroup(stages: stages,
                       difficulty: Double.random(in: 0.8...1.5),
                       rewardMult: [0.5, 1.0, 1.5, 2.0, 3.0].randomElement() ?? 1.0,
                       tierBoost: 1.0,
                       canRetreat: availableCount > 1)
        }
    }

    private func nextFloor() {
        floor += 1
        saveRun()
        if floor < stage.floors, floor > 1, Int.random(in: 0..<100) < 22 {
            // 按段位扩充事件池（低段位保留原三种，高段位解锁新事件）
            var pool: [TowerEvent] = [.forced, .opportunity, .trial]
            if stage.index >= 5 { pool.append(.wordTide) }
            if stage.index >= 5 { pool.append(.ruins) }
            // 灵泉现世：只在血量 ≤70% 时进入候选，且不与上回重复
            if stage.index >= 5, floor != lastEventSpringFloor, hp * 10 <= maxHP * 7 {
                pool.append(.spring)
            }
            if stage.index >= 10 { pool.append(.robber) }
            if stage.index >= 5 { pool.append(.earBomb) }
            if stage.index >= 10 { pool.append(.mindTrial) }
            if stage.index >= 5 { pool.append(.forkRoad) }
            if stage.index >= 5, coins >= 30 { pool.append(.wordSpirit) }
            if stage.index >= 5 { pool.append(.luckFall) }
            if stage.index >= 14 { pool.append(.realmSuppress) }
            phase = .event(pool.randomElement() ?? .forced)
            return
        }
        makeChoices()
        phase = .map
    }

    // MARK: - 突发事件

    /// 选择上古遗迹宝箱
    func selectRuinsOption(_ index: Int) {
        guard phase == .event(.ruins), index >= 0, index < ruinsOptions.count else { return }
        ruinsOptions = []
        switch index {
        case 0: // 金币
            coins += 20
            toast = "🏛️ 打开宝箱，获得 💰 +20 金币！"
        case 1: // 随机装备
            if let drop = rollItems(count: 1, stageGate: stage.index, excludeOwned: false).first {
                gainItem(drop)
                toast = "🏛️ 打开宝箱，获得 \(drop.name)！"
            } else { toast = "🏛️ 宝箱空空如也……" }
        default: // 未知宝箱：50% 扣血 / 50% 金币
            if Bool.random() {
                let dmg = Int.random(in: 3...6)
                hp = hero == .demon ? hp - dmg : max(1, hp - dmg)
                toast = "☠️ 宝箱里弹出陷阱，-\(dmg) 血！"
            } else {
                coins += 25
                toast = "🎉 宝箱里金光闪闪，💰 +25 金币！"
            }
        }
        makeChoices()
        phase = .map
    }

    /// 上古遗迹三选一
    @Published var ruinsOptions: [String] = []

    func acceptEvent(_ event: TowerEvent) {
        switch event {
        case .forced:
            enterBattle(.battle(category: nil, kind: randomKind()), mode: .standard, eventBoost: true, canRetreat: false)
        case .opportunity:
            enterBattle(.elite(kind: randomKind()), mode: .opportunity)
        case .trial:
            enterBattle(.timedTrial(kind: randomKind()), mode: .trial)
        case .spring:
            // 灵泉现世：回复 10~15 血
            let heal = Int.random(in: 10...15)
            hp = hero == .demon ? min(0, hp + heal) : min(maxHP, hp + heal)
            lastEventSpringFloor = floor
            toast = hero == .demon ? "🔥 魔泉滋养 +\(heal)" : "💧 灵泉涤体 +\(heal)"
            makeChoices()
            phase = .map
        case .robber:
            // 劫匪拦路：强制一战，胜利无事，失败扣 30% 金币（不死亡）
            eventRobber = true
            enterBattle(.battle(category: nil, kind: randomKind()), mode: .standard, eventBoost: true, canRetreat: false)
        case .ruins:
            // 上古遗迹：三选一宝箱
            ruinsOptions = ["💰 金币 +20", "🎁 随机装备", "☠️ 未知宝箱"]
            phase = .event(event)
        case .wordTide:
            // 词妖潮：连续 3 场小怪战
            eventWordTide = true
            let stages = (0..<3).map { _ in NodeType.battle(category: nil, kind: randomKind()) }
            var boot: [String] = []
            groupCanRetreat = false
            groupCategory = nil
            groupStages = stages
            groupTotal = stages.count
            groupIndex = 1
            advanceGroup(messages: &boot)
            if phase == .battle, !boot.isEmpty { toast = boot.joined(separator: "  ") }
        case .earBomb:
            // 魔音灌耳：3 道听音题（trial 模式，答错不扣血，20 秒限时）
            eventEarBomb = true
            enterBattle(.timedTrial(kind: .listen), mode: .trial)
        case .mindTrial:
            // 心魔幻境：5 道限时题（答对 N 题发 N×5 金币；0 题扣 6 血）
            eventMindTrial = true
            enterBattle(.timedTrial(kind: randomKind()), mode: .trial)
        case .forkRoad:
            // 迷雾岔路：随机结果（50% 战斗 / 50% 宝藏）
            if Int.random(in: 0..<100) < 50 {
                enterBattle(.battle(category: nil, kind: randomKind()), mode: .standard, canRetreat: false)
            } else {
                let gold = Int.random(in: 10...25)
                coins += gold
                toast = "🌫️ 岔路尽头发现了一处宝藏，获得 💰 +\(gold) 金币！"
                makeChoices()
                phase = .map
            }
        case .wordSpirit:
            // 词灵求救：花 30 金换下个节点组伤害 +2
            coins -= 30
            eventDamageBuff += 2
            toast = "🧚 词灵感激不尽，接下来的战斗中它将助你一臂之力！"
            makeChoices()
            phase = .map
        case .luckFall:
            // 天降奇遇：免费 buff（伤害 +2）
            eventDamageBuff += 2
            toast = "✨ 祥光入体，下个节点组伤害 +2！"
            makeChoices()
            phase = .map
        case .realmSuppress:
            // 境界压制：本节点组答错惩罚 +1
            eventPenaltyBuff += 1
            toast = "⚡ 灵气紊乱——下个节点组答错将额外承受 1 点伤害！"
            makeChoices()
            phase = .map
        }
    }

    func declineEvent(_ event: TowerEvent) {
        switch event {
        case .spring, .ruins, .forkRoad, .wordSpirit, .realmSuppress:
            // 可选绕行
            makeChoices()
            phase = .map
            let msgs: [TowerEvent: String] = [.spring: "你绕过了灵泉，继续赶路",
                                               .ruins: "你离开了遗迹，继续赶路",
                                               .forkRoad: "你随便选了一条路走了出去",
                                               .wordSpirit: "你叹了口气，继续赶路",
                                               .realmSuppress: "你绕开了压制区域，绕了个远路"]
            toast = msgs[event, default: "继续赶路"]
        case .forced, .robber, .wordTide, .earBomb, .mindTrial, .luckFall:
            // 不可拒绝
            return
        case .trial, .opportunity:
            // 原有可拒绝事件
            makeChoices()
            phase = .map
            toast = event == .opportunity ? "你绕开了秘宝洞窟，继续赶路" : "灵光消散，继续赶路"
        }
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
            // S4 限时压力：秘境守卫 60 秒起随境界递减至 30 秒
            timeLimit = mode == .trial ? 20 : max(30, 60 - power * 2)
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
        // 关卡组内统一判定一次（groupTomb 在 startGroup 时确定），保证整组敌人一致
        let tombRoll = hero == .demon ? 200 : 1000
        let inTomb = node != .boss && (groupTotal > 0 ? groupTomb : Int.random(in: 0..<tombRoll) == 0)
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

        // 路线差异化：险路/秘路按组难度系数放大敌人血攻
        enemyHP = max(3, Int(Double(enemyHP + difficulty.enemyHPMod) * groupDifficulty))
        attack = max(2, Int(Double(attack + difficulty.attackMod) * groupDifficulty))
        // S4 组首领：组内最后一关 +50% 血攻
        if groupTotal > 0, groupIndex == groupTotal {
            enemyHP = Int(Double(enemyHP) * 1.5)
            attack = Int(Double(attack) * 1.5)
        }
        // S4 破绽：组内完美率 ≥60% 时组首领攻击减半（答好题 → 打得更轻松）
        var weakened = false
        if groupTotal > 0, groupIndex == groupTotal, groupAnswered >= 3,
           groupPerfectCount * 5 >= groupAnswered * 3 {
            attack = max(1, attack / 2)
            weakened = true
        }
        if timed { timeLimit += equipEffects.time }

        let disabled = ability == .disableSkill
        let retreatAllowed = canRetreat && node != .boss
        // 魔修视角：敌人多为正道修士，偶尔遭遇同族魔道（15% 保持原名）
        // 关卡组内不在此改名：组启动时已按英雄视角统一（见 startGroup）
        if hero == .demon, groupTotal == 0, !inTomb, Int.random(in: 0..<100) >= 15 {
            switch node {
            case .boss:
                enemyName = Self.demonEnemyBosses[stage.index % Self.demonEnemyBosses.count]
            case .elite:
                enemyName = Self.demonEnemyElites.randomElement() ?? enemyName
            default:
                enemyName = Self.demonEnemyMinions.randomElement() ?? enemyName
            }
        }
        // 关卡组：组内所有子关卡共用同一敌人名/图标（组启动时已统一；墓穴组保持墓穴守卫）
        if groupTotal > 0, !inTomb, let gName = groupEnemyName, let gIcon = groupEnemyIcon {
            enemyName = gName
            enemyIcon = gIcon
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
            isTomb: inTomb,
            weakened: weakened
        )
        spellInput = ""
        phase = .battle
        if ability != .none { showSkillPreview = true }   // 有技能怪物进入战斗前弹出预览
        // 墓穴提示仅在组第一关（或非组战斗）显示一次，避免覆盖组内连战消息
        if inTomb, groupIndex <= 1 { toast = "⚰️ 你误入神秘关卡——地下墓穴！" }
        if disabled { toast = "🏀 \(enemyName)：唱！跳！rap！篮球！——你的技能被封印了！" }
        nextQuestion()
        if timed { startTimer() }
    }

    private func questionPool(for node: NodeType) -> [Word] {
        let window = difficultyWindow()
        let base = window.isEmpty ? pool : window
        // 分类：节点自带分类优先；否则用关卡组分类（特定词汇关卡如"衣物试炼"贯穿全组）
        let category: WordCategory?
        if case .battle(let cat?, _) = node {
            category = cat
        } else {
            category = groupCategory
        }
        if let category {
            let windowSet = Set(window.map(\.id))
            let catWords = categoryWords[category.id] ?? []
            // 分类战斗：优先窗口内同类，不足则用全部同类（始终不混入无关词）
            let filtered = catWords.filter { windowSet.contains($0.id) }
            if filtered.count >= 6 { return filtered }
            if catWords.count >= 6 { return catWords }
            // 同类词仍不足 6 个：全部同类词+窗口内最接近词混合（优先同类）
            return (catWords + base).prefix(20).shuffled()
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
        // MARK: - S3 新题型
        case .listen:
            // 听音辨义：TTS 朗读单词，4 选 1 选中文释义（须听懂且认识，比选词更难）
            var options = Array(Set(pool.map { Self.firstLine($0.definitionCn) }.filter { $0 != cnDef })
                .shuffled().prefix(3))
            let index = Int.random(in: 0...options.count)
            options.insert(cnDef, at: index)
            question = Question(kind: kind, word: word, prompt: "", options: options, correctIndex: index, spellHint: "")
            SpeechService.shared.speak(word.headword)
        case .formChange:
            // 词形变换：解析 exchange 字段，选正确变形
            let forms = parseExchange(word.exchange ?? "")
            if forms.count >= 4, let (formLabel, correctForm) = forms.first {
                var opts = Set<String>()
                opts.insert(correctForm)
                // 从其他词的 exchange 找干扰项
                for _ in 0..<10 {
                    if let other = pool.randomElement(), let otherEx = other.exchange {
                        let otherForms = parseExchange(otherEx)
                        if let otherForm = otherForms.first?.1, otherForm != correctForm {
                            opts.insert(otherForm)
                        }
                    }
                    if opts.count >= 4 { break }
                }
                var options = Array(opts).shuffled()
                let ci = options.firstIndex(of: correctForm) ?? 0
                let prompt = "\(word.headword) → \(formLabel)"
                question = Question(kind: kind, word: word, prompt: prompt, options: options, correctIndex: ci, spellHint: "")
            } else { fallbackToEnToCn() }
        case .cloze:
            // 完形填空：例句挖空选词
            if let sentence = WordMemoryService.shared.sentences(for: word.headword)?.first,
               sentence.lowercased().contains(word.headword.lowercased()) {
                let blanked = sentence.replacingOccurrences(of: word.headword, with: "____", options: .caseInsensitive)
                var opts = Array(Set(pool.map(\.headword).filter { $0.lowercased() != word.headword.lowercased() })
                    .shuffled().prefix(3))
                let index = Int.random(in: 0...opts.count)
                opts.insert(word.headword, at: index)
                question = Question(kind: kind, word: word, prompt: blanked, options: opts, correctIndex: index, spellHint: "")
            } else { fallbackToEnToCn() }
        case .rootMerge:
            // 词根拆解：碎片组合成词
            if let (fragments, full) = WordMemoryService.shared.rootPuzzle(for: word.headword) {
                var opts = Set<String>()
                opts.insert(full)
                for _ in 0..<12 {
                    if let other = pool.randomElement(),
                       let (_, otherFull) = WordMemoryService.shared.rootPuzzle(for: other.headword),
                       otherFull != full {
                        opts.insert(otherFull)
                    }
                    if opts.count >= 4 { break }
                }
                var options = Array(opts).shuffled()
                let ci = options.firstIndex(of: full) ?? 0
                let prompt = fragments.joined(separator: " + ")
                question = Question(kind: kind, word: word, prompt: prompt, options: options, correctIndex: ci, spellHint: "")
            } else { fallbackToEnToCn() }
        case .match:
            // 词义连线：4 词 × 4 释义配对
            var ws = Set<String>()
            ws.insert(word.headword)
            for _ in 0..<8 {
                if let other = pool.randomElement(), ws.count < 4 {
                    ws.insert(other.headword)
                }
            }
            let pairs = Array(ws).shuffled().map { w in
                let target = pool.first(where: { $0.headword == w }) ?? word
                return MatchPair(word: w, definition: Self.firstLine(target.definitionCn))
            }
            if pairs.count == 4, Set(pairs.map(\.definition)).count == 4 {
                matchAnswers = [:]
                question = Question(kind: kind, word: word, prompt: "将单词与释义配对", options: [], correctIndex: 0,
                                    spellHint: "", pairs: pairs)
            } else { fallbackToEnToCn() }
        case .combo:
            // 限时连击：60 秒连续作答基础题型（复用 timedTrial 限时，连击伤害由 resolveAnswer 处理）
            let baseKinds: [QuestionKind] = [.enToCn, .cnToEn, .spell]
            let baseKind = baseKinds.randomElement() ?? .enToCn
            // 递归生成基础题（仅限这些题型）
            if let q = baseQuestion(of: baseKind, word: word, cnDef: cnDef) {
                question = q
            } else { fallbackToEnToCn() }
        // MARK: - S3.5 考试题型
        case .judge:
            // 判断正误：词 + 说法，判对错（50% 正确说法 / 50% 其他词释义）
            let isTrue = Bool.random()
            let other = pool.randomElement().map { Self.firstLine($0.definitionCn) } ?? cnDef
            let claim = isTrue ? cnDef : other
            question = Question(kind: kind, word: word,
                                prompt: "「\(word.headword)」意为「\(claim)」？",
                                options: ["✅ 正确", "❌ 错误"], correctIndex: isTrue ? 0 : 1, spellHint: "")
        case .scramble:
            // 乱序组词：打乱字母，选正确排列
            let scrambled = String(word.headword.shuffled())
            if scrambled.lowercased() != word.headword.lowercased() {
                var opts = Array(Set(pool.map(\.headword).filter { $0.lowercased() != word.headword.lowercased() })
                    .shuffled().prefix(3))
                let index = Int.random(in: 0...opts.count)
                opts.insert(word.headword, at: index)
                question = Question(kind: kind, word: word, prompt: "乱序：\(scrambled)",
                                    options: opts, correctIndex: index, spellHint: "")
            } else { fallbackToEnToCn() }
        case .synonym:
            // 同义替换：选同义词（复用趣味记词同义词数据）
            if let syns = WordMemoryService.shared.synonyms(for: word.headword), !syns.isEmpty {
                let correct = syns.randomElement()!
                var opts = Set<String>()
                opts.insert(correct)
                for _ in 0..<8 {
                    if let o = pool.randomElement(), opts.count < 4 {
                        opts.insert(o.headword)
                    }
                }
                var options = Array(opts).shuffled()
                let ci = options.firstIndex(of: correct) ?? 0
                question = Question(kind: kind, word: word, prompt: "\(word.headword) 的同义词是？",
                                    options: options, correctIndex: ci, spellHint: "")
            } else { fallbackToEnToCn() }
        case .listenSpell:
            // 听音拼写：TTS 朗读 + 首字母提示
            let first = word.headword.prefix(1)
            question = Question(kind: kind, word: word, prompt: cnDef, options: [], correctIndex: 0,
                                spellHint: "提示：首字母 \(first) · 共 \(word.headword.count) 个字母")
            SpeechService.shared.speak(word.headword)
        case .fillBlank:
            // 选词填空：例句挖空选词（干扰项为词库其他词）
            if let sentence = WordMemoryService.shared.sentences(for: word.headword)?.first,
               sentence.lowercased().contains(word.headword.lowercased()) {
                let blanked = sentence.replacingOccurrences(of: word.headword, with: "____", options: .caseInsensitive)
                var opts = Array(Set(pool.map(\.headword).filter { $0.lowercased() != word.headword.lowercased() })
                    .shuffled().prefix(3))
                let index = Int.random(in: 0...opts.count)
                opts.insert(word.headword, at: index)
                question = Question(kind: kind, word: word, prompt: blanked, options: opts, correctIndex: index, spellHint: "")
            } else { fallbackToEnToCn() }
        case .sentenceMatch:
            // 例句配对：4 词 × 4 例句
            var ws = Set<String>()
            ws.insert(word.headword)
            for _ in 0..<8 {
                if let o = pool.randomElement(), ws.count < 4 {
                    ws.insert(o.headword)
                }
            }
            var pairs: [MatchPair] = []
            for w in ws {
                if let sentence = WordMemoryService.shared.sentences(for: w)?.first {
                    pairs.append(MatchPair(word: w, definition: sentence))
                }
            }
            if pairs.count == 4, Set(pairs.map(\.definition)).count == 4 {
                matchAnswers = [:]
                question = Question(kind: kind, word: word, prompt: "将单词与例句配对", options: [], correctIndex: 0,
                                    spellHint: "", pairs: pairs)
            } else { fallbackToEnToCn() }
        }
        spellInput = ""
        matchAnswers = [:]
        self.battle?.lastAnswerCorrect = nil
        self.battle?.chosenIndex = nil
    }

    /// 解析 exchange 字段（d:did/p:done/i:doing/3:does）→ [(标签, 变形)]
    private func parseExchange(_ exchange: String) -> [(String, String)] {
        let labels: [String: String] = ["d": "过去式", "p": "过去分词", "i": "现在分词",
                                         "3": "第三人称", "s": "复数", "1": "比较级", "2": "最高级", "0": "复数/原形"]
        return exchange.split(separator: "/").compactMap { seg in
            let parts = seg.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let key = String(parts[0]), val = String(parts[1])
            return labels[key].map { ($0, val) }
        }.filter { !$0.1.isEmpty }
    }

    /// 出题兜底：英选中四选一
    private func fallbackToEnToCn() {
        guard let battle else { return }
        let candidates = questionPool(for: battle.node)
        guard let w = candidates.randomElement() else { return }
        let cnDef = Self.firstLine(w.definitionCn)
        var opts = Array(Set(pool.map { Self.firstLine($0.definitionCn) }.filter { $0 != cnDef }).shuffled().prefix(3))
        let idx = Int.random(in: 0...opts.count)
        opts.insert(cnDef, at: idx)
        question = Question(kind: .enToCn, word: w, prompt: w.headword, options: opts, correctIndex: idx, spellHint: "")
    }

    /// 生成基础题型题目（供限时连击等复用）
    private func baseQuestion(of kind: QuestionKind, word: Word, cnDef: String) -> Question? {
        switch kind {
        case .enToCn:
            var opts = Array(Set(pool.map { Self.firstLine($0.definitionCn) }.filter { $0 != cnDef }).shuffled().prefix(3))
            let idx = Int.random(in: 0...opts.count)
            opts.insert(cnDef, at: idx)
            return Question(kind: .enToCn, word: word, prompt: word.headword, options: opts, correctIndex: idx, spellHint: "")
        case .cnToEn:
            var opts = Array(Set(pool.map(\.headword).filter { $0 != word.headword }).shuffled().prefix(3))
            let idx = Int.random(in: 0...opts.count)
            opts.insert(word.headword, at: idx)
            return Question(kind: .cnToEn, word: word, prompt: cnDef, options: opts, correctIndex: idx, spellHint: "")
        case .spell:
            let first = word.headword.prefix(1)
            return Question(kind: .spell, word: word, prompt: cnDef, options: [], correctIndex: 0,
                            spellHint: "提示：首字母 \(first) · 共 \(word.headword.count) 个字母")
        default:
            return nil
        }
    }

    // MARK: - 词义连线交互

    /// 词义连线：点击配对（词 ↔ 释义；再点取消）
    func selectMatchPair(word: String, definition: String) {
        guard phase == .battle, let question, question.kind == .match else { return }
        if matchAnswers[word] == definition {
            matchAnswers.removeValue(forKey: word)
        } else {
            matchAnswers[word] = definition
        }
        // 4 词全部配对且释义不重复 → 自动判分
        if matchAnswers.count == question.pairs.count, Set(matchAnswers.values).count == question.pairs.count {
            resolveMatch()
        }
    }

    private func resolveMatch() {
        guard let question, question.kind == .match else { return }
        let correct = question.pairs.allSatisfy { matchAnswers[$0.word] == $0.definition }
        matchAnswers = [:]
        resolveAnswer(correct: correct, chosen: nil)
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
        if groupTotal > 0 { groupAnswered += 1 }   // S4：组内答题统计（破绽判定）
        let skillOn = !battle.skillsDisabled       // 鸡哥封印时为 false

        if correct {
            battle.combo += 1
            // S4 完美判定：连击 ≥3 的答对 = 完美（伤害 ×1.5）
            let isPerfect = battle.combo >= 3
            battle.perfect = isPerfect
            if isPerfect, groupTotal > 0 { groupPerfectCount += 1 }
            var damage = (skillOn && hero == .gambler) ? 2 : 1
            if skillOn && hero == .mage && battle.combo >= 3 { damage += 1 }
            damage += equipEffects.damage
            if hero == .demon { damage += max(0, -hp) / 3 }   // 不死不灭：负血越深攻击越狂
            if demonMode { damage += 2 }               // 魔功：命中伤害 +2
            if isPerfect { damage = Int(Double(damage) * 1.5) }   // 完美：伤害 ×1.5
            // 事件 buff：词灵求救/天降奇遇伤害加成（组内生效）
            if groupTotal > 0 { damage += eventDamageBuff }
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
            // 连对 5 题回血 +1（化神 10 境起，不受职业技能影响）
            if stage.index >= 10, battle.combo >= 5, battle.combo % 5 == 0 {
                hp = min(maxHP, hp + 1)
            }
            if hero == .demon {
                hp = min(0, hp + 1)          // 魔气回涌：答对回升 1 点（至 0）
            }
            // 宠物/精灵技能随机触发（按状态概率）
            if battle.enemyHP > 0, let skillMsg = activatePetSpriteSkill(battle: &battle) {
                toast = (toast ?? "") + " " + skillMsg
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
                // 境界压制：答错额外 +1（事件 debuff，组内生效）
                if groupTotal > 0 { hit += eventPenaltyBuff }
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
            // 答错时宠物/精灵承受 1 点伤害（0 血自动离去）
            damagePetSpriteOnWrong()
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

        // 关卡组连战：组内还有子关卡 → 显示组内选择（继续/休息/突击），不再自动连战
        if groupTotal > 0, groupIndex < groupTotal {
            makeGroupChoices()
            phase = .map
            toast = messages.joined(separator: "  ")
            return
        }
        // 关卡组全部通关
        if groupTotal > 0 {
            finishGroup(messages: &messages)
            // 词妖潮事件：组完成不推进楼层，直接回地图
            if eventWordTide {
                eventWordTide = false
                proceedToMap(messages: messages)
                return
            }
        }
        // 事件战斗结算（魔音灌耳/心魔幻境）
        if eventEarBomb {
            eventEarBomb = false
            let correct = battle.answered
            if correct >= 2 {
                coins += 15
                messages.append("🔊 抵御魔音，💰 +15！")
            } else {
                hp = hero == .demon ? hp - 4 : max(1, hp - 4)
                messages.append("🔊 魔音入脑，❤️ -4！")
            }
            proceedToMap(messages: messages)
            return
        }
        if eventMindTrial {
            eventMindTrial = false
            let correct = battle.answered
            if correct > 0 {
                let reward = correct * 5
                coins += reward
                messages.append("🧠 心魔试炼答对 \(correct) 题，💰 +\(reward)！")
            } else {
                hp = hero == .demon ? hp - 6 : max(1, hp - 6)
                messages.append("🧠 心魔溃败，❤️ -6！")
            }
            proceedToMap(messages: messages)
            return
        }

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
            proceedToMap(messages: messages)
        }
    }

    // MARK: - 组内选择（每战后玩家选择继续/休息/突击）

    /// 下一子关卡的节点类型（用于显示选择预览）
    var nextSubBattleNode: NodeType? {
        guard groupTotal > 0, groupIndex < groupTotal else { return nil }
        return groupStages[groupIndex]
    }

    /// 预览子关卡的敌人信息（用于组内选择卡片，确定性返回第一个小怪）
    func previewSubBattle(_ node: NodeType) -> (name: String, icon: String) {
        switch node {
        case .elite: return (stage.eliteName, "flame.fill")
        case .timedTrial: return ("秘境守卫", "timer")
        case .battle(let cat, _):
            let minion = stage.minions.first ?? (name: "词妖", icon: "questionmark")
            return (cat != nil ? "\(minion.name)见习" : minion.name, minion.icon)
        default: return ("未知", "questionmark")
        }
    }

    /// 最后一关的节点类型（用于"突击收尾"预览）
    var rushSubBattleNode: NodeType? {
        guard groupTotal > 0, groupTotal > 0 else { return nil }
        return groupStages[groupTotal - 1]
    }

    /// 生成组内选择：每场子关卡胜利后展示（继续/休息/突击）
    private func makeGroupChoices() {
        guard groupTotal > 0, groupIndex < groupTotal else {
            groupChoices = []
            return
        }
        self.choices = []   // 组内休整期间隐藏地图旧节点，防止误点破坏组流程
        var choices: [GroupChoice] = [.normal]
        // 休息：血量越低出现概率越高（封顶 10%），且掉血 ≥30% 才可能触发
        let hurtEnough = hero == .demon ? hp <= -3 : hp * 10 <= maxHP * 7
        let restChance = hero == .demon
            ? min(10, max(1, -hp * 2))                                      // 魔修按负血深度
            : min(10, max(1, Int((1 - Double(hp) / Double(max(1, maxHP))) * 12)))   // 普通按掉血比例
        if hurtEnough, Int.random(in: 0..<100) < restChance {
            choices.append(.rest)
        }
        // 突击：至少还有 2 关以上（跳过中间直达最后一关）
        if groupIndex + 1 < groupTotal {
            choices.append(.rush)
        }
        groupChoices = choices
    }

    /// 选择组内行动：继续战斗 / 调息恢复 / 突击收尾
    func chooseGroupChoice(_ choice: GroupChoice) {
        guard phase == .map, groupTotal > 0, groupIndex < groupTotal, !groupChoices.isEmpty else { return }
        groupChoices = []

        switch choice {
        case .normal:
            groupIndex += 1
            advanceGroup()
        case .rest:
            // 调息：回血 +5 后继续到下一关
            hp = hero == .demon ? min(0, hp + 5) : min(maxHP, hp + 5)
            toast = hero == .demon ? "🔥 调息回魔 +5" : "💧 调息恢复 +5"
            groupIndex += 1
            if groupIndex <= groupTotal {
                advanceGroup()
            } else {
                // 休息后无后续关卡：直接组通关
                var msgs: [String] = ["💧 调息恢复 +5"]
                finishGroup(messages: &msgs)
                floor += 1
                proceedToMap(messages: msgs)
            }
        case .rush:
            // 突击：跳到最后一关（组首领/精英）
            groupIndex = groupTotal
            advanceGroup()
        }
    }

    /// 组内推进（无消息）：直接进入当前子关卡
    private func advanceGroup() {
        var messages: [String] = []
        advanceGroup(messages: &messages)
        if phase == .battle, !messages.isEmpty {
            toast = messages.joined(separator: "  ")
        }
    }

    /// 组内推进到当前子关卡：战斗直接开战；灵泉自动回血；商人弹商店
    private func advanceGroup(messages: inout [String]) {
        switch groupStages[groupIndex - 1] {
        case .rest:
            // 组内灵泉：自动回血，然后显示组内选择
            hp = min(maxHP, hp + 15)
            // 宠物/精灵同享滋养：各恢复一半生命
            if petMaxHP > 0 { petHP = min(petMaxHP, petHP + max(1, petMaxHP / 2)) }
            if spriteMaxHP > 0 { spriteHP = min(spriteMaxHP, spriteHP + max(1, spriteMaxHP / 2)) }
            let msg = hero == .demon ? "🔥 魔气滋养 +15" : "💧 组内灵泉涤体 +15"
            messages.append(msg)
            persistAll()          // 宠物/精灵生命持久化
            groupIndex += 1
            if groupIndex < groupTotal {
                makeGroupChoices()
                phase = .map
                toast = messages.joined(separator: "  ") + "  " + msg
            } else {
                // 灵泉收尾：直接组通关回地图
                finishGroup(messages: &messages)
                floor += 1
                proceedToMap(messages: messages)
            }
        case .merchant:
            // 组内商人：弹商店，离开后继续组内下一关（leaveMerchant）
            merchantOffers = rollItems(count: 3, stageGate: stage.index, excludeOwned: true)
            phase = .merchant
            toast = "🛒 组内偶遇神秘商人"
        default:
            enterBattle(groupStages[groupIndex - 1], mode: .standard, canRetreat: groupCanRetreat)
        }
    }

    /// 关卡组通关：小额固定奖励 + 高概率掉落 + 重置组状态（不自动回血，回血需选择休息）
    private func finishGroup(messages: inout [String]) {
        // 组通关奖励随段位递增：前期 2 → 后期 6
        let tierBonus = min(6, 2 + stage.index / 4)
        let bonus = tierBonus
        coins += bonus
        messages.append("🏆 关卡组通关 +\(bonus)")
        // 秘路揭晓
        if currentRoute == .mystery {
            messages.append(groupRewardMult >= 2 ? "🎲 秘路大赚！" : (groupRewardMult <= 0.5 ? "💸 秘路血亏……" : "🎲 秘路平淡"))
        }
        // 组通关：高概率掉落（50%）；险路高品阶权重提升
        if Int.random(in: 0..<100) < 50,
           let drop = rollItems(count: 1, stageGate: stage.index, excludeOwned: false, tierBoost: groupTierBoost).first {
            gainItem(drop)
            if let last = toast { messages.append(last) }
        }
        // 组通关后宠物/精灵恢复三分之一生命
        if petMaxHP > 0 { petHP = min(petMaxHP, petHP + max(1, petMaxHP / 3)) }
        if spriteMaxHP > 0 { spriteHP = min(spriteMaxHP, spriteHP + max(1, spriteMaxHP / 3)) }
        persistAll()          // 宠物/精灵生命持久化
        resetGroup()
        usedRoutes.removeAll()
        branchRoutes = []
    }

    /// 节点/关卡组通关：回到地图（楼层已推进）
    private func proceedToMap(messages: [String]) {
        shortcutPending = false
        saveRun()
        makeChoices()
        phase = .map
        toast = messages.joined(separator: "  ")
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
        resetGroup()          // 撤退 = 放弃整个关卡组
        persistAll()
        // 撤退不刷新关卡：原样恢复进入战斗前的选择界面（节点或分叉口路线）
        choices = preGroupChoices
        branchRoutes = preGroupRoutes
        preGroupChoices = []
        preGroupRoutes = []
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
            // 💰 劫匪拦路：失败扣 30% 金币，不死亡
            if eventRobber {
                eventRobber = false
                resetGroup()
                let loss = max(1, coins * 30 / 100)
                coins -= loss
                persistWealth()
                stopTimer()
                advanceTask?.cancel()
                floor += 1
                saveRun()
                makeChoices()
                phase = .map
                toast = "💰 劫匪抢走了 \(loss) 金币后扬长而去…"
                return
            }
            // 🌙 月光宝盒：死亡时自动发动——随机回到当前境界任一节点（消耗 1 个）
            if let idx = inventory.firstIndex(where: { $0.id == "moonlightBox" }) {
                inventory.remove(at: idx)
                persistWealth()
                resetGroup()                        // 放弃当前关卡组
                let target = Int.random(in: 1...max(1, stage.floors))
                floor = target
                usedCategoryIds = []
                recentWordIds = []
                branchFloors = Self.makeBranchFloors(floors: stage.floors)
                usedRoutes = []
                branchRoutes = []
                lastRestFloor = -1
                shortcutPending = false
                if hero == .demon {
                    hp = max(-10, hp + 40)          // 魔修：负血拉回（反噬身亡后回魂）
                } else {
                    hp = max(1, maxHP / 2)          // 普通：半血复生
                }
                saveRun()
                makeChoices()
                phase = .map
                toast = "🌙 月光宝盒发动！时空倒流，回到第 \(target) 层"
                return
            }
            resetGroup()            // 组内死亡：放弃整个关卡组
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
        branchFloors = Self.makeBranchFloors(floors: stage.floors)   // 新境重新生成分叉口
        usedRoutes = []
        branchRoutes = []
        lastRestFloor = -1          // 新境灵泉冷却重置
        lastEventSpringFloor = -1
        shortcutPending = false
        if hero != .demon { maxHP += 5 }  // 境界突破，根基更厚（魔修恒 0）
        // 突破回复按段位递减：最多 20%（初入仙途 20% → 问道巅峰 12%）
        let breakRatio: Double
        if stage.index <= 4 { breakRatio = 0.2 }
        else if stage.index <= 9 { breakRatio = 0.18 }
        else if stage.index <= 13 { breakRatio = 0.15 }
        else { breakRatio = 0.12 }
        hp = min(hero == .demon ? 0 : maxHP, hp + max(5, Int(Double(maxHP) * breakRatio)))
        saveRun()
    }

    /// 在突破页点“继续”：状态已在 finishRun 里推进到下一境，这里只需进入地图
    func continueToNextStage() {
        makeChoices()
        phase = .map
    }
}
