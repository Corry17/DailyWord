import Foundation
import SwiftUI
import DailyWordCore

// MARK: - 身份（职业）

enum HeroClass: String, CaseIterable, Identifiable {
    case knight, mage, rogue, healer, gambler, demon   // 魔修（隐藏职业）

    var id: String { rawValue }

    var name: String {
        switch self {
        case .knight: return "词剑士"
        case .mage: return "词法师"
        case .rogue: return "词行者"
        case .healer: return "词医者"
        case .gambler: return "词赌徒"
        case .demon: return "魔修"
        }
    }

    var icon: String {
        switch self {
        case .knight: return "shield.lefthalf.filled"
        case .mage: return "wand.and.stars"
        case .rogue: return "figure.walk.motion"
        case .healer: return "cross.case.fill"
        case .gambler: return "die.face.5.fill"
        case .demon: return "flame.fill"
        }
    }

    var maxHP: Int {
        switch self {
        case .knight: return 34
        case .mage: return 26
        case .rogue: return 28
        case .healer: return 30
        case .gambler: return 22
        case .demon: return 40
        }
    }

    var skillTitle: String {
        switch self {
        case .knight: return "格挡"
        case .mage: return "咒语连击 & 凝时"
        case .rogue: return "妙手"
        case .healer: return "回响治疗"
        case .gambler: return "孤注一掷"
        case .demon: return "魔焰"
        }
    }

    var skillDesc: String {
        switch self {
        case .knight: return "血厚耐揍；每场战斗第一次答错不扣血"
        case .mage: return "连续答对 3 题起每击伤害 +1；限时战时限 +15 秒"
        case .rogue: return "每场战斗可「跳过」一题，不扣血不计错"
        case .healer: return "每连续答对 2 题回复 1 点生命"
        case .gambler: return "每次命中伤害 ×2，但挨打也多掉 1 点血"
        case .demon: return "血厚耐打；每击伤害 +1，连续答对 3 题额外 +2"
        }
    }
}

// MARK: - 难度（学习情况自动判定）

struct TowerDifficulty: Equatable {
    let name: String
    let icon: String
    let enemyHPMod: Int
    let attackMod: Int
    let bossTimeMod: Int

    static let apprentice = TowerDifficulty(name: "学徒", icon: "leaf", enemyHPMod: -1, attackMod: -1, bossTimeMod: 15)
    static let adventurer = TowerDifficulty(name: "冒险者", icon: "figure.hiking", enemyHPMod: 0, attackMod: 0, bossTimeMod: 0)
    static let master = TowerDifficulty(name: "大师", icon: "crown", enemyHPMod: 2, attackMod: 1, bossTimeMod: -10)

    static func evaluate(learned: Int, mastered: Int) -> TowerDifficulty {
        if learned >= 200 || mastered >= 30 { return .master }
        if learned >= 50 { return .adventurer }
        return .apprentice
    }
}

// MARK: - 单词分类

struct WordCategory: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    let posMarks: [String]
    let keywords: [String]

    func matches(_ word: Word) -> Bool {
        matches(definitionLowercased: word.definitionCn.lowercased())
    }

    /// 用已小写的释义判断（批量构建缓存时避免重复 lowercased）
    func matches(definitionLowercased lower: String) -> Bool {
        if !posMarks.isEmpty {
            return posMarks.contains { lower.contains($0) }
        }
        return keywords.contains { lower.contains($0) }
    }

    static func == (lhs: WordCategory, rhs: WordCategory) -> Bool { lhs.id == rhs.id }

    static let all: [WordCategory] = [
        WordCategory(id: "verb", label: "动词", icon: "figure.run", posMarks: ["v.", "vt.", "vi."], keywords: []),
        WordCategory(id: "noun", label: "名词", icon: "cube", posMarks: ["n."], keywords: []),
        WordCategory(id: "adj", label: "形容词", icon: "paintpalette", posMarks: ["a.", "adj."], keywords: []),
        WordCategory(id: "animal", label: "动物", icon: "pawprint.fill", posMarks: [],
                     keywords: ["猫", "狗", "鸟", "鱼", "马", "牛", "羊", "猪", "狮", "虎", "熊", "鼠", "兔", "猴", "昆虫", "动物", "蛇", "鸡", "鸭", "兽"]),
        WordCategory(id: "weather", label: "天气", icon: "cloud.sun.fill", posMarks: [],
                     keywords: ["雨", "雪", "风", "云", "雷", "晴", "雾", "风暴", "气候", "天气", "冰"]),
        WordCategory(id: "emotion", label: "情绪", icon: "face.smiling", posMarks: [],
                     keywords: ["怒", "悲", "惧", "恐", "焦虑", "快乐", "高兴", "伤心", "情绪", "感情", "惊", "羞", "忧", "喜"]),
        WordCategory(id: "food", label: "食物", icon: "fork.knife", posMarks: [],
                     keywords: ["食物", "吃", "肉", "菜", "水果", "米", "面包", "汤", "糖", "盐", "饮", "酒", "茶", "咖啡", "餐"]),
        WordCategory(id: "body", label: "身体", icon: "figure.stand", posMarks: [],
                     keywords: ["头", "手", "脚", "眼", "耳", "鼻", "嘴", "心脏", "血", "骨", "肌肉", "身体", "皮肤", "牙"]),
        WordCategory(id: "color", label: "颜色", icon: "paintbrush.fill", posMarks: [],
                     keywords: ["红", "蓝", "绿", "黄", "紫", "粉红", "灰", "棕", "颜色"]),
        WordCategory(id: "time", label: "时间", icon: "clock.fill", posMarks: [],
                     keywords: ["时间", "年", "月", "星期", "小时", "分钟", "季", "早晨", "夜", "黄昏", "世纪", "永久"]),
        WordCategory(id: "place", label: "地点", icon: "mappin.circle.fill", posMarks: [],
                     keywords: ["地方", "城市", "国家", "村", "学校", "医院", "商店", "建筑", "街", "公园", "地区"]),
        WordCategory(id: "nature", label: "自然", icon: "leaf.fill", posMarks: [],
                     keywords: ["山", "河", "海", "湖", "树", "花", "草", "森林", "岛", "沙漠", "石", "土地"]),
        WordCategory(id: "transport", label: "交通", icon: "car.fill", posMarks: [],
                     keywords: ["车", "船", "飞机", "火车", "自行车", "交通", "公路", "铁路", "航"]),
        WordCategory(id: "clothing", label: "衣物", icon: "tshirt.fill", posMarks: [],
                     keywords: ["衣", "裤", "帽", "鞋", "裙", "袜", "穿"]),
        WordCategory(id: "family", label: "家庭", icon: "person.2.fill", posMarks: [],
                     keywords: ["父", "母", "兄", "姐", "妹", "弟", "家庭", "亲戚", "叔", "婚", "祖"]),
        WordCategory(id: "work", label: "职业", icon: "briefcase.fill", posMarks: [],
                     keywords: ["医生", "教师", "律师", "工人", "农民", "职业", "警察", "司机", "秘书", "工程师", "作家"]),
        WordCategory(id: "study", label: "学习", icon: "book.fill", posMarks: [],
                     keywords: ["学习", "书", "读", "写", "考试", "课程", "知识", "教育", "大学", "科学"]),
        WordCategory(id: "sports", label: "运动", icon: "sportscourt.fill", posMarks: [],
                     keywords: ["跑", "跳", "球", "游泳", "运动", "比赛", "体育"]),
        WordCategory(id: "money", label: "财物", icon: "dollarsign.circle.fill", posMarks: [],
                     keywords: ["钱", "价格", "买", "卖", "支付", "财", "贸易", "市场", "银行", "经济"]),
        WordCategory(id: "sound", label: "声音", icon: "speaker.wave.3.fill", posMarks: [],
                     keywords: ["声", "音", "唱", "叫", "响", "音乐", "噪"]),
        WordCategory(id: "furniture", label: "家具", icon: "bed.double.fill", posMarks: [],
                     keywords: ["桌", "椅", "床", "柜", "门", "窗", "灯", "家具", "沙", "橱", "帘", "垫"]),
        WordCategory(id: "electronics", label: "电子", icon: "desktopcomputer", posMarks: [],
                     keywords: ["电脑", "手机", "网络", "软件", "硬件", "电子", "信息", "数据", "设备", "机器"]),
        WordCategory(id: "building", label: "建筑", icon: "building.2.fill", posMarks: [],
                     keywords: ["建筑", "房", "屋", "墙", "桥", "塔", "宫殿", "庙", "寺", "城"]),
        WordCategory(id: "music", label: "音乐", icon: "music.note.list", posMarks: [],
                     keywords: ["音乐", "歌", "曲", "琴", "鼓", "乐器", "演唱", "声乐", "旋律", "节奏", "舞"]),
        WordCategory(id: "health", label: "健康", icon: "heart.circle.fill", posMarks: [],
                     keywords: ["医", "药", "病", "治疗", "健康", "手术", "痛", "锻炼", "健身", "营养"]),
        WordCategory(id: "politics", label: "政治", icon: "building.columns.fill", posMarks: [],
                     keywords: ["政治", "政府", "选举", "政策", "民主", "法律", "议会", "权利", "管理", "制度"]),
        WordCategory(id: "military", label: "军事", icon: "shield.ranged.fill", posMarks: [],
                     keywords: ["军事", "战争", "军队", "武器", "战斗", "进攻", "防御", "战略", "士兵", "冲突"]),
        WordCategory(id: "tech", label: "科技", icon: "gearshape.2.fill", posMarks: [],
                     keywords: ["科技", "技术", "科学", "创新", "发明", "实验室", "雷达", "卫星", "工业", "工程"]),
        WordCategory(id: "art", label: "艺术", icon: "paintpalette.fill", posMarks: [],
                     keywords: ["艺术", "绘画", "雕塑", "美学", "展览", "风格", "设计", "创造", "工艺"]),
        WordCategory(id: "travel", label: "旅行", icon: "airplane.departure", posMarks: [],
                     keywords: ["旅行", "旅游", "度假", "风景", "出发", "参观", "游览", "目的地", "旅程"])
    ]
}

// MARK: - 题型

enum QuestionKind: String, CaseIterable {
    case enToCn, cnToEn, spell, engDef
    // S3 新题型
    case listen       // 听音辨词：TTS 朗读后 4 选 1
    case formChange   // 词形变换：给原形选变形
    case match        // 词义连线：4 词 × 4 释义配对
    case cloze        // 完形填空：例句挖空选词
    case rootMerge    // 词根拆解：碎片组合成词
    case combo        // 限时连击：60 秒连续作答（基础题型）
    // S3.5 考试题型
    case judge        // 判断正误：词 + 说法，判对错
    case scramble     // 乱序组词：打乱字母选正确排列
    case synonym      // 同义替换：句中划线词选同义词
    case listenSpell  // 听音拼写：TTS 朗读 + 首字母提示拼写
    case fillBlank    // 选词填空：段落挖空选词
    case sentenceMatch // 例句配对：4 词 × 4 例句

    var label: String {
        switch self {
        case .enToCn: return "英选中"
        case .cnToEn: return "中选英"
        case .spell: return "拼写"
        case .engDef: return "英释选词"
        case .listen: return "听音辨义"
        case .formChange: return "词形变换"
        case .match: return "词义连线"
        case .cloze: return "完形填空"
        case .rootMerge: return "词根拆解"
        case .combo: return "限时连击"
        case .judge: return "判断正误"
        case .scramble: return "乱序组词"
        case .synonym: return "同义替换"
        case .listenSpell: return "听音拼写"
        case .fillBlank: return "选词填空"
        case .sentenceMatch: return "例句配对"
        }
    }

    var icon: String {
        switch self {
        case .enToCn: return "a.square"
        case .cnToEn: return "character.square"
        case .spell: return "keyboard"
        case .engDef: return "text.book.closed"
        case .listen: return "ear"
        case .formChange: return "pencil.and.outline"
        case .match: return "arrow.left.arrow.right.square"
        case .cloze: return "text.insert"
        case .rootMerge: return "puzzlepiece.extension"
        case .combo: return "flame"
        case .judge: return "checkmark.seal"
        case .scramble: return "shuffle"
        case .synonym: return "arrow.triangle.2.circlepath"
        case .listenSpell: return "ear.badge.checkmark"
        case .fillBlank: return "text.badge.plus"
        case .sentenceMatch: return "text.quote"
        }
    }

    /// 新题型随境界逐个开放：2 境起每境解锁一种（新手期循序渐进，避免一次性涌入）
    /// 考试题型：5 境筑基 = 判断正误/乱序组词；6 境金丹 = 同义替换/听音拼写；8 境化神 = 选词填空/例句配对
    static func available(stageIndex: Int) -> [QuestionKind] {
        var kinds: [QuestionKind] = [.enToCn, .cnToEn, .spell]
        if stageIndex >= 2 { kinds.append(.engDef) }        // 炼气初期
        if stageIndex >= 3 { kinds.append(.listen) }        // 炼气中期
        if stageIndex >= 4 { kinds.append(.combo) }         // 炼气后期
        if stageIndex >= 5 { kinds.append(.formChange) }    // 筑基
        if stageIndex >= 5 { kinds.append(.judge) }         // 筑基 · 考试
        if stageIndex >= 5 { kinds.append(.scramble) }      // 筑基 · 考试
        if stageIndex >= 6 { kinds.append(.cloze) }         // 金丹
        if stageIndex >= 6 { kinds.append(.synonym) }       // 金丹 · 考试
        if stageIndex >= 6 { kinds.append(.listenSpell) }   // 金丹 · 考试
        if stageIndex >= 7 { kinds.append(.match) }         // 元婴
        if stageIndex >= 8 { kinds.append(.rootMerge) }     // 化神
        if stageIndex >= 8 { kinds.append(.fillBlank) }     // 化神 · 考试
        if stageIndex >= 8 { kinds.append(.sentenceMatch) } // 化神 · 考试
        return kinds
    }
}

// MARK: - 词义连线配对

struct MatchPair: Equatable {
    let word: String
    let definition: String
}

// MARK: - 地图节点

enum NodeType: Equatable {
    case battle(category: WordCategory?, kind: QuestionKind)
    case elite(kind: QuestionKind)
    case timedTrial(kind: QuestionKind)
    case rest
    case merchant
    case boss

    var title: String {
        switch self {
        case .battle(let category, let kind):
            return category.map { "\($0.label)试炼 · \(kind.label)" } ?? "遭遇战 · \(kind.label)"
        case .elite(let kind): return "精英战 · \(kind.label)"
        case .timedTrial(let kind): return "限时秘境 · \(kind.label)"
        case .rest: return "灵泉休息"
        case .merchant: return "神秘商人"
        case .boss: return "境主之战"
        }
    }

    var icon: String {
        switch self {
        case .battle(let category, let kind): return category?.icon ?? kind.icon
        case .elite: return "flame"
        case .timedTrial: return "timer"
        case .rest: return "drop.fill"
        case .merchant: return "cart.fill"
        case .boss: return "crown.fill"
        }
    }

    var desc: String {
        switch self {
        case .battle(let category, _):
            return category != nil ? "主题词战斗，敌人稍弱" : "随机单词，答对进攻、答错挨打"
        case .elite: return "更强的敌人——胜利有额外金币"
        case .timedTrial: return "限时击败敌人，重赏金币！"
        case .rest: return "恢复 10 点生命"
        case .merchant: return "用金币换取装备与丹药"
        case .boss: return "限时决战！时间耗尽即倒下"
        }
    }
}

// MARK: - 分叉口路线（S2：每个分叉口 2~3 条候选路线）

enum RouteType: Equatable, Hashable {
    case perilous   // 险路：⚔️ 强敌
    case steady     // 平路：🛡️ 稳妥
    case mystery    // 秘路：❓ 未知

    var title: String {
        switch self {
        case .perilous: return "险路"
        case .steady: return "平路"
        case .mystery: return "秘路"
        }
    }

    var badge: String {
        switch self {
        case .perilous: return "⚔️ 强敌"
        case .steady: return "🛡️ 稳妥"
        case .mystery: return "❓ 未知"
        }
    }

    var icon: String {
        switch self {
        case .perilous: return "bolt.fill"
        case .steady: return "shield.fill"
        case .mystery: return "questionmark.circle.fill"
        }
    }

    /// 难度星级（秘路未知，用问号）
    var stars: String {
        switch self {
        case .perilous: return "★★★"
        case .steady: return "★★"
        case .mystery: return "？"
        }
    }

    /// 组内关数（秘路随机 2~4 关）
    var stageCountText: String {
        switch self {
        case .perilous: return "2 关"
        case .steady: return "3 关"
        case .mystery: return "2~4 关"
        }
    }

    /// 预期收益描述（秘路隐藏）
    var rewardText: String {
        switch self {
        case .perilous: return "组奖励 ×2 · 高品阶掉落 ↑"
        case .steady: return "标准奖励"
        case .mystery: return "？"
        }
    }

    var desc: String {
        switch self {
        case .perilous: return "敌人更强（+30% 血攻），但组奖励翻倍、掉落更好"
        case .steady: return "标准强度，稳步推进"
        case .mystery: return "一切未知——可能大赚，也可能血亏"
        }
    }
}

// MARK: - 组内选择（S2+：每战后选择继续/休息/突击）

enum GroupChoice: Equatable, Hashable {
    case normal    // 继续战斗：进入下一子关卡
    case rest      // 调息恢复 +5
    case rush      // 突击收尾：跳过中间，直达最后一关
}

// MARK: - 突发事件

enum TowerEvent: Equatable {
    case forced, opportunity, trial
    // 新事件
    case spring         // 灵泉现世：可选回血
    case robber         // 劫匪拦路：强制战斗，失败扣 30% 金币
    case ruins          // 上古遗迹：三选一宝箱
    case wordTide       // 词妖潮：连续 3 场小怪战
    // 剩余 6 种
    case earBomb        // 魔音灌耳：3 道听音题
    case mindTrial      // 心魔幻境：5 道连续题
    case forkRoad       // 迷雾岔路：两条未知路
    case wordSpirit     // 词灵求救：花 30 金加 buff
    case luckFall       // 天降奇遇：免费 buff
    case realmSuppress  // 境界压制：本组答错 +1

    var title: String {
        switch self {
        case .forced: return "⚠️ 妖潮突袭！"
        case .opportunity: return "✨ 秘宝洞窟"
        case .trial: return "💡 灵光乍现"
        case .spring: return "💧 灵泉现世"
        case .robber: return "💰 劫匪拦路"
        case .ruins: return "🏛️ 上古遗迹"
        case .wordTide: return "🌊 词妖潮"
        case .earBomb: return "🔊 魔音灌耳"
        case .mindTrial: return "🧠 心魔幻境"
        case .forkRoad: return "🌫️ 迷雾岔路"
        case .wordSpirit: return "🧚 词灵求救"
        case .luckFall: return "✨ 天降奇遇"
        case .realmSuppress: return "⚡ 境界压制"
        }
    }

    var desc: String {
        switch self {
        case .forced: return "词妖拦路，避无可避——必须应战！"
        case .opportunity: return "洞中似有秘宝，但守卫凶猛。胜利必得重宝，却也可能沾染诅咒……挑战还是绕行？"
        case .trial: return "一道灵光闪过：20 秒内答对 3 题即得奖励。失败也无损失，试试吗？"
        case .spring: return "一缕灵泉自地底涌出，清澈甘甜——可回复生命，也可绕行继续赶路。"
        case .robber: return "一伙劫匪拦住了去路，狞笑着要你留下买路财——必须应战！若不慎落败，身上金币将折损三成。"
        case .ruins: return "你发现一处上古遗迹，三个宝箱并列而放，但只能打开一个——选错了可能会有陷阱……"
        case .wordTide: return "成群的词妖如潮水般涌来——连续三场恶战！答对率超过六成方可无伤过关。"
        case .earBomb: return "刺耳的魔音灌入脑髓——连续 3 道听音题！答对 2 题即得金币，否则神魂受损扣血 4 点。"
        case .mindTrial: return "心魔幻境将你的心神拉入试炼——连续答 5 题，答对越多的奖励越丰厚，但也可能空手而归反受其伤。"
        case .forkRoad: return "前方出现两条岔路，浓雾弥漫看不清尽头——选一条走吧，未知的命运在等待。"
        case .wordSpirit: return "一只受伤的词灵倒在路边，它说若肯花 30 金币救它，它便在你接下来的战斗中助你一臂之力。"
        case .luckFall: return "一道祥光从天而降，沐浴其中感觉浑身充满了力量——下个节点组获得增益！"
        case .realmSuppress: return "此方天地灵气紊乱，修为受到压制——接下来的关卡组答错惩罚加重！你可以绕开此行省……"
        }
    }
}

// MARK: - Boss 特殊技能（包含梗）

enum BossAbility: Equatable {
    case none
    case disableSkill    // 整局封印职业技能（鸡哥：唱跳rap篮球）
    case doubleHit       // 答错扣双倍血（马保国：闪电五连鞭）
    case timeDrain       // 答错额外流失时间
    case regen           // Boss 每隔几题回血
    case venom           // 毒雾：每次答对后玩家被侵蚀 1 血
    case berserk         // 狂暴：每 3 题攻击 +1，越战越强
    case dodge           // 幻影闪避：30% 概率免疫玩家伤害
    case ironwall        // 铁壁：每 4 题免疫一次伤害
    case lifesteal       // 吸血：答错时 Boss 回复 1 血

    var title: String {
        switch self {
        case .none: return ""
        case .disableSkill: return "唱跳rap篮球"
        case .doubleHit: return "闪电五连鞭"
        case .timeDrain: return "吞噬光阴"
        case .regen: return "不死身法"
        case .venom: return "毒雾漫天"
        case .berserk: return "狂暴之血"
        case .dodge: return "幻影闪避"
        case .ironwall: return "铁壁防御"
        case .lifesteal: return "吸血魔功"
        }
    }

    var desc: String {
        switch self {
        case .none: return ""
        case .disableSkill: return "大招一出，本局你的职业技能全部失效！"
        case .doubleHit: return "年轻人不讲武德——答错时受伤翻倍！"
        case .timeDrain: return "每答错一题，额外流失 5 秒。"
        case .regen: return "每隔几题会回复 1 点生命，速战速决！"
        case .venom: return "剧毒弥漫——每次答对都会被侵蚀 1 点生命！"
        case .berserk: return "愈战愈狂——每 3 题攻击 +1，拖得越久越危险！"
        case .dodge: return "身影飘忽——约 30% 概率闪避你的攻击！"
        case .ironwall: return "铜墙铁壁——每 4 题免疫一次你的伤害！"
        case .lifesteal: return "以战养战——你答错时它回复 1 点生命！"
        }
    }
}

// MARK: - 境界（从凡人到道祖，共 16 大境界）

struct TowerStage: Identifiable, Equatable {
    let index: Int
    let name: String
    let subtitle: String
    let icon: String
    let floors: Int
    let minions: [(name: String, icon: String)]
    let eliteName: String
    let bossName: String
    let bossIcon: String
    let bossHP: Int
    let bossTime: Int
    var bossAbility: BossAbility = .none

    var id: Int { index }
    static func == (lhs: TowerStage, rhs: TowerStage) -> Bool { lhs.index == rhs.index }

    static let all: [TowerStage] = [
        TowerStage(index: 1, name: "凡人", subtitle: "尚未入道，肉体凡胎", icon: "figure.walk", floors: 1,
                   minions: [("田间野狗", "pawprint.fill"), ("街头泼皮", "figure.stand")],
                   eliteName: "镇上恶霸", bossName: "拦路山大王", bossIcon: "figure.walk.motion", bossHP: 12, bossTime: 0),
        TowerStage(index: 2, name: "炼气初期", subtitle: "引气入体，妖雾初现", icon: "wind", floors: 4,
                   minions: [("拼写小妖", "ant.fill"), ("词雾史莱姆", "cloud.fog.fill")],
                   eliteName: "词灵盗匪", bossName: "墨大夫", bossIcon: "cross.vial.fill", bossHP: 22, bossTime: 0, bossAbility: .venom),
        TowerStage(index: 3, name: "炼气中期", subtitle: "灵力渐盛，心魔来犯", icon: "wind", floors: 4,
                   minions: [("健忘蝙蝠", "moon.stars.fill"), ("乱序精怪", "shuffle")],
                   eliteName: "形近妖僧", bossName: "鸡哥·只因", bossIcon: "basketball.fill", bossHP: 30, bossTime: 60,
                   bossAbility: .disableSkill),
        TowerStage(index: 4, name: "炼气后期", subtitle: "气海满盈，准备筑基", icon: "wind", floors: 5,
                   minions: [("音标幽灵", "waveform"), ("词性哨兵", "textformat.abc")],
                   eliteName: "混淆使者", bossName: "铁手张铁", bossIcon: "hammer.fill", bossHP: 40, bossTime: 0,
                   bossAbility: .doubleHit),
        TowerStage(index: 5, name: "筑基期", subtitle: "筑道基之，真假难辨", icon: "square.stack.3d.up", floors: 5,
                   minions: [("语法小鬼", "puzzlepiece.fill"), ("词根傀儡", "cube.fill")],
                   eliteName: "从句缠灵", bossName: "野狼帮主", bossIcon: "pawprint.circle.fill", bossHP: 55, bossTime: 0, bossAbility: .dodge),
        TowerStage(index: 6, name: "结丹期", subtitle: "凝结金丹，语法巨物", icon: "circle.circle.fill", floors: 5,
                   minions: [("长难句魔像", "text.alignleft"), ("语法巨魔", "flame.fill")],
                   eliteName: "时态吞噬者", bossName: "诸葛老怪", bossIcon: "eye.trianglebadge.exclamationmark.fill", bossHP: 75, bossTime: 0,
                   bossAbility: .regen),
        TowerStage(index: 7, name: "元婴期", subtitle: "结婴成神，同义迷阵", icon: "sparkles", floors: 5,
                   minions: [("同义幻影", "rectangle.on.rectangle"), ("反义双头蛇", "arrow.left.arrow.right")],
                   eliteName: "近义织网者", bossName: "银翅夜叉王", bossIcon: "bird.fill", bossHP: 95, bossTime: 0,
                   bossAbility: .doubleHit),
        TowerStage(index: 8, name: "化神期", subtitle: "神识化形，心魔当道", icon: "brain.head.profile", floors: 6,
                   minions: [("心魔低语", "brain.head.profile"), ("虚空词灵", "sparkles")],
                   eliteName: "执念魔影", bossName: "天魔·忘言", bossIcon: "theatermasks.fill", bossHP: 120, bossTime: 75,
                   bossAbility: .timeDrain),
        TowerStage(index: 9, name: "炼虚期", subtitle: "炼神返虚，虚实不分", icon: "cloud.bolt.fill", floors: 6,
                   minions: [("湮灭书妖", "book.closed.fill"), ("迷雾魔", "smoke.fill")],
                   eliteName: "虚空行者", bossName: "马保国", bossIcon: "figure.martial.arts", bossHP: 150, bossTime: 70,
                   bossAbility: .doubleHit),
        TowerStage(index: 10, name: "合体期", subtitle: "法身合一，威能无双", icon: "atom", floors: 6,
                   minions: [("融魂妖", "rectangle.2.swap"), ("双生煞", "person.2.fill")],
                   eliteName: "合体傀儡", bossName: "血神子", bossIcon: "drop.fill", bossHP: 185, bossTime: 0, bossAbility: .lifesteal,
                   ),
        TowerStage(index: 11, name: "大乘期", subtitle: "大乘之境，渡劫在即", icon: "burst.fill", floors: 6,
                   minions: [("渡劫雷魂", "bolt.fill"), ("心魔化身", "theatermasks")],
                   eliteName: "大乘执事", bossName: "曲魂", bossIcon: "waveform.path.ecg", bossHP: 220, bossTime: 80,
                   bossAbility: .timeDrain),
        TowerStage(index: 12, name: "真仙", subtitle: "飞升仙界，谪仙之始", icon: "sparkle", floors: 7,
                   minions: [("仙界游魂", "wind.snow"), ("堕仙", "cloud.moon.fill")],
                   eliteName: "谪仙使者", bossName: "通天魔祖", bossIcon: "tornado", bossHP: 260, bossTime: 0, bossAbility: .berserk),
        TowerStage(index: 13, name: "金仙", subtitle: "金身不坏，万劫不磨", icon: "sun.max.fill", floors: 7,
                   minions: [("金光罗汉", "circle.circle.fill"), ("叛仙", "person.fill.xmark")],
                   eliteName: "金仙护法", bossName: "黄金战神", bossIcon: "figure.strengthtraining.traditional", bossHP: 300, bossTime: 85, bossAbility: .ironwall,
                   ),
        TowerStage(index: 14, name: "太乙", subtitle: "太乙金仙，星辰在握", icon: "moon.stars.fill", floors: 7,
                   minions: [("太乙散人", "sparkles"), ("星宿妖", "star.fill")],
                   eliteName: "太乙真君", bossName: "混沌魔君", bossIcon: "hurricane", bossHP: 340, bossTime: 90, bossAbility: .venom,
                   ),
        TowerStage(index: 15, name: "大罗金仙", subtitle: "跳出三界，不在五行", icon: "crown.fill", floors: 8,
                   minions: [("大罗虚影", "circle.hexagongrid.fill"), ("时空裂魔", "clock.badge.exclamationmark.fill")],
                   eliteName: "大罗执法", bossName: "弑神者", bossIcon: "bolt.trianglebadge.exclamationmark.fill", bossHP: 390, bossTime: 0, bossAbility: .dodge,
                   ),
        TowerStage(index: 16, name: "道祖", subtitle: "道之本源，万词之师", icon: "infinity", floors: 8,
                   minions: [("道则傀儡", "function"), ("混元虚影", "circle.dotted")],
                   eliteName: "鸿蒙守卫", bossName: "道祖·鸿蒙", bossIcon: "infinity.circle.fill", bossHP: 450, bossTime: 100,
                   bossAbility: .disableSkill)
    ]
}

// MARK: - 品质：低阶＜中阶＜高阶＜稀有＜传奇＜金色传说

enum ItemTier: String, CaseIterable, Comparable {
    case low, mid, high, rare, legendary, goldLegend, demon

    var label: String {
        switch self {
        case .low: return "低阶"
        case .mid: return "中阶"
        case .high: return "高阶"
        case .rare: return "稀有"
        case .legendary: return "传奇"
        case .goldLegend: return "金色传说"
        case .demon: return "魔器"
        }
    }

    var color: Color {
        switch self {
        case .low: return .gray
        case .mid: return .green
        case .high: return .blue
        case .rare: return .purple
        case .legendary: return .orange
        case .goldLegend: return .yellow
        case .demon: return .purple
        }
    }

    /// 抽取权重（稀有度越高越难出）
    var weight: Int {
        switch self {
        case .low: return 28
        case .mid: return 26
        case .high: return 20
        case .rare: return 14
        case .legendary: return 9
        case .goldLegend: return 3
        case .demon: return 1
        }
    }

    /// 隐藏门槛：高稀有度需闯到后面的境界才可能出现（不对外说明）
    var stageGate: Int {
        switch self {
        case .rare: return 4
        case .legendary: return 7
        case .goldLegend: return 11
        default: return 1
        }
    }

    private var order: Int {
        ItemTier.allCases.firstIndex(of: self) ?? 0
    }

    static func < (lhs: ItemTier, rhs: ItemTier) -> Bool { lhs.order < rhs.order }
}

// MARK: - 物品分类：穿戴（五部位）/ 武器 / 药水 / 宠物 / 精灵

enum WearSlot: String, CaseIterable {
    case hat, clothes, jewelry, pants, shoes

    var label: String {
        switch self {
        case .hat: return "帽子"
        case .clothes: return "衣服"
        case .jewelry: return "首饰"
        case .pants: return "裤子"
        case .shoes: return "鞋子"
        }
    }
}

enum ItemCategory: Equatable {
    case wear(WearSlot)
    case weapon
    case potion
    case pet
    case sprite

    var bigLabel: String {
        switch self {
        case .wear: return "穿戴"
        case .weapon: return "武器"
        case .potion: return "药水"
        case .pet: return "宠物"
        case .sprite: return "精灵"
        }
    }

    /// 装备槽键（药水不可装备）
    var equipKey: String? {
        switch self {
        case .wear(let slot): return slot.rawValue
        case .weapon: return "weapon"
        case .pet: return "pet"
        case .sprite: return "sprite"
        case .potion: return nil
        }
    }
}

struct GameItem: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let tier: ItemTier
    let category: ItemCategory
    let effectDesc: String
    let maxDurability: Int          // 药水 1；99 = 不磨损
    let price: Int
    let restrictedTo: HeroClass?
    /// 物品背景故事/徕语
    var lore: String = ""
    var damageBonus: Int = 0
    var defenseBonus: Int = 0
    var extraShield: Bool = false
    var coinBonus: Int = 0
    var healAmount: Int = 0         // 药水回血（99 = 全满）
    var timeBonus: Int = 0          // 装备=限时战被动加秒；药水=使用加秒
    var regenPerWin: Int = 0        // 每次战斗胜利回血

    static func == (lhs: GameItem, rhs: GameItem) -> Bool { lhs.id == rhs.id }

    static let catalog: [GameItem] = [
        // ── 穿戴 · 帽子
        GameItem(id: "strawHat", name: "斗笠", icon: "cone.fill", tier: .low, category: .wear(.hat),
                 effectDesc: "江湖气十足的收藏品", maxDurability: 99, price: 10, restrictedTo: nil, lore: "每个大侠的第一顶帽子。风雨里赶路时，它比什么护甲都实在。"),
        GameItem(id: "clothCap", name: "布巾", icon: "seal", tier: .low, category: .wear(.hat),
                 effectDesc: "受击伤害 -1", maxDurability: 10, price: 18, restrictedTo: nil, lore: "山下杂货铺三文钱一条，胜在便宜。", defenseBonus: 1),
        GameItem(id: "bambooHat", name: "竹叶帽", icon: "leaf.fill", tier: .low, category: .wear(.hat),
                 effectDesc: "受击伤害 -1", maxDurability: 12, price: 22, restrictedTo: nil, lore: "竹叶编的帽子，据说能挡住词妖的窥视。", defenseBonus: 1),
        GameItem(id: "学徒Cap", name: "学徒软帽", icon: "graduationcap", tier: .low, category: .wear(.hat),
                 effectDesc: "受击伤害 -1", maxDurability: 11, price: 20, restrictedTo: nil, lore: "新入门弟子的标配，帽檐还留着背单词时蹭上的墨迹。", defenseBonus: 1),
        GameItem(id: "linenHood", name: "麻布头巾", icon: "person.crop.circle", tier: .low, category: .wear(.hat),
                 effectDesc: "每次胜利 +1 金币", maxDurability: 12, price: 16, restrictedTo: nil, lore: "贩夫走卒的头巾，兜里总能多出几个铜板。", coinBonus: 1),
        GameItem(id: "gauzeCrown", name: "青纱冠", icon: "crown", tier: .mid, category: .wear(.hat),
                 effectDesc: "受击伤害 -1，更耐用", maxDurability: 18, price: 45, restrictedTo: nil, lore: "青纱覆面，风流自在。据说戴上它背单词，记性会好三分。", defenseBonus: 1),
        GameItem(id: "scholarCap", name: "书生巾", icon: "book.closed.fill", tier: .mid, category: .wear(.hat),
                 effectDesc: "每次胜利额外 +1 金币", maxDurability: 20, price: 48, restrictedTo: nil, lore: "十年寒窗的见证。书生说：单词嘛，读书百遍其义自见。", coinBonus: 1),
        GameItem(id: "ironCap", name: "铁盔", icon: "shield.lefthalf.filled", tier: .mid, category: .wear(.hat),
                 effectDesc: "受击伤害 -1", maxDurability: 24, price: 50, restrictedTo: nil, lore: "军中制式，笨重但可靠。", defenseBonus: 1),
        GameItem(id: "featherCap", name: "羽饰帽", icon: "bird", tier: .mid, category: .wear(.hat),
                 effectDesc: "限时战斗 +4 秒", maxDurability: 18, price: 52, restrictedTo: nil, lore: "插着一根不知名鸟羽，走路带风。", timeBonus: 4),
        GameItem(id: "mageHat", name: "星语法帽", icon: "wand.and.stars", tier: .high, category: .wear(.hat),
                 effectDesc: "命中伤害 +1", maxDurability: 18, price: 85, restrictedTo: .mage, lore: "法师的尖顶帽。帽尖越尖，咒语越准——这是行会千年不变的迷信。", damageBonus: 1),
        GameItem(id: "ironHelm", name: "玄铁盔", icon: "shield.fill", tier: .high, category: .wear(.hat),
                 effectDesc: "受击伤害 -1，坚固耐用", maxDurability: 30, price: 90, restrictedTo: nil, lore: "玄铁百炼，刀砍上去只留一道白痕。", defenseBonus: 1),
        GameItem(id: "moonCoronet", name: "月华冠", icon: "moon.stars.fill", tier: .high, category: .wear(.hat),
                 effectDesc: "限时战斗 +5 秒", maxDurability: 22, price: 95, restrictedTo: nil, lore: "月光凝成的冠冕，戴上后时间仿佛走得慢些。", timeBonus: 5),
        GameItem(id: "knightHelm", name: "誓约头盔", icon: "shield.checkered", tier: .high, category: .wear(.hat),
                 effectDesc: "受击 -2（词剑士专属）", maxDurability: 26, price: 100, restrictedTo: .knight, lore: "剑士入门时立下的誓约刻在内衬：一寸不退。", defenseBonus: 2),
        GameItem(id: "healerVeil", name: "杏林纱帽", icon: "cross.case", tier: .high, category: .wear(.hat),
                 effectDesc: "每次胜利回血 1（词医者专属）", maxDurability: 22, price: 98, restrictedTo: .healer, lore: "医者的纱帽，行医时用来遮挡病气。", regenPerWin: 1),
        GameItem(id: "thiefHood", name: "夜行斗篷帽", icon: "moon.fill", tier: .high, category: .wear(.hat),
                 effectDesc: "限时 +6 秒（词行者专属）", maxDurability: 20, price: 92, restrictedTo: .rogue, lore: "夜行者的兜帽。真正的高手，连风都听不见他的脚步。", timeBonus: 6),
        GameItem(id: "starCrown", name: "星辉冠", icon: "sparkle", tier: .rare, category: .wear(.hat),
                 effectDesc: "受击伤害 -2", maxDurability: 24, price: 160, restrictedTo: nil, lore: "以陨星碎屑镶嵌，夜里会自己发光，找路很方便。", defenseBonus: 2),
        GameItem(id: "thunderHelm", name: "雷纹战盔", icon: "bolt.fill", tier: .rare, category: .wear(.hat),
                 effectDesc: "命中伤害 +1", maxDurability: 20, price: 170, restrictedTo: nil, lore: "盔上雷纹会在战斗中噼啪作响，敌人往往先被吓一跳。", damageBonus: 1),
        GameItem(id: "gamblerTopHat", name: "老千高帽", icon: "die.face.3.fill", tier: .rare, category: .wear(.hat),
                 effectDesc: "命中 +1，胜利 +2 金币（词赌徒专属）", maxDurability: 18, price: 175, restrictedTo: .gambler, lore: "帽子里能藏五张牌——当然，赌徒本人绝不承认。", damageBonus: 1, coinBonus: 2),
        GameItem(id: "archmageHat", name: "大法师尖帽", icon: "wand.and.rays", tier: .rare, category: .wear(.hat),
                 effectDesc: "命中 +1，限时 +5 秒（词法师专属）", maxDurability: 20, price: 180, restrictedTo: .mage, lore: "「你不该来这儿。」——某位灰袍法师最爱说的话。", damageBonus: 1, timeBonus: 5),
        GameItem(id: "dragonHelm", name: "龙魂战盔", icon: "flame.circle.fill", tier: .legendary, category: .wear(.hat),
                 effectDesc: "受击伤害 -2，每场战斗额外一次格挡", maxDurability: 22, price: 260, restrictedTo: nil, lore: "盔中封着一缕龙魂。它在你濒死时会替你咬住那一击。", defenseBonus: 2, extraShield: true),
        GameItem(id: "phoenixCoronet", name: "凤羽金冠", icon: "bird.circle.fill", tier: .legendary, category: .wear(.hat),
                 effectDesc: "受击 -1，命中 +1", maxDurability: 22, price: 275, restrictedTo: nil, lore: "凤凰落羽所制。凤凰不死，戴它的人也总能多撑一会儿。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "crownOfThorns", name: "荆棘之冠", icon: "hexagon", tier: .legendary, category: .wear(.hat),
                 effectDesc: "命中 +2，受击 +0", maxDurability: 18, price: 290, restrictedTo: nil, lore: "越痛越强的冠冕。刺扎进皮肉时，你反而看得更清了。", damageBonus: 2),
        GameItem(id: "goldenCrown", name: "金乌冕", icon: "sun.max.fill", tier: .goldLegend, category: .wear(.hat),
                 effectDesc: "受击伤害 -3", maxDurability: 26, price: 420, restrictedTo: nil, lore: "传说金乌栖于扶桑，一日一飞。此冕以其冠羽为芯，烈日不能伤。", defenseBonus: 3),
        GameItem(id: "voidCrown", name: "虚空道冠", icon: "circle.hexagongrid.fill", tier: .goldLegend, category: .wear(.hat),
                 effectDesc: "受击 -2，限时 +8 秒", maxDurability: 26, price: 460, restrictedTo: nil, lore: "戴上它，你会短暂地忘记「时间」这个词的含义——这正是它的用处。", defenseBonus: 2, timeBonus: 8),
        GameItem(id: "woodenCirclet", name: "木环冠", icon: "circle", tier: .low, category: .wear(.hat),
                 effectDesc: "受击伤害 -1", maxDurability: 9, price: 14, restrictedTo: nil, lore: "削木成环，聊胜于无。", defenseBonus: 1),
        GameItem(id: "beggarHat", name: "破草帽", icon: "cone", tier: .low, category: .wear(.hat),
                 effectDesc: "每次胜利 +1 金币", maxDurability: 8, price: 12, restrictedTo: nil, lore: "别嫌破。真正的高人往往一身破衣。", coinBonus: 1),
        GameItem(id: "silkBand", name: "锦缎发带", icon: "line.horizontal.3", tier: .low, category: .wear(.hat),
                 effectDesc: "限时战斗 +3 秒", maxDurability: 10, price: 20, restrictedTo: nil, lore: "束发用的锦带，跑起来利索。", timeBonus: 3),
        GameItem(id: "bronzeHelm", name: "青铜盔", icon: "shield", tier: .mid, category: .wear(.hat),
                 effectDesc: "受击伤害 -1", maxDurability: 26, price: 46, restrictedTo: nil, lore: "上古军械，青绿的铜锈里还嵌着旧战场的沙。", defenseBonus: 1),
        GameItem(id: "cloudCap", name: "流云帽", icon: "cloud", tier: .mid, category: .wear(.hat),
                 effectDesc: "限时战斗 +5 秒", maxDurability: 19, price: 55, restrictedTo: nil, lore: "轻得像没戴。走神时它会替你挡一下阳光。", timeBonus: 5),
        GameItem(id: "horaryCap", name: "更漏冠", icon: "clock", tier: .mid, category: .wear(.hat),
                 effectDesc: "限时战斗 +6 秒", maxDurability: 17, price: 58, restrictedTo: nil, lore: "冠内嵌着微型更漏，滴答声让人心安。", timeBonus: 6),
        GameItem(id: "wolfHeadgear", name: "狼首盔", icon: "pawprint", tier: .high, category: .wear(.hat),
                 effectDesc: "命中伤害 +1", maxDurability: 20, price: 88, restrictedTo: nil, lore: "以头狼颅骨为形。狼群的规矩：咬住了就别松口。", damageBonus: 1),
        GameItem(id: "jadeCrown", name: "白玉冠", icon: "diamond", tier: .high, category: .wear(.hat),
                 effectDesc: "受击 -1，胜利 +2 金币", maxDurability: 22, price: 105, restrictedTo: nil, lore: "世家子弟的排场。玉能养人，也能买命。", defenseBonus: 1, coinBonus: 2),
        // ── 穿戴 · 衣服
        GameItem(id: "clothRobe", name: "粗布道衣", icon: "tshirt", tier: .low, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 10, price: 20, restrictedTo: nil, lore: "道观发的常服，洗得发白。", defenseBonus: 1),
        GameItem(id: "hempShirt", name: "麻布短打", icon: "tshirt.fill", tier: .low, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 12, price: 24, restrictedTo: nil, lore: "干活方便，打架也方便。", defenseBonus: 1),
        GameItem(id: "patchedRobe", name: "百衲衣", icon: "square.grid.3x3.fill", tier: .low, category: .wear(.clothes),
                 effectDesc: "受击 -1，胜利 +1 金币", maxDurability: 11, price: 22, restrictedTo: nil, lore: "一百块碎布缝的，据说每块都来自一位施主。", defenseBonus: 1, coinBonus: 1),
        GameItem(id: "noviceVest", name: "弟子背心", icon: "tshirt", tier: .low, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 10, price: 18, restrictedTo: nil, lore: "背上绣着「勤」字，师父亲手绣的。", defenseBonus: 1),
        GameItem(id: "strawCape", name: "蓑衣", icon: "cloud.rain.fill", tier: .low, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 13, price: 26, restrictedTo: nil, lore: "孤舟蓑笠翁，独钓寒江雪。", defenseBonus: 1),
        GameItem(id: "daoRobe", name: "青云道袍", icon: "tshirt.fill", tier: .mid, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1，更耐用", maxDurability: 24, price: 60, restrictedTo: nil, lore: "青云直上，说的是志气，不是衣服。", defenseBonus: 1),
        GameItem(id: "leatherArmor", name: "皮甲", icon: "shippingbox.fill", tier: .mid, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 26, price: 58, restrictedTo: nil, lore: "牛皮硝制，实用主义者的选择。", defenseBonus: 1),
        GameItem(id: "chainMail", name: "锁子甲", icon: "square.grid.4x3.fill", tier: .mid, category: .wear(.clothes),
                 effectDesc: "受击 -1，耐久极高", maxDurability: 34, price: 68, restrictedTo: nil, lore: "一环扣一环，像背单词一样，少一环就散。", defenseBonus: 1),
        GameItem(id: "silkGown", name: "云锦长衫", icon: "wave.3.right", tier: .mid, category: .wear(.clothes),
                 effectDesc: "限时战斗 +5 秒", maxDurability: 20, price: 64, restrictedTo: nil, lore: "穿它去赴宴，比穿它去打架合适。", timeBonus: 5),
        GameItem(id: "herbRobe", name: "药香褂", icon: "leaf.circle", tier: .mid, category: .wear(.clothes),
                 effectDesc: "每次胜利回血 1", maxDurability: 20, price: 70, restrictedTo: nil, lore: "衣襟里常年塞着药材，闻着就精神。", regenPerWin: 1),
        GameItem(id: "turtleArmor", name: "玄武甲", icon: "tortoise.fill", tier: .high, category: .wear(.clothes),
                 effectDesc: "受击伤害 -2", maxDurability: 22, price: 110, restrictedTo: nil, lore: "玄武负地，千年不动。穿上它你就懂什么叫「稳」。", defenseBonus: 2),
        GameItem(id: "frostRobe", name: "霜纹长袍", icon: "snowflake", tier: .high, category: .wear(.clothes),
                 effectDesc: "受击 -1，命中 +1", maxDurability: 20, price: 120, restrictedTo: nil, lore: "袍上霜纹会在寒冬自行蔓延，据说是活的。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "healerRobe", name: "杏林白袍", icon: "cross.case.fill", tier: .high, category: .wear(.clothes),
                 effectDesc: "受击 -1，每次胜利回血 1（词医者专属）", maxDurability: 20, price: 100, restrictedTo: .healer, lore: "医者不自医，但这件袍子会替他疗伤。", defenseBonus: 1, regenPerWin: 1),
        GameItem(id: "shadowCloak", name: "影行披风", icon: "moon.fill", tier: .mid, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1（词行者专属）", maxDurability: 18, price: 55, restrictedTo: .rogue, lore: "披上它，影子会先一步替你溜走。", defenseBonus: 1),
        GameItem(id: "knightPlate", name: "誓约胸甲", icon: "shield.righthalf.filled", tier: .high, category: .wear(.clothes),
                 effectDesc: "受击 -2（词剑士专属）", maxDurability: 28, price: 115, restrictedTo: .knight, lore: "胸甲正中有一道旧凹痕——那是他没退的那一步留下的。", defenseBonus: 2),
        GameItem(id: "gamblerSuit", name: "花牌礼服", icon: "suit.club.fill", tier: .high, category: .wear(.clothes),
                 effectDesc: "命中 +1，胜利 +2 金币（词赌徒专属）", maxDurability: 18, price: 112, restrictedTo: .gambler, lore: "上牌桌要有排场。至于袖子里有什么，那是另一回事。", damageBonus: 1, coinBonus: 2),
        GameItem(id: "featherRobe", name: "仙羽霓裳", icon: "bird.fill", tier: .rare, category: .wear(.clothes),
                 effectDesc: "受击伤害 -2，轻若无物", maxDurability: 26, price: 170, restrictedTo: nil, lore: "千鸟落羽织成，穿上仿佛下一步就能踏空而行。", defenseBonus: 2),
        GameItem(id: "starRobe", name: "星河法衣", icon: "sparkles", tier: .rare, category: .wear(.clothes),
                 effectDesc: "受击 -1，限时 +6 秒", maxDurability: 24, price: 175, restrictedTo: nil, lore: "法衣内里绣着整片星图，夜里能当地图看。", defenseBonus: 1, timeBonus: 6),
        GameItem(id: "greenRobe", name: "青囊道服", icon: "cross.vial.fill", tier: .rare, category: .wear(.clothes),
                 effectDesc: "每次胜利回血 2（词医者专属）", maxDurability: 22, price: 185, restrictedTo: .healer, lore: "传说华佗的青囊里装着这件衣服，可惜书被烧了。", regenPerWin: 2),
        GameItem(id: "saintRobe", name: "不朽圣袍", icon: "moon.stars.fill", tier: .legendary, category: .wear(.clothes),
                 effectDesc: "受击伤害 -3", maxDurability: 24, price: 280, restrictedTo: nil, lore: "它不会破。你破了它都还在。", defenseBonus: 3),
        GameItem(id: "dragonRobe", name: "蟠龙锦袍", icon: "scale.3d", tier: .legendary, category: .wear(.clothes),
                 effectDesc: "受击 -2，每次胜利 +2 金币", maxDurability: 26, price: 290, restrictedTo: nil, lore: "袍上蟠龙栩栩如生。据说穿它上朝，龙会替你说话。", defenseBonus: 2, coinBonus: 2),
        GameItem(id: "cicadaRobe", name: "金蝉圣衣", icon: "seal.fill", tier: .goldLegend, category: .wear(.clothes),
                 effectDesc: "受击伤害 -4", maxDurability: 28, price: 450, restrictedTo: nil, lore: "金蝉脱壳，此衣即壳。刀枪不入，水火不侵——但每次脱下都要三天才能穿回去。", defenseBonus: 4),
        GameItem(id: "chaosRobe", name: "混沌天衣", icon: "circle.dotted", tier: .goldLegend, category: .wear(.clothes),
                 effectDesc: "受击 -3，额外一次格挡", maxDurability: 28, price: 500, restrictedTo: nil, lore: "天衣无缝。你找不到它的接缝，敌人也找不到你的破绽。", defenseBonus: 3, extraShield: true),
        GameItem(id: "roughVest", name: "藤编护胸", icon: "square.split.diagonal", tier: .low, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 9, price: 15, restrictedTo: nil, lore: "山民用藤条编的，防野兽尚可。", defenseBonus: 1),
        GameItem(id: "cottonRobe", name: "棉布长袍", icon: "tshirt", tier: .low, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 12, price: 21, restrictedTo: nil, lore: "暖和。背单词到半夜时全靠它。", defenseBonus: 1),
        GameItem(id: "scaleVest", name: "鱼鳞衬甲", icon: "fish.fill", tier: .mid, category: .wear(.clothes),
                 effectDesc: "受击 -1，限时 +3 秒", maxDurability: 24, price: 62, restrictedTo: nil, lore: "以深潭鱼鳞缝制，滑不留手。", defenseBonus: 1, timeBonus: 3),
        GameItem(id: "bronzeArmor", name: "青铜胸甲", icon: "square.stack.3d.up.fill", tier: .mid, category: .wear(.clothes),
                 effectDesc: "受击伤害 -1", maxDurability: 30, price: 56, restrictedTo: nil, lore: "上古战场遗物，还留着钝痕。", defenseBonus: 1),
        GameItem(id: "mageRobe", name: "秘纹法袍", icon: "wand.and.stars.inverse", tier: .high, category: .wear(.clothes),
                 effectDesc: "命中 +1，限时 +4 秒（词法师专属）", maxDurability: 20, price: 108, restrictedTo: .mage, lore: "袍上秘纹是一整套咒语的速记，法师管它叫「小抄」。", damageBonus: 1, timeBonus: 4),
        GameItem(id: "wolfPelt", name: "狼皮大衣", icon: "pawprint.fill", tier: .high, category: .wear(.clothes),
                 effectDesc: "命中 +1，受击 -1", maxDurability: 22, price: 118, restrictedTo: nil, lore: "猎狼者穿狼皮，是尊重，也是宣战。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "nightSuit", name: "夜行紧衣", icon: "moon.zzz.fill", tier: .rare, category: .wear(.clothes),
                 effectDesc: "限时 +8 秒（词行者专属）", maxDurability: 20, price: 165, restrictedTo: .rogue, lore: "贴身裁制，连呼吸都被裹住了。", timeBonus: 8),
        GameItem(id: "phoenixRobe", name: "不死鸟羽衣", icon: "flame.circle", tier: .legendary, category: .wear(.clothes),
                 effectDesc: "受击 -2，每次胜利回血 2", maxDurability: 24, price: 300, restrictedTo: nil, lore: "浴火重生这四个字，穿上才有资格说。", defenseBonus: 2, regenPerWin: 2),
        // ── 穿戴 · 首饰
        GameItem(id: "woodBeads", name: "木珠链", icon: "circle.grid.cross.fill", tier: .low, category: .wear(.jewelry),
                 effectDesc: "每次胜利额外 +1 金币", maxDurability: 12, price: 18, restrictedTo: nil, lore: "山寺赠的念珠，据说数一遍能静心。", coinBonus: 1),
        GameItem(id: "copperRing", name: "铜戒", icon: "circle.circle", tier: .low, category: .wear(.jewelry),
                 effectDesc: "命中伤害 +1", maxDurability: 8, price: 25, restrictedTo: nil, lore: "铜戒握拳时能多几分力道，仅此而已。", damageBonus: 1),
        GameItem(id: "boneAmulet", name: "骨符", icon: "seal", tier: .low, category: .wear(.jewelry),
                 effectDesc: "受击伤害 -1", maxDurability: 10, price: 20, restrictedTo: nil, lore: "兽骨刻符，巫祝之物。信则灵。", defenseBonus: 1),
        GameItem(id: "luckyKnot", name: "同心结", icon: "heart.fill", tier: .low, category: .wear(.jewelry),
                 effectDesc: "每次胜利回血 1", maxDurability: 10, price: 24, restrictedTo: nil, lore: "不知谁送的，红线都旧了，却一直没舍得扔。", regenPerWin: 1),
        GameItem(id: "copperCoinString", name: "铜钱串", icon: "circle.hexagongrid", tier: .low, category: .wear(.jewelry),
                 effectDesc: "每次胜利 +2 金币", maxDurability: 12, price: 28, restrictedTo: nil, lore: "一串铜钱当项链戴。俗气，但真的招财。", coinBonus: 2),
        GameItem(id: "jadePendant", name: "凝神玉佩", icon: "diamond.fill", tier: .mid, category: .wear(.jewelry),
                 effectDesc: "限时战斗时限 +10 秒", maxDurability: 8, price: 70, restrictedTo: nil, lore: "握住它深吸一口气，慌乱的心就定了。", timeBonus: 10),
        GameItem(id: "koiRibbon", name: "锦鲤发带", icon: "fish.fill", tier: .mid, category: .wear(.jewelry),
                 effectDesc: "传说能带来好运的收藏品", maxDurability: 99, price: 25, restrictedTo: nil, lore: "锦鲤跃龙门的故事人人会讲，跃过去的却总是别人。"),
        GameItem(id: "silverBell", name: "银铃", icon: "bell", tier: .mid, category: .wear(.jewelry),
                 effectDesc: "限时战斗 +6 秒", maxDurability: 14, price: 60, restrictedTo: nil, lore: "铃响一声，神志清明一分。", timeBonus: 6),
        GameItem(id: "tigerTooth", name: "虎牙坠", icon: "pawprint", tier: .mid, category: .wear(.jewelry),
                 effectDesc: "命中伤害 +1", maxDurability: 12, price: 66, restrictedTo: nil, lore: "从猛虎口中拔下的牙。至于是怎么拔的，他不肯说。", damageBonus: 1),
        GameItem(id: "moneyBag", name: "聚财金袋", icon: "bag.fill", tier: .high, category: .wear(.jewelry),
                 effectDesc: "每次胜利额外 +3 金币", maxDurability: 14, price: 120, restrictedTo: nil, lore: "袋口永远收不紧——金币太多了。", coinBonus: 3),
        GameItem(id: "windBell", name: "清风铃", icon: "bell.fill", tier: .high, category: .wear(.jewelry),
                 effectDesc: "限时战斗 +6 秒，胜利 +1 金币", maxDurability: 14, price: 115, restrictedTo: nil, lore: "风一过就响。有人说那是提醒你：时间还够。", coinBonus: 1, timeBonus: 6),
        GameItem(id: "knightOath", name: "誓约徽记", icon: "shield.checkered", tier: .high, category: .wear(.jewelry),
                 effectDesc: "额外一次格挡（词剑士专属）", maxDurability: 10, price: 118, restrictedTo: .knight, lore: "骑士的誓约刻在徽记背面，磨得快看不清了，他却记得每一个字。", extraShield: true),
        GameItem(id: "manaCrystal", name: "魔力水晶", icon: "hexagon.fill", tier: .high, category: .wear(.jewelry),
                 effectDesc: "命中 +1，限时 +5 秒（词法师专属）", maxDurability: 12, price: 122, restrictedTo: .mage, lore: "法师的备用魔力池。快没词儿的时候，靠它顶一下。", damageBonus: 1, timeBonus: 5),
        GameItem(id: "gamblerCharm", name: "赌魂符", icon: "suit.spade.fill", tier: .high, category: .wear(.jewelry),
                 effectDesc: "命中伤害 +1（词赌徒专属）", maxDurability: 12, price: 95, restrictedTo: .gambler, lore: "「再来一把。」——赌魂符上唯一的铭文。", damageBonus: 1),
        GameItem(id: "physicianSeal", name: "杏林印", icon: "cross.circle.fill", tier: .high, category: .wear(.jewelry),
                 effectDesc: "每次胜利回血 2（词医者专属）", maxDurability: 14, price: 120, restrictedTo: .healer, lore: "悬壶济世的凭证。盖过它的药方，从不收穷人的钱。", regenPerWin: 2),
        GameItem(id: "calamityBead", name: "避劫珠", icon: "circle.hexagonpath.fill", tier: .rare, category: .wear(.jewelry),
                 effectDesc: "每场战斗额外一次格挡", maxDurability: 8, price: 150, restrictedTo: nil, lore: "劫数临头时，珠子会碎——碎一次，换你一条命。", extraShield: true),
        GameItem(id: "dragonMask", name: "龙纹面具", icon: "theatermasks.fill", tier: .rare, category: .wear(.jewelry),
                 effectDesc: "稀世收藏，尽显威严", maxDurability: 99, price: 60, restrictedTo: nil, lore: "戴上它谁也认不出你。摘下来，你可能也认不出自己。"),
        GameItem(id: "spiritLocket", name: "聚灵坠", icon: "capsule.fill", tier: .rare, category: .wear(.jewelry),
                 effectDesc: "每次胜利回血 1", maxDurability: 16, price: 155, restrictedTo: nil, lore: "坠中养着一缕灵息，它会一点点还给你。", regenPerWin: 1),
        GameItem(id: "shadowRing", name: "隐踪戒", icon: "circle.dashed", tier: .rare, category: .wear(.jewelry),
                 effectDesc: "限时 +8 秒（词行者专属）", maxDurability: 12, price: 168, restrictedTo: .rogue, lore: "戴上它转三圈，据说能消失——当然，那是骗小孩的。", timeBonus: 8),
        GameItem(id: "cosmosMirror", name: "乾坤镜", icon: "circle.circle.fill", tier: .legendary, category: .wear(.jewelry),
                 effectDesc: "命中伤害 +1，受击伤害 -1", maxDurability: 16, price: 300, restrictedTo: nil, lore: "镜中乾坤，能照见词的本相。照久了会看见自己背错的每一个词。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "nineDragonPearl", name: "九龙珠", icon: "circle.grid.3x3.fill", tier: .legendary, category: .wear(.jewelry),
                 effectDesc: "命中 +2", maxDurability: 14, price: 310, restrictedTo: nil, lore: "九龙争珠，珠归持之者。至于九条龙去哪儿了，故事没说。", damageBonus: 2),
        GameItem(id: "oneRing", name: "至尊金环", icon: "circle.fill", tier: .legendary, category: .wear(.jewelry),
                 effectDesc: "命中 +1，限时 +8 秒", maxDurability: 12, price: 330, restrictedTo: nil, lore: "内圈刻着一行没人认得的字。戴久了总觉得有谁在叫你的名字。", damageBonus: 1, timeBonus: 8),
        GameItem(id: "primalSeal", name: "鸿蒙道印", icon: "hexagon.fill", tier: .goldLegend, category: .wear(.jewelry),
                 effectDesc: "命中伤害 +2，受击伤害 -2", maxDurability: 20, price: 500, restrictedTo: nil, lore: "鸿蒙初辟时的第一枚印。所有的词都从这里开始。", damageBonus: 2, defenseBonus: 2),
        GameItem(id: "fateDice", name: "命运骰坠", icon: "die.face.4.fill", tier: .goldLegend, category: .wear(.jewelry),
                 effectDesc: "命中 +2，每次胜利 +3 金币", maxDurability: 18, price: 520, restrictedTo: nil, lore: "它只有一面朝上：你想要的那面。", damageBonus: 2, coinBonus: 3),
        GameItem(id: "ironBangle", name: "铁镯", icon: "circle", tier: .low, category: .wear(.jewelry),
                 effectDesc: "受击伤害 -1", maxDurability: 11, price: 17, restrictedTo: nil, lore: "打铁匠的赠礼，沉得能练手劲。", defenseBonus: 1),
        GameItem(id: "shellNecklace", name: "贝壳串", icon: "shell.fill", tier: .low, category: .wear(.jewelry),
                 effectDesc: "限时战斗 +3 秒", maxDurability: 10, price: 15, restrictedTo: nil, lore: "海边捡的。凑近能听见潮声。", timeBonus: 3),
        GameItem(id: "cloudPin", name: "云纹簪", icon: "cloud.fill", tier: .mid, category: .wear(.jewelry),
                 effectDesc: "受击 -1，限时 +4 秒", maxDurability: 13, price: 64, restrictedTo: nil, lore: "簪头一朵云，云里藏着一点风。", defenseBonus: 1, timeBonus: 4),
        GameItem(id: "goldLeaf", name: "金叶佩", icon: "leaf.fill", tier: .mid, category: .wear(.jewelry),
                 effectDesc: "每次胜利 +2 金币", maxDurability: 14, price: 72, restrictedTo: nil, lore: "真金打的叶子，脉络分明。有钱人的浪漫。", coinBonus: 2),
        GameItem(id: "phoenixFeather", name: "凤羽坠", icon: "flame.fill", tier: .rare, category: .wear(.jewelry),
                 effectDesc: "每次胜利回血 2", maxDurability: 14, price: 178, restrictedTo: nil, lore: "凤凰的一根尾羽。灼手，但暖。", regenPerWin: 2),
        // ── 穿戴 · 裤子
        GameItem(id: "linenPants", name: "麻布裤", icon: "rectangle.split.2x1", tier: .low, category: .wear(.pants),
                 effectDesc: "受击伤害 -1", maxDurability: 10, price: 15, restrictedTo: nil, lore: "耐磨、透气、便宜，穷修士的三大美德。", defenseBonus: 1),
        GameItem(id: "hideLeggings", name: "兽皮护腿", icon: "pawprint", tier: .low, category: .wear(.pants),
                 effectDesc: "受击伤害 -1", maxDurability: 12, price: 20, restrictedTo: nil, lore: "猎人的护腿，膝盖处磨得最亮。", defenseBonus: 1),
        GameItem(id: "cottonPants", name: "粗棉裤", icon: "rectangle.split.2x1.fill", tier: .low, category: .wear(.pants),
                 effectDesc: "受击伤害 -1", maxDurability: 11, price: 18, restrictedTo: nil, lore: "娘亲缝的，针脚有点歪。", defenseBonus: 1),
        GameItem(id: "wovenPants", name: "藤纹裤", icon: "square.split.diagonal", tier: .low, category: .wear(.pants),
                 effectDesc: "限时战斗 +3 秒", maxDurability: 10, price: 19, restrictedTo: nil, lore: "山民手艺，走山路快得很。", timeBonus: 3),
        GameItem(id: "cloudPants", name: "云纹裤", icon: "cloud.fill", tier: .mid, category: .wear(.pants),
                 effectDesc: "受击伤害 -1，更耐用", maxDurability: 22, price: 50, restrictedTo: nil, lore: "腿上一朵云，走起来轻快。", defenseBonus: 1),
        GameItem(id: "silkPants", name: "丝绸裤", icon: "wave.3.right", tier: .mid, category: .wear(.pants),
                 effectDesc: "限时战斗 +4 秒", maxDurability: 20, price: 52, restrictedTo: nil, lore: "料子太好，打架时总怕蹭破。", timeBonus: 4),
        GameItem(id: "leatherPants", name: "皮护裤", icon: "shippingbox", tier: .mid, category: .wear(.pants),
                 effectDesc: "受击 -1，耐久高", maxDurability: 30, price: 54, restrictedTo: nil, lore: "佣兵最爱。血迹擦擦就没了。", defenseBonus: 1),
        GameItem(id: "bronzeGreaves", name: "青铜胫甲", icon: "square.stack.3d.down.right.fill", tier: .mid, category: .wear(.pants),
                 effectDesc: "受击伤害 -1", maxDurability: 28, price: 56, restrictedTo: nil, lore: "护住小腿，冲阵时最要紧的地方。", defenseBonus: 1),
        GameItem(id: "galePants", name: "罡风战裤", icon: "tornado", tier: .high, category: .wear(.pants),
                 effectDesc: "受击伤害 -2", maxDurability: 20, price: 100, restrictedTo: nil, lore: "裤脚常年鼓风，像有人在旁边推你一把。", defenseBonus: 2),
        GameItem(id: "stonePants", name: "磐石胫甲", icon: "cube.fill", tier: .high, category: .wear(.pants),
                 effectDesc: "受击 -1，耐久极高", maxDurability: 34, price: 95, restrictedTo: nil, lore: "重得离谱，但站定了谁也推不动。", defenseBonus: 1),
        GameItem(id: "knightGreaves", name: "誓约胫甲", icon: "shield.lefthalf.filled", tier: .high, category: .wear(.pants),
                 effectDesc: "受击 -2（词剑士专属）", maxDurability: 30, price: 108, restrictedTo: .knight, lore: "剑士的膝甲从不擦亮——他从不下跪。", defenseBonus: 2),
        GameItem(id: "swiftTrousers", name: "轻捷行裤", icon: "hare", tier: .high, category: .wear(.pants),
                 effectDesc: "限时 +6 秒（词行者专属）", maxDurability: 20, price: 102, restrictedTo: .rogue, lore: "缝了七个暗袋，装满了不该问的东西。", timeBonus: 6),
        GameItem(id: "flameLeggings", name: "焚天护腿", icon: "flame", tier: .rare, category: .wear(.pants),
                 effectDesc: "命中 +1，受击 -1", maxDurability: 20, price: 150, restrictedTo: nil, lore: "行走时留下焦痕。别穿它进草原。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "tidePants", name: "潮汐裤", icon: "water.waves", tier: .rare, category: .wear(.pants),
                 effectDesc: "受击 -2", maxDurability: 22, price: 145, restrictedTo: nil, lore: "布面起伏如潮，攻击落上去总会滑开。", defenseBonus: 2),
        GameItem(id: "dragonscale", name: "龙鳞裤", icon: "scale.3d", tier: .legendary, category: .wear(.pants),
                 effectDesc: "受击伤害 -2，坚不可摧", maxDurability: 26, price: 240, restrictedTo: nil, lore: "每一片鳞都来自不同的龙。它们不是自愿的。", defenseBonus: 2),
        GameItem(id: "starPants", name: "星辰战裤", icon: "star.fill", tier: .legendary, category: .wear(.pants),
                 effectDesc: "受击 -2，胜利 +2 金币", maxDurability: 24, price: 250, restrictedTo: nil, lore: "裤上星点会随夜空变化，同一条裤子从没穿出两次相同的样子。", defenseBonus: 2, coinBonus: 2),
        GameItem(id: "kylinPants", name: "麒麟金胫", icon: "hare.fill", tier: .goldLegend, category: .wear(.pants),
                 effectDesc: "受击伤害 -3", maxDurability: 26, price: 430, restrictedTo: nil, lore: "麒麟不履生草。穿上它，你的每一步都会格外小心。", defenseBonus: 3),
        GameItem(id: "chaosPants", name: "太初法裤", icon: "circle.hexagongrid.circle", tier: .goldLegend, category: .wear(.pants),
                 effectDesc: "受击 -2，命中 +1", maxDurability: 26, price: 450, restrictedTo: nil, lore: "太初有言，言化万物。这条裤子听得懂词。", damageBonus: 1, defenseBonus: 2),
        GameItem(id: "beggarPants", name: "破布裤", icon: "rectangle.dashed", tier: .low, category: .wear(.pants),
                 effectDesc: "每次胜利 +1 金币", maxDurability: 8, price: 10, restrictedTo: nil, lore: "补丁摞补丁。别小看它，跑得比谁都快。", coinBonus: 1),
        GameItem(id: "furLeggings", name: "毛皮暖裤", icon: "snowflake", tier: .low, category: .wear(.pants),
                 effectDesc: "受击伤害 -1", maxDurability: 13, price: 23, restrictedTo: nil, lore: "北境行商的必备，冻不着腿就冻不着心。", defenseBonus: 1),
        GameItem(id: "scalePants", name: "鱼鳞胫裤", icon: "fish", tier: .mid, category: .wear(.pants),
                 effectDesc: "受击 -1，限时 +3 秒", maxDurability: 24, price: 58, restrictedTo: nil, lore: "下水也不沉，据说渔家子弟人人一条。", defenseBonus: 1, timeBonus: 3),
        GameItem(id: "moonPants", name: "月纹裤", icon: "moon", tier: .mid, category: .wear(.pants),
                 effectDesc: "限时战斗 +5 秒", maxDurability: 20, price: 60, restrictedTo: nil, lore: "月色织成的纹路，夜里走路不用点灯。", timeBonus: 5),
        GameItem(id: "mageSkirt", name: "星纹法裾", icon: "wand.and.stars", tier: .high, category: .wear(.pants),
                 effectDesc: "命中 +1（词法师专属）", maxDurability: 18, price: 105, restrictedTo: .mage, lore: "法袍下摆的延伸，走起来像在翻书。", damageBonus: 1),
        GameItem(id: "gamblerPants", name: "花纹长裤", icon: "suit.diamond.fill", tier: .high, category: .wear(.pants),
                 effectDesc: "胜利 +3 金币（词赌徒专属）", maxDurability: 18, price: 110, restrictedTo: .gambler, lore: "口袋深不见底。赢的时候是好事，输的时候……也一样。", coinBonus: 3),
        GameItem(id: "thunderGreaves", name: "雷纹胫甲", icon: "bolt.horizontal", tier: .rare, category: .wear(.pants),
                 effectDesc: "命中 +1，限时 +4 秒", maxDurability: 20, price: 155, restrictedTo: nil, lore: "迈步带电，敌人常被自己的头发吓退。", damageBonus: 1, timeBonus: 4),
        GameItem(id: "voidPants", name: "虚空裤", icon: "circle.dashed.inset.filled", tier: .legendary, category: .wear(.pants),
                 effectDesc: "受击 -3", maxDurability: 24, price: 260, restrictedTo: nil, lore: "据说它其实不存在。摸得到，是你的错觉。", defenseBonus: 3),
        // ── 穿戴 · 鞋子
        GameItem(id: "strawShoes", name: "草鞋", icon: "shoeprints.fill", tier: .low, category: .wear(.shoes),
                 effectDesc: "行走江湖的收藏品", maxDurability: 99, price: 8, restrictedTo: nil, lore: "千里之行，始于草鞋。磨破七双，就到得了山顶。"),
        GameItem(id: "clothBoots", name: "布靴", icon: "shoeprints.fill", tier: .low, category: .wear(.shoes),
                 effectDesc: "受击伤害 -1", maxDurability: 10, price: 16, restrictedTo: nil, lore: "轻便，但下雨天会灌水。", defenseBonus: 1),
        GameItem(id: "hideBoots", name: "兽皮靴", icon: "pawprint.circle", tier: .low, category: .wear(.shoes),
                 effectDesc: "受击伤害 -1", maxDurability: 12, price: 19, restrictedTo: nil, lore: "山里人手工缝的，防滑。", defenseBonus: 1),
        GameItem(id: "woodenClogs", name: "木屐", icon: "square.split.bottomrightquarter", tier: .low, category: .wear(.shoes),
                 effectDesc: "每次胜利 +1 金币", maxDurability: 9, price: 12, restrictedTo: nil, lore: "踏踏作响。想偷袭的话，换一双。", coinBonus: 1),
        GameItem(id: "cloudBoots", name: "踏云靴", icon: "wind", tier: .mid, category: .wear(.shoes),
                 effectDesc: "受击伤害 -1", maxDurability: 20, price: 55, restrictedTo: nil, lore: "传说能踏云而行，实际只是走路轻一点。", defenseBonus: 1),
        GameItem(id: "ironBoots", name: "铁履", icon: "hammer.fill", tier: .mid, category: .wear(.shoes),
                 effectDesc: "受击 -1，耐久高", maxDurability: 30, price: 60, restrictedTo: nil, lore: "踢一脚能踢断树。代价是走十里就累。", defenseBonus: 1),
        GameItem(id: "hunterBoots", name: "猎行靴", icon: "scope", tier: .mid, category: .wear(.shoes),
                 effectDesc: "限时战斗 +5 秒", maxDurability: 20, price: 58, restrictedTo: nil, lore: "鞋底纹路是猎人自己刻的，为了不被猎物听见。", timeBonus: 5),
        GameItem(id: "windBoots", name: "疾风履", icon: "wind.snow", tier: .high, category: .wear(.shoes),
                 effectDesc: "限时战斗 +6 秒", maxDurability: 18, price: 100, restrictedTo: nil, lore: "穿上它跑起来，风会替你让路。", timeBonus: 6),
        GameItem(id: "earthBoots", name: "厚土战靴", icon: "square.3.layers.3d", tier: .high, category: .wear(.shoes),
                 effectDesc: "受击 -2", maxDurability: 20, price: 105, restrictedTo: nil, lore: "脚踏实地，是最朴素的天赋。", defenseBonus: 2),
        GameItem(id: "thiefBoots", name: "无声靴", icon: "moon.zzz", tier: .high, category: .wear(.shoes),
                 effectDesc: "限时 +7 秒（词行者专属）", maxDurability: 18, price: 108, restrictedTo: .rogue, lore: "鞋底垫了七层棉。走过雪地不留声，只留印。", timeBonus: 7),
        GameItem(id: "healerSandals", name: "行医草履", icon: "cross.case", tier: .high, category: .wear(.shoes),
                 effectDesc: "每次胜利回血 1（词医者专属）", maxDurability: 20, price: 100, restrictedTo: .healer, lore: "走遍十六州的鞋。每一道磨痕后面都有一条被救的命。", regenPerWin: 1),
        GameItem(id: "swiftBoots", name: "疾影靴", icon: "hare.fill", tier: .rare, category: .wear(.shoes),
                 effectDesc: "受击伤害 -1，每次胜利 +1 金币", maxDurability: 18, price: 140, restrictedTo: nil, lore: "影子追不上主人，就是这双靴子的传说。", defenseBonus: 1, coinBonus: 1),
        GameItem(id: "lotusBoots", name: "青莲步履", icon: "leaf.circle.fill", tier: .rare, category: .wear(.shoes),
                 effectDesc: "每次胜利回血 1", maxDurability: 18, price: 150, restrictedTo: nil, lore: "步步生莲。落脚处的青苔都活了过来。", regenPerWin: 1),
        GameItem(id: "thunderBoots", name: "雷步战靴", icon: "bolt.horizontal.circle.fill", tier: .legendary, category: .wear(.shoes),
                 effectDesc: "命中 +1，限时 +5 秒", maxDurability: 20, price: 260, restrictedTo: nil, lore: "每一步都像一记闷雷。敌人还没看清，你已经到跟前了。", damageBonus: 1, timeBonus: 5),
        GameItem(id: "voidBoots", name: "虚空踏", icon: "circle.dashed", tier: .legendary, category: .wear(.shoes),
                 effectDesc: "受击 -2，胜利 +2 金币", maxDurability: 20, price: 270, restrictedTo: nil, lore: "它踩着的不是地面，是「两个词之间的空白」。", defenseBonus: 2, coinBonus: 2),
        GameItem(id: "sunChaser", name: "逐日金履", icon: "sunrise.fill", tier: .goldLegend, category: .wear(.shoes),
                 effectDesc: "受击伤害 -2，限时战斗 +5 秒", maxDurability: 22, price: 380, restrictedTo: nil, lore: "夸父逐日未成，鞋留了下来。谁穿上，都得替他跑完那一段。", defenseBonus: 2, timeBonus: 5),
        GameItem(id: "skyWalker", name: "凌霄天履", icon: "airplane", tier: .goldLegend, category: .wear(.shoes),
                 effectDesc: "受击 -2，命中 +1，限时 +5 秒", maxDurability: 24, price: 480, restrictedTo: nil, lore: "登天的最后一段路，没有台阶。所以要有这双鞋。", damageBonus: 1, defenseBonus: 2, timeBonus: 5),
        GameItem(id: "bambooShoes", name: "竹编鞋", icon: "leaf", tier: .low, category: .wear(.shoes),
                 effectDesc: "限时战斗 +3 秒", maxDurability: 10, price: 14, restrictedTo: nil, lore: "夏天穿最舒服，冬天……换一双吧。", timeBonus: 3),
        GameItem(id: "ropeSandals", name: "麻绳凉履", icon: "line.3.horizontal", tier: .low, category: .wear(.shoes),
                 effectDesc: "受击伤害 -1", maxDurability: 9, price: 11, restrictedTo: nil, lore: "麻绳绕脚，简陋但结实。", defenseBonus: 1),
        GameItem(id: "silverBoots", name: "银纹靴", icon: "sparkle", tier: .mid, category: .wear(.shoes),
                 effectDesc: "受击 -1，胜利 +1 金币", maxDurability: 22, price: 66, restrictedTo: nil, lore: "靴面银纹在月下会亮，很适合走夜路（也很适合被发现）。", defenseBonus: 1, coinBonus: 1),
        GameItem(id: "stoneBoots", name: "山岩靴", icon: "cube", tier: .mid, category: .wear(.shoes),
                 effectDesc: "受击伤害 -1", maxDurability: 32, price: 62, restrictedTo: nil, lore: "山民所制，走碎石路如履平地。", defenseBonus: 1),
        GameItem(id: "mageSlippers", name: "星语软靴", icon: "wand.and.rays.inverse", tier: .high, category: .wear(.shoes),
                 effectDesc: "限时 +6 秒（词法师专属）", maxDurability: 18, price: 104, restrictedTo: .mage, lore: "法师不爱走路，所以把靴子做得很轻。", timeBonus: 6),
        GameItem(id: "knightSabatons", name: "誓约铁靴", icon: "shield.fill", tier: .high, category: .wear(.shoes),
                 effectDesc: "受击 -2（词剑士专属）", maxDurability: 28, price: 112, restrictedTo: .knight, lore: "铁靴踏地的声音就是他的战鼓。", defenseBonus: 2),
        GameItem(id: "gamblerLoafers", name: "红运皮鞋", icon: "suit.heart.fill", tier: .rare, category: .wear(.shoes),
                 effectDesc: "胜利 +3 金币（词赌徒专属）", maxDurability: 16, price: 160, restrictedTo: .gambler, lore: "每次赢钱他都擦一遍鞋。鞋擦得越亮，赌得越大。", coinBonus: 3),
        GameItem(id: "phoenixBoots", name: "焚羽战靴", icon: "flame.circle.fill", tier: .legendary, category: .wear(.shoes),
                 effectDesc: "命中 +1，每次胜利回血 1", maxDurability: 20, price: 275, restrictedTo: nil, lore: "踏火不焚。据说不死鸟落地时就穿着它。", damageBonus: 1, regenPerWin: 1),
        // ── 武器（刀剑弓杖锤枪，不分类展示）
        GameItem(id: "woodSword", name: "青竹剑", icon: "chevron.forward.2", tier: .low, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 8, price: 20, restrictedTo: nil, lore: "削竹为剑，是所有剑客的开始。别笑，它砍过妖。", damageBonus: 1),
        GameItem(id: "rustyBlade", name: "锈铁刀", icon: "line.diagonal", tier: .low, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 9, price: 22, restrictedTo: nil, lore: "锈是锈，锋还在。", damageBonus: 1),
        GameItem(id: "shortBow", name: "猎人短弓", icon: "scope", tier: .low, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 10, price: 26, restrictedTo: nil, lore: "打兔子用的。打词妖也行，只是要多打几箭。", damageBonus: 1),
        GameItem(id: "apprenticeWand", name: "学徒木杖", icon: "wand.and.rays.inverse", tier: .low, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 10, price: 28, restrictedTo: nil, lore: "第一根法杖。挥起来像在指挥一群不听话的字母。", damageBonus: 1),
        GameItem(id: "woodStaff", name: "枣木棍", icon: "line.horizontal.3.decrease", tier: .low, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 12, price: 18, restrictedTo: nil, lore: "路边捡的棍子。趁手得出乎意料。", damageBonus: 1),
        GameItem(id: "stoneAxe", name: "石斧", icon: "hammer", tier: .low, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 10, price: 21, restrictedTo: nil, lore: "最古老的武器。简单、直接、有效。", damageBonus: 1),
        GameItem(id: "throwKnife", name: "飞刀", icon: "paperplane.fill", tier: .low, category: .weapon,
                 effectDesc: "命中 +1，限时 +3 秒", maxDurability: 8, price: 25, restrictedTo: nil, lore: "小李飞刀，例无虚发——那是别人。你的还得练。", damageBonus: 1, timeBonus: 3),
        GameItem(id: "ironBlade", name: "玄铁重刀", icon: "bolt.horizontal.fill", tier: .mid, category: .weapon,
                 effectDesc: "命中伤害 +1，更耐用", maxDurability: 20, price: 60, restrictedTo: nil, lore: "重刀无锋，大巧不工。", damageBonus: 1),
        GameItem(id: "steelSpear", name: "精钢长枪", icon: "arrow.up.right", tier: .mid, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 18, price: 65, restrictedTo: nil, lore: "一寸长一寸强。枪法讲的是距离，不是力气。", damageBonus: 1),
        GameItem(id: "windDagger", name: "风刃匕", icon: "leaf.arrow.circlepath", tier: .mid, category: .weapon,
                 effectDesc: "命中 +1，限时 +4 秒", maxDurability: 15, price: 72, restrictedTo: nil, lore: "快，是唯一的道理。", damageBonus: 1, timeBonus: 4),
        GameItem(id: "goldDice", name: "鎏金骰子", icon: "die.face.6.fill", tier: .mid, category: .weapon,
                 effectDesc: "命中伤害 +1（词赌徒专属）", maxDurability: 15, price: 70, restrictedTo: .gambler, lore: "他把骰子当武器扔出去。据说从没扔出过一点。", damageBonus: 1),
        GameItem(id: "healerScalpel", name: "青囊刀", icon: "cross.vial", tier: .mid, category: .weapon,
                 effectDesc: "命中 +1，每次胜利回血 1（词医者专属）", maxDurability: 16, price: 78, restrictedTo: .healer, lore: "能救人也能杀人。医者的刀，比谁都清楚这两者的距离。", damageBonus: 1, regenPerWin: 1),
        GameItem(id: "bronzeSword", name: "青铜古剑", icon: "chevron.up", tier: .mid, category: .weapon,
                 effectDesc: "命中伤害 +1", maxDurability: 24, price: 62, restrictedTo: nil, lore: "从古墓里带出来的。剑身上的铭文没人认得。", damageBonus: 1),
        GameItem(id: "crossbow", name: "手弩", icon: "arrow.right.to.line", tier: .mid, category: .weapon,
                 effectDesc: "命中 +1，限时 +3 秒", maxDurability: 16, price: 68, restrictedTo: nil, lore: "不需要臂力，只需要冷静。", damageBonus: 1, timeBonus: 3),
        GameItem(id: "frostBow", name: "寒霜长弓", icon: "scope", tier: .high, category: .weapon,
                 effectDesc: "命中伤害 +1，每次胜利 +1 金币", maxDurability: 18, price: 110, restrictedTo: nil, lore: "弦一拉，方圆三尺结霜。射出去的箭自带回音。", damageBonus: 1, coinBonus: 1),
        GameItem(id: "magicWand", name: "星芒法杖", icon: "wand.and.rays", tier: .high, category: .weapon,
                 effectDesc: "命中伤害 +2", maxDurability: 14, price: 130, restrictedTo: nil, lore: "杖头星芒会随咒语明暗。背错单词时它会黯下去，很伤自尊。", damageBonus: 2),
        GameItem(id: "moonBlade", name: "月牙弯刀", icon: "moon.fill", tier: .high, category: .weapon,
                 effectDesc: "命中伤害 +2", maxDurability: 15, price: 128, restrictedTo: nil, lore: "刀如新月。挥出去的弧线，据说能割断月光。", damageBonus: 2),
        GameItem(id: "thunderHammer", name: "雷霆战锤", icon: "hammer.fill", tier: .high, category: .weapon,
                 effectDesc: "命中 +2，笨重", maxDurability: 12, price: 120, restrictedTo: nil, lore: "举起来很慢，落下去很快。这就够了。", damageBonus: 2),
        GameItem(id: "knightLongsword", name: "誓约长剑", icon: "shield.righthalf.filled", tier: .high, category: .weapon,
                 effectDesc: "命中 +2（词剑士专属）", maxDurability: 20, price: 135, restrictedTo: .knight, lore: "剑柄缠布已被血浸透多次。剑士说：它记得每一个我救下的人。", damageBonus: 2),
        GameItem(id: "mageOrb", name: "秘文法球", icon: "circle.hexagongrid.circle.fill", tier: .high, category: .weapon,
                 effectDesc: "命中 +2（词法师专属）", maxDurability: 14, price: 138, restrictedTo: .mage, lore: "球里封着一整本词典。摇一摇，会听见沙沙的翻页声。", damageBonus: 2),
        GameItem(id: "thiefFangs", name: "双影匕", icon: "arrow.left.arrow.right", tier: .high, category: .weapon,
                 effectDesc: "命中 +2（词行者专属）", maxDurability: 14, price: 132, restrictedTo: .rogue, lore: "一把在明，一把在暗。敌人永远盯错那一把。", damageBonus: 2),
        GameItem(id: "greenDragonBlade", name: "青龙偃月刀", icon: "line.diagonal.arrow", tier: .high, category: .weapon,
                 effectDesc: "命中 +2，受击 -1", maxDurability: 18, price: 145, restrictedTo: nil, lore: "八十二斤。据说某位红脸将军用它温过酒，也斩过将。", damageBonus: 2, defenseBonus: 1),
        GameItem(id: "immortalSword", name: "赤霄仙剑", icon: "burst.fill", tier: .rare, category: .weapon,
                 effectDesc: "命中伤害 +2，剑气纵横", maxDurability: 20, price: 180, restrictedTo: nil, lore: "赤霄一出，斩白蛇于泽中。剑还在，蛇的传说也还在。", damageBonus: 2),
        GameItem(id: "dragonBow", name: "游龙弓", icon: "arrow.up.forward", tier: .rare, category: .weapon,
                 effectDesc: "命中 +2，胜利 +1 金币", maxDurability: 18, price: 190, restrictedTo: nil, lore: "弓身如龙脊。拉满时会有龙吟——也可能只是风声。", damageBonus: 2, coinBonus: 1),
        GameItem(id: "soulStaff", name: "摄魂法杖", icon: "sparkle.magnifyingglass", tier: .rare, category: .weapon,
                 effectDesc: "命中 +2，限时 +5 秒", maxDurability: 16, price: 195, restrictedTo: nil, lore: "它能摄走词妖的魂。副作用是你会梦见那些词。", damageBonus: 2, timeBonus: 5),
        GameItem(id: "gamblerRevolver", name: "六面轮盘", icon: "die.face.6", tier: .rare, category: .weapon,
                 effectDesc: "命中 +2，胜利 +2 金币（词赌徒专属）", maxDurability: 16, price: 200, restrictedTo: .gambler, lore: "六个格子，五个是空的。赌徒偏爱第六格。", damageBonus: 2, coinBonus: 2),
        GameItem(id: "mercyBlade", name: "慈悲刃", icon: "cross.case.fill", tier: .rare, category: .weapon,
                 effectDesc: "命中 +1，每次胜利回血 2（词医者专属）", maxDurability: 18, price: 198, restrictedTo: .healer, lore: "刀名慈悲，因为它总是先救人，后杀敌。", damageBonus: 1, regenPerWin: 2),
        GameItem(id: "fangOfWolf", name: "狼牙棒", icon: "pawprint.fill", tier: .rare, category: .weapon,
                 effectDesc: "命中 +3，受击 +0", maxDurability: 16, price: 185, restrictedTo: nil, lore: "满身尖刺，毫无技巧，全是力量。", damageBonus: 3),
        GameItem(id: "phoenixSpear", name: "凤翎枪", icon: "flame.fill", tier: .legendary, category: .weapon,
                 effectDesc: "命中伤害 +3", maxDurability: 18, price: 320, restrictedTo: nil, lore: "枪尖一点火，能烧尽一整页错词。", damageBonus: 3),
        GameItem(id: "frostFang", name: "玄冰牙", icon: "snowflake.circle.fill", tier: .legendary, category: .weapon,
                 effectDesc: "命中 +3，受击 -1", maxDurability: 18, price: 340, restrictedTo: nil, lore: "拔出时寒气逼人，连词妖的呼吸都会凝住。", damageBonus: 3, defenseBonus: 1),
        GameItem(id: "starBow", name: "落星神弓", icon: "star.circle.fill", tier: .legendary, category: .weapon,
                 effectDesc: "命中 +3，胜利 +2 金币", maxDurability: 16, price: 350, restrictedTo: nil, lore: "它射下来的不是箭，是星。所以每次只能射一发。", damageBonus: 3, coinBonus: 2),
        GameItem(id: "shadowEdge", name: "无影剑", icon: "circle.dashed.inset.filled", tier: .legendary, category: .weapon,
                 effectDesc: "命中 +3（词行者专属）", maxDurability: 16, price: 345, restrictedTo: .rogue, lore: "剑无影，出鞘时天下人只看见结果。", damageBonus: 3),
        GameItem(id: "staffOfWisdom", name: "智慧长杖", icon: "book.circle.fill", tier: .legendary, category: .weapon,
                 effectDesc: "命中 +2，限时 +8 秒（词法师专属）", maxDurability: 18, price: 355, restrictedTo: .mage, lore: "「我们不是要跑得更快，是要想得更清楚。」——杖上唯一的刻字。", damageBonus: 2, timeBonus: 8),
        GameItem(id: "xuanyuanSword", name: "轩辕圣剑", icon: "bolt.shield.fill", tier: .goldLegend, category: .weapon,
                 effectDesc: "命中伤害 +3，每场战斗额外一次格挡", maxDurability: 22, price: 520, restrictedTo: nil, lore: "黄帝铸之，蚩尤畏之。剑在，则言正；言正，则词不惑。", damageBonus: 3, extraShield: true),
        GameItem(id: "chaosStaff", name: "混元道杖", icon: "sparkles.rectangle.stack", tier: .goldLegend, category: .weapon,
                 effectDesc: "命中 +4", maxDurability: 20, price: 600, restrictedTo: nil, lore: "一杖开天。它不背单词，它定义单词。", damageBonus: 4),
        GameItem(id: "dragonSlayer", name: "屠龙巨剑", icon: "flame.circle", tier: .goldLegend, category: .weapon,
                 effectDesc: "命中 +4，受击 -1", maxDurability: 20, price: 640, restrictedTo: nil, lore: "剑很大，很重，很钝。但它真的杀过龙。", damageBonus: 4, defenseBonus: 1),
        GameItem(id: "excalibur", name: "湖中圣剑", icon: "drop.circle.fill", tier: .goldLegend, category: .weapon,
                 effectDesc: "命中 +3，受击 -2", maxDurability: 22, price: 660, restrictedTo: nil, lore: "石中之剑，唯真王可拔。你拔出来了——所以别辜负它。", damageBonus: 3, defenseBonus: 2),
        GameItem(id: "monkeyStaff", name: "如意金箍棒", icon: "arrow.up.and.down.circle.fill", tier: .goldLegend, category: .weapon,
                 effectDesc: "命中 +4，限时 +5 秒", maxDurability: 22, price: 700, restrictedTo: nil, lore: "一万三千五百斤，可大可小。「俺去也」——它的前任主人如是说。", damageBonus: 4, timeBonus: 5),
        // ── 药水
        GameItem(id: "smallHerb", name: "止血草", icon: "leaf.fill", tier: .low, category: .potion,
                 effectDesc: "服用回复 6 点生命", maxDurability: 1, price: 9, restrictedTo: nil, lore: "随手能采的野草，嚼碎按在伤口上。土法子，但管用。", healAmount: 6),
        GameItem(id: "energyTea", name: "凝神茶", icon: "cup.and.saucer.fill", tier: .low, category: .potion,
                 effectDesc: "服用回复 8 点生命", maxDurability: 1, price: 12, restrictedTo: nil, lore: "背单词背到犯困时来一杯。", healAmount: 8),
        GameItem(id: "healPill", name: "疗伤丹", icon: "pill.fill", tier: .low, category: .potion,
                 effectDesc: "服用回复 10 点生命", maxDurability: 1, price: 15, restrictedTo: nil, lore: "最常见的丹药，药铺整坛卖。", healAmount: 10),
        GameItem(id: "riceWine", name: "米酒", icon: "wineglass.fill", tier: .low, category: .potion,
                 effectDesc: "服用回复 8 点生命", maxDurability: 1, price: 11, restrictedTo: nil, lore: "酒能壮胆。壮完胆，单词还是不认识。", healAmount: 8),
        GameItem(id: "honeyWater", name: "蜜水", icon: "drop.circle", tier: .low, category: .potion,
                 effectDesc: "服用回复 7 点生命", maxDurability: 1, price: 10, restrictedTo: nil, lore: "甜的。喝一口就觉得世界温柔了些。", healAmount: 7),
        GameItem(id: "smallSand", name: "碎时沙", icon: "hourglass.bottomhalf.filled", tier: .low, category: .potion,
                 effectDesc: "限时战斗 +8 秒", maxDurability: 1, price: 14, restrictedTo: nil, lore: "沙漏里漏下的一点点时间。省着用。", timeBonus: 8),
        GameItem(id: "bigPill", name: "大还丹", icon: "pills.fill", tier: .mid, category: .potion,
                 effectDesc: "服用回复 20 点生命", maxDurability: 1, price: 35, restrictedTo: nil, lore: "宗门发的救命丹，一年只发两颗。", healAmount: 20),
        GameItem(id: "timeSand", name: "时之沙", icon: "hourglass", tier: .mid, category: .potion,
                 effectDesc: "限时战斗中使用 +15 秒", maxDurability: 1, price: 30, restrictedTo: nil, lore: "握紧它，秒针会犹豫一下。", timeBonus: 15),
        GameItem(id: "jadeDew", name: "玉髓露", icon: "drop.fill", tier: .mid, category: .potion,
                 effectDesc: "服用回复 25 点生命", maxDurability: 1, price: 42, restrictedTo: nil, lore: "玉中凝出的一滴髓液。据说能补回熬夜背书的元气。", healAmount: 25),
        GameItem(id: "herbSoup", name: "十全大补汤", icon: "takeoutbag.and.cup.and.straw.fill", tier: .mid, category: .potion,
                 effectDesc: "服用回复 22 点生命", maxDurability: 1, price: 38, restrictedTo: nil, lore: "药材放了十种，味道很难形容。喝完确实精神。", healAmount: 22),
        GameItem(id: "clarityPill", name: "醒神丸", icon: "brain.head.profile", tier: .mid, category: .potion,
                 effectDesc: "限时战斗 +18 秒", maxDurability: 1, price: 40, restrictedTo: nil, lore: "一入口，脑子里的雾就散了。", timeBonus: 18),
        GameItem(id: "superPill", name: "醍醐灌顶露", icon: "drop.degreesign.fill", tier: .high, category: .potion,
                 effectDesc: "服用回复 35 点生命", maxDurability: 1, price: 70, restrictedTo: nil, lore: "醍醐灌顶。喝完那一瞬间，你会觉得所有词都认识了（只是错觉）。", healAmount: 35),
        GameItem(id: "chronoSand", name: "岁月金沙", icon: "hourglass.tophalf.filled", tier: .high, category: .potion,
                 effectDesc: "限时战斗 +25 秒", maxDurability: 1, price: 65, restrictedTo: nil, lore: "金沙一粒，值一刻钟。奢侈，但有时候就得奢侈。", timeBonus: 25),
        GameItem(id: "spiritBrew", name: "灵酿", icon: "wineglass", tier: .high, category: .potion,
                 effectDesc: "服用回复 30 点生命", maxDurability: 1, price: 62, restrictedTo: nil, lore: "仙人自酿。凡人喝了会睡三天，醒来伤全好了。", healAmount: 30),
        GameItem(id: "dragonBlood", name: "龙血丹", icon: "flame.circle.fill", tier: .rare, category: .potion,
                 effectDesc: "服用回复 45 点生命", maxDurability: 1, price: 100, restrictedTo: nil, lore: "以真龙之血炼制。喝下去喉咙会烧，然后骨头会响。", healAmount: 45),
        GameItem(id: "phoenixTear", name: "凤凰泪", icon: "drop.triangle.fill", tier: .rare, category: .potion,
                 effectDesc: "服用回复 50 点生命", maxDurability: 1, price: 110, restrictedTo: nil, lore: "凤凰垂泪，能疗百伤。它哭一次，你活一次。", healAmount: 50),
        GameItem(id: "nirvanaSand", name: "涅槃沙", icon: "hourglass.circle.fill", tier: .rare, category: .potion,
                 effectDesc: "限时战斗 +32 秒", maxDurability: 1, price: 105, restrictedTo: nil, lore: "沙落尽时是终点。所以它总在最后一刻停下。", timeBonus: 32),
        GameItem(id: "fullElixir", name: "九转还魂液", icon: "sparkles", tier: .legendary, category: .potion,
                 effectDesc: "服用回满生命", maxDurability: 1, price: 150, restrictedTo: nil, lore: "九转九炼，一滴还魂。药王说：这药救不了不肯自救的人。", healAmount: 99),
        GameItem(id: "eternitySand", name: "永恒沙漏", icon: "hourglass.bottomhalf.filled", tier: .legendary, category: .potion,
                 effectDesc: "限时战斗 +40 秒", maxDurability: 1, price: 140, restrictedTo: nil, lore: "把它倒过来，时间也跟着倒过来——一小会儿。", timeBonus: 40),
        GameItem(id: "immortalPeach", name: "蟠桃仙露", icon: "circle.fill", tier: .goldLegend, category: .potion,
                 effectDesc: "服用回满生命，仙气盈然", maxDurability: 1, price: 220, restrictedTo: nil, lore: "三千年一开花，三千年一结果。你手里这瓶，是某只猴子漏下的。", healAmount: 99),
        GameItem(id: "ninefoldPill", name: "太上金丹", icon: "circle.circle.fill", tier: .goldLegend, category: .potion,
                 effectDesc: "服用回满生命", maxDurability: 1, price: 240, restrictedTo: nil, lore: "炉中丹成，天雷都要退三分。吃之前记得先看看有没有猴毛。", healAmount: 99),
        GameItem(id: "timelessHour", name: "无尽时轮", icon: "clock.arrow.2.circlepath", tier: .goldLegend, category: .potion,
                 effectDesc: "限时战斗 +60 秒", maxDurability: 1, price: 260, restrictedTo: nil, lore: "轮转不休，时间在它面前只是个提议。", timeBonus: 60),
        GameItem(id: "moonlightBox", name: "月光宝盒", icon: "moon.stars.fill", tier: .legendary, category: .potion,
                 effectDesc: "死亡时自动发动：随机回到当前境界任一节点", maxDurability: 1, price: 320, restrictedTo: nil, lore: "月宫遗落的秘盒，能在生死一瞬逆转时空。传说它只救有缘人——而有缘，往往就是兜里有它。"),
        // ── 宠物
        GameItem(id: "bookWorm", name: "书虫", icon: "ant.fill", tier: .low, category: .pet,
                 effectDesc: "每次胜利额外 +1 金币", maxDurability: 99, price: 35, restrictedTo: nil, lore: "真的会吃书。好在它只吃你背错的那几页。", coinBonus: 1),
        GameItem(id: "inkCat", name: "墨玉猫", icon: "cat.fill", tier: .low, category: .pet,
                 effectDesc: "每次胜利回血 1", maxDurability: 99, price: 45, restrictedTo: nil, lore: "踩着墨迹在书页上走来走去，还理直气壮。", regenPerWin: 1),
        GameItem(id: "clayDog", name: "泥塑犬", icon: "dog.fill", tier: .low, category: .pet,
                 effectDesc: "每次胜利 +1 金币", maxDurability: 99, price: 30, restrictedTo: nil, lore: "庙会上买的泥狗。某天早上，它自己换了个姿势。", coinBonus: 1),
        GameItem(id: "firefly", name: "流萤", icon: "sparkles", tier: .low, category: .pet,
                 effectDesc: "限时战斗 +3 秒", maxDurability: 99, price: 32, restrictedTo: nil, lore: "夜里替你照亮书页的小东西。", timeBonus: 3),
        GameItem(id: "sparrow", name: "灰雀", icon: "bird", tier: .low, category: .pet,
                 effectDesc: "受击伤害 -1", maxDurability: 99, price: 38, restrictedTo: nil, lore: "停在肩上叽叽喳喳，据说能预警危险。", defenseBonus: 1),
        GameItem(id: "wordPup", name: "词灵犬", icon: "pawprint.fill", tier: .mid, category: .pet,
                 effectDesc: "每次胜利额外 +1 金币", maxDurability: 99, price: 80, restrictedTo: nil, lore: "能闻出哪个词你记不牢，然后叼过来放你手上。", coinBonus: 1),
        GameItem(id: "cloudCrane", name: "云中鹤", icon: "bird.fill", tier: .mid, category: .pet,
                 effectDesc: "限时战斗 +5 秒", maxDurability: 99, price: 90, restrictedTo: nil, lore: "鹤唳一声，人心里的急躁就散了。", timeBonus: 5),
        GameItem(id: "greenSnake", name: "青蛇", icon: "lizard", tier: .mid, category: .pet,
                 effectDesc: "命中伤害 +1", maxDurability: 99, price: 85, restrictedTo: nil, lore: "盘在剑鞘上打盹。你出剑时它比你更兴奋。", damageBonus: 1),
        GameItem(id: "stoneLion", name: "小石狮", icon: "cube.fill", tier: .mid, category: .pet,
                 effectDesc: "受击伤害 -1", maxDurability: 99, price: 88, restrictedTo: nil, lore: "门口石狮的崽。走路砰砰响，但真挡得住。", defenseBonus: 1),
        GameItem(id: "fireFox", name: "赤焰狐", icon: "flame.fill", tier: .high, category: .pet,
                 effectDesc: "命中伤害 +1", maxDurability: 99, price: 140, restrictedTo: nil, lore: "尾巴一扫，词妖就着火了。它自己却不怕烫。", damageBonus: 1),
        GameItem(id: "stoneTurtle", name: "玄石龟", icon: "tortoise.fill", tier: .high, category: .pet,
                 effectDesc: "受击伤害 -1", maxDurability: 99, price: 150, restrictedTo: nil, lore: "慢，但从来没被打伤过。它说这叫策略。", defenseBonus: 1),
        GameItem(id: "healingDeer", name: "灵鹿", icon: "hare", tier: .high, category: .pet,
                 effectDesc: "每次胜利回血 1", maxDurability: 99, price: 145, restrictedTo: nil, lore: "鹿角上长着草药。它会自己叼来给你。", regenPerWin: 1),
        GameItem(id: "moneyToad", name: "金蟾", icon: "circle.hexagongrid.circle", tier: .high, category: .pet,
                 effectDesc: "每次胜利 +2 金币", maxDurability: 99, price: 148, restrictedTo: nil, lore: "口含金钱的三足蟾。招财，但很吵。", coinBonus: 2),
        GameItem(id: "inkKirin", name: "墨麒麟", icon: "hare.fill", tier: .rare, category: .pet,
                 effectDesc: "受击伤害 -1，灵性十足", maxDurability: 99, price: 190, restrictedTo: nil, lore: "麒麟本不该现世。它说：因为你在认真背书，所以我来看看。", defenseBonus: 1),
        GameItem(id: "thunderBird", name: "雷羽鹰", icon: "bolt.fill", tier: .rare, category: .pet,
                 effectDesc: "命中 +1，限时 +4 秒", maxDurability: 99, price: 200, restrictedTo: nil, lore: "振翅带雷。它俯冲时，你只需要跟着念出那个词。", damageBonus: 1, timeBonus: 4),
        GameItem(id: "whiteTiger", name: "白虎幼崽", icon: "pawprint.circle.fill", tier: .rare, category: .pet,
                 effectDesc: "命中 +1，受击 -1", maxDurability: 99, price: 210, restrictedTo: nil, lore: "西方白虎，主兵戈。现在它咬着你的裤脚要吃的。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "pixiu", name: "吞词貔貅", icon: "dollarsign.circle.fill", tier: .legendary, category: .pet,
                 effectDesc: "每次胜利额外 +4 金币", maxDurability: 99, price: 340, restrictedTo: nil, lore: "貔貅无肛，只进不出。它吞下的每个词都会变成金币。", coinBonus: 4),
        GameItem(id: "nineTailFox", name: "九尾灵狐", icon: "sparkle", tier: .legendary, category: .pet,
                 effectDesc: "命中 +1，受击 -1", maxDurability: 99, price: 360, restrictedTo: nil, lore: "九条尾巴，每条记一千个词。它常笑你记性差。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "qilin", name: "麒麟", icon: "hare.circle.fill", tier: .legendary, category: .pet,
                 effectDesc: "受击 -2", maxDurability: 99, price: 370, restrictedTo: nil, lore: "麒麟出，圣人生。它跟着你，大概是看错人了——也许没看错。", defenseBonus: 2),
        GameItem(id: "goldenCrow", name: "金乌雏", icon: "bird.circle.fill", tier: .goldLegend, category: .pet,
                 effectDesc: "命中伤害 +1，限时战斗 +5 秒", maxDurability: 99, price: 560, restrictedTo: nil, lore: "十日并出时被射落的那只金乌，如今只剩一只雏鸟，落在你肩上。", damageBonus: 1, timeBonus: 5),
        GameItem(id: "dragonWhelp", name: "幼龙", icon: "lizard.fill", tier: .goldLegend, category: .pet,
                 effectDesc: "命中 +2，受击 -1", maxDurability: 99, price: 620, restrictedTo: nil, lore: "它还不会飞，但已经会喷火了。请注意书本。", damageBonus: 2, defenseBonus: 1),
        GameItem(id: "phoenixChick", name: "凤雏", icon: "flame.circle.fill", tier: .goldLegend, category: .pet,
                 effectDesc: "命中 +1，每次胜利回血 2", maxDurability: 99, price: 600, restrictedTo: nil, lore: "凤凰的孩子。它每次重生都会长大一点，你每次背词也是。", damageBonus: 1, regenPerWin: 2),
        // ── 精灵
        GameItem(id: "dewFae", name: "露珠精灵", icon: "drop.circle.fill", tier: .low, category: .sprite,
                 effectDesc: "每次胜利 +1 金币", maxDurability: 99, price: 38, restrictedTo: nil, lore: "清晨叶尖上的一滴露。它以为自己是海。", coinBonus: 1),
        GameItem(id: "fireflyFae", name: "萤穗精灵", icon: "sparkles", tier: .low, category: .sprite,
                 effectDesc: "每次战斗胜利回复 1 点生命", maxDurability: 99, price: 40, restrictedTo: nil, lore: "它一闪一闪的，像在替你数背过的词。", regenPerWin: 1),
        GameItem(id: "dustFae", name: "尘光精灵", icon: "sparkle", tier: .low, category: .sprite,
                 effectDesc: "限时战斗 +3 秒", maxDurability: 99, price: 34, restrictedTo: nil, lore: "书页翻动时飞起的那些光尘，其实都是它。", timeBonus: 3),
        GameItem(id: "mossFae", name: "苔灵", icon: "leaf", tier: .low, category: .sprite,
                 effectDesc: "受击伤害 -1", maxDurability: 99, price: 36, restrictedTo: nil, lore: "住在墙角的小家伙。安静，但很结实。", defenseBonus: 1),
        GameItem(id: "leafFae", name: "叶灵", icon: "leaf.circle.fill", tier: .mid, category: .sprite,
                 effectDesc: "受击伤害 -1", maxDurability: 99, price: 85, restrictedTo: nil, lore: "一片叶子成精。它最擅长的事是「不被注意」。", defenseBonus: 1),
        GameItem(id: "emberFae", name: "火苗精灵", icon: "flame.circle", tier: .mid, category: .sprite,
                 effectDesc: "命中伤害 +1", maxDurability: 99, price: 95, restrictedTo: nil, lore: "性子急。你答得慢一点，它就烧你一下。", damageBonus: 1),
        GameItem(id: "brookFae", name: "溪灵", icon: "water.waves", tier: .mid, category: .sprite,
                 effectDesc: "每次胜利回血 1", maxDurability: 99, price: 90, restrictedTo: nil, lore: "潺潺的水声里藏着它的哼唱，据说能催眠词妖。", regenPerWin: 1),
        GameItem(id: "windFae", name: "风铃精灵", icon: "wind", tier: .mid, category: .sprite,
                 effectDesc: "限时战斗 +5 秒", maxDurability: 99, price: 92, restrictedTo: nil, lore: "它一路推着你走。慢了，它就在耳边吹口哨。", timeBonus: 5),
        GameItem(id: "chronoFae", name: "时汐精灵", icon: "clock.badge.checkmark.fill", tier: .high, category: .sprite,
                 effectDesc: "限时战斗时限 +8 秒", maxDurability: 99, price: 150, restrictedTo: nil, lore: "它数着秒过日子，所以特别懂「来不及」的滋味。", timeBonus: 8),
        GameItem(id: "coinFae", name: "金铃精灵", icon: "bell.circle.fill", tier: .high, category: .sprite,
                 effectDesc: "每次胜利 +2 金币", maxDurability: 99, price: 145, restrictedTo: nil, lore: "每赚一枚金币就叮一声。它是最诚实的账房。", coinBonus: 2),
        GameItem(id: "inkFae", name: "墨灵", icon: "pencil.circle.fill", tier: .high, category: .sprite,
                 effectDesc: "命中 +1，胜利 +1 金币", maxDurability: 99, price: 152, restrictedTo: nil, lore: "住在砚台里。你写错字它会把墨弄脏，以示抗议。", damageBonus: 1, coinBonus: 1),
        GameItem(id: "healFae", name: "药灵", icon: "cross.circle", tier: .high, category: .sprite,
                 effectDesc: "每次胜利回血 1", maxDurability: 99, price: 148, restrictedTo: nil, lore: "背着小药篓到处跑，见谁受伤都要管。", regenPerWin: 1),
        GameItem(id: "swordFae", name: "剑意精灵", icon: "wand.and.stars.inverse", tier: .rare, category: .sprite,
                 effectDesc: "命中伤害 +1", maxDurability: 99, price: 200, restrictedTo: nil, lore: "它本身就是一道剑意。剑客死了，剑意留下来找新主人。", damageBonus: 1),
        GameItem(id: "shieldFae", name: "护心精灵", icon: "shield.checkered", tier: .rare, category: .sprite,
                 effectDesc: "每场战斗额外一次格挡", maxDurability: 99, price: 210, restrictedTo: nil, lore: "它总挡在你身前，明明只有巴掌大。", extraShield: true),
        GameItem(id: "starletFae", name: "小星灵", icon: "star.circle", tier: .rare, category: .sprite,
                 effectDesc: "命中 +1，限时 +4 秒", maxDurability: 99, price: 205, restrictedTo: nil, lore: "从星河里掉下来的碎片，还带着一点点亮。", damageBonus: 1, timeBonus: 4),
        GameItem(id: "mendFae", name: "回春精灵", icon: "cross.circle.fill", tier: .legendary, category: .sprite,
                 effectDesc: "每次胜利回血 2", maxDurability: 99, price: 320, restrictedTo: nil, lore: "妙手回春不是医术，是它偷偷帮的忙。", regenPerWin: 2),
        GameItem(id: "starFae", name: "星辉精灵", icon: "star.circle.fill", tier: .legendary, category: .sprite,
                 effectDesc: "命中 +1，受击 -1", maxDurability: 99, price: 340, restrictedTo: nil, lore: "它披着一整条星河当披风，走起路来银光四散。", damageBonus: 1, defenseBonus: 1),
        GameItem(id: "dreamFae", name: "梦纹精灵", icon: "moon.zzz.fill", tier: .legendary, category: .sprite,
                 effectDesc: "受击 -2", maxDurability: 99, price: 330, restrictedTo: nil, lore: "它把敌人的攻击变成一场梦。梦里你不会痛。", defenseBonus: 2),
        GameItem(id: "primordialFae", name: "鸿蒙小仙", icon: "sparkles.rectangle.stack.fill", tier: .goldLegend, category: .sprite,
                 effectDesc: "命中伤害 +1，受击 -1，每次胜利 +2 金币", maxDurability: 99, price: 580, restrictedTo: nil, lore: "鸿蒙未分时它就在了。它见过第一个词被说出口的那一刻。", damageBonus: 1, defenseBonus: 1, coinBonus: 2),
        GameItem(id: "chaosFae", name: "太虚仙童", icon: "circle.hexagongrid.circle.fill", tier: .goldLegend, category: .sprite,
                 effectDesc: "命中 +2，每次胜利回血 1", maxDurability: 99, price: 640, restrictedTo: nil, lore: "太虚之中一点灵光。它管你叫「小友」，尽管它看着像个孩子。", damageBonus: 2, regenPerWin: 1),
        GameItem(id: "wordSpirit", name: "字灵", icon: "textformat.abc", tier: .goldLegend, category: .sprite,
                 effectDesc: "命中 +2，限时 +6 秒", maxDurability: 99, price: 620, restrictedTo: nil, lore: "它是所有单词的本源精灵。它认得你，因为你背过它。", damageBonus: 2, timeBonus: 6),

        // ── 魔器 · 隐藏品质（😈）真实内容仅「拥有者/魔修」可见，其余时候以 ? 示人
        GameItem(id: "demonShackle", name: "幽冥锁链", icon: "link", tier: .demon, category: .wear(.hat),
                 effectDesc: "受击伤害 -3，每场胜利回复 2 点", maxDurability: 99, price: 9999, restrictedTo: .demon,
                 lore: "上古魔修留下的缚魂枷锁。锁住的是亡魂，护住的是主人。", defenseBonus: 3, regenPerWin: 2),
        GameItem(id: "demonBlade", name: "噬魂刃", icon: "flame.fill", tier: .demon, category: .weapon,
                 effectDesc: "命中伤害 +4", maxDurability: 99, price: 9999, restrictedTo: .demon,
                 lore: "以万千词魂淬炼的魔刃。每斩一词，饮血三分。", damageBonus: 4),
        GameItem(id: "demonHeart", name: "魔心", icon: "heart.fill", tier: .demon, category: .wear(.jewelry),
                 effectDesc: "每次战斗首次受击自动护体", maxDurability: 99, price: 9999, restrictedTo: .demon,
                 lore: "一颗仍在跳动的心脏，从深渊中拾得。遇险之时，它替你挡下致命一击。", extraShield: true),
        GameItem(id: "demonRelic", name: "魔纹古玉", icon: "diamond.fill", tier: .demon, category: .wear(.jewelry),
                 effectDesc: "命中伤害 +2，胜利金币 +5", maxDurability: 99, price: 9999, restrictedTo: .demon,
                 lore: "通体漆黑的古玉，魔纹流转。持有者愈战愈强，也愈战愈富。", damageBonus: 2, coinBonus: 5)
    ]

    /// id → 物品 字典缓存（O(1) 查找；背包/图鉴渲染大量调用，避免线性扫描 250 件）
    static let catalogById: [String: GameItem] = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

    static func item(_ id: String) -> GameItem? {
        catalogById[id]
    }
}

struct OwnedItem: Identifiable, Equatable {
    let id: String
    var durability: Int
    /// 获得时间
    var acquiredAt: Date = Date()
    /// 过期时间（部分道具限时）；nil = 永久
    var expiresAt: Date?

    var item: GameItem? { GameItem.item(id) }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// 剩余时间描述
    var expiryText: String? {
        guard let expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        if remaining <= 0 { return "已过期" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours > 0 ? "剩 \(hours) 小时 \(minutes) 分" : "剩 \(minutes) 分钟"
    }
}
