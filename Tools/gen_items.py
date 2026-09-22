#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 TowerItems.swift 的 catalog（200+ 件，稀有度金字塔 + 大量职业限定 + 经典梗致敬）。"""
import io

ITEMS = []

def add(id_, name, icon, tier, category, desc, dur, price, restricted=None, lore="", **effects):
    ITEMS.append((id_, name, icon, tier, category, desc, dur, price, restricted, lore, effects))

K, M, R, HE, GA = ".knight", ".mage", ".rogue", ".healer", ".gambler"

# ══════════ 穿戴 · 帽子（32）
add("strawHat", "斗笠", "cone.fill", "low", ".wear(.hat)", "江湖气十足的收藏品", 99, 10,
    lore="每个大侠的第一顶帽子。风雨里赶路时，它比什么护甲都实在。")
add("clothCap", "布巾", "seal", "low", ".wear(.hat)", "受击伤害 -1", 10, 18, defenseBonus=1,
    lore="山下杂货铺三文钱一条，胜在便宜。")
add("bambooHat", "竹叶帽", "leaf.fill", "low", ".wear(.hat)", "受击伤害 -1", 12, 22, defenseBonus=1,
    lore="竹叶编的帽子，据说能挡住词妖的窥视。")
add("学徒Cap", "学徒软帽", "graduationcap", "low", ".wear(.hat)", "受击伤害 -1", 11, 20, defenseBonus=1,
    lore="新入门弟子的标配，帽檐还留着背单词时蹭上的墨迹。")
add("linenHood", "麻布头巾", "person.crop.circle", "low", ".wear(.hat)", "每次胜利 +1 金币", 12, 16, coinBonus=1,
    lore="贩夫走卒的头巾，兜里总能多出几个铜板。")
add("gauzeCrown", "青纱冠", "crown", "mid", ".wear(.hat)", "受击伤害 -1，更耐用", 18, 45, defenseBonus=1,
    lore="青纱覆面，风流自在。据说戴上它背单词，记性会好三分。")
add("scholarCap", "书生巾", "book.closed.fill", "mid", ".wear(.hat)", "每次胜利额外 +1 金币", 20, 48, coinBonus=1,
    lore="十年寒窗的见证。书生说：单词嘛，读书百遍其义自见。")
add("ironCap", "铁盔", "shield.lefthalf.filled", "mid", ".wear(.hat)", "受击伤害 -1", 24, 50, defenseBonus=1,
    lore="军中制式，笨重但可靠。")
add("featherCap", "羽饰帽", "bird", "mid", ".wear(.hat)", "限时战斗 +4 秒", 18, 52, timeBonus=4,
    lore="插着一根不知名鸟羽，走路带风。")
add("mageHat", "星语法帽", "wand.and.stars", "high", ".wear(.hat)", "命中伤害 +1", 18, 85, restricted=M, damageBonus=1,
    lore="法师的尖顶帽。帽尖越尖，咒语越准——这是行会千年不变的迷信。")
add("ironHelm", "玄铁盔", "shield.fill", "high", ".wear(.hat)", "受击伤害 -1，坚固耐用", 30, 90, defenseBonus=1,
    lore="玄铁百炼，刀砍上去只留一道白痕。")
add("moonCoronet", "月华冠", "moon.stars.fill", "high", ".wear(.hat)", "限时战斗 +5 秒", 22, 95, timeBonus=5,
    lore="月光凝成的冠冕，戴上后时间仿佛走得慢些。")
add("knightHelm", "誓约头盔", "shield.checkered", "high", ".wear(.hat)", "受击 -2（词剑士专属）", 26, 100, restricted=K, defenseBonus=2,
    lore="剑士入门时立下的誓约刻在内衬：一寸不退。")
add("healerVeil", "杏林纱帽", "cross.case", "high", ".wear(.hat)", "每次胜利回血 1（词医者专属）", 22, 98, restricted=HE, regenPerWin=1,
    lore="医者的纱帽，行医时用来遮挡病气。")
add("thiefHood", "夜行斗篷帽", "moon.fill", "high", ".wear(.hat)", "限时 +6 秒（词行者专属）", 20, 92, restricted=R, timeBonus=6,
    lore="夜行者的兜帽。真正的高手，连风都听不见他的脚步。")
add("starCrown", "星辉冠", "sparkle", "rare", ".wear(.hat)", "受击伤害 -2", 24, 160, defenseBonus=2,
    lore="以陨星碎屑镶嵌，夜里会自己发光，找路很方便。")
add("thunderHelm", "雷纹战盔", "bolt.fill", "rare", ".wear(.hat)", "命中伤害 +1", 20, 170, damageBonus=1,
    lore="盔上雷纹会在战斗中噼啪作响，敌人往往先被吓一跳。")
add("gamblerTopHat", "老千高帽", "die.face.3.fill", "rare", ".wear(.hat)", "命中 +1，胜利 +2 金币（词赌徒专属）", 18, 175,
    restricted=GA, damageBonus=1, coinBonus=2, lore="帽子里能藏五张牌——当然，赌徒本人绝不承认。")
add("archmageHat", "大法师尖帽", "wand.and.rays", "rare", ".wear(.hat)", "命中 +1，限时 +5 秒（词法师专属）", 20, 180,
    restricted=M, damageBonus=1, timeBonus=5, lore="「你不该来这儿。」——某位灰袍法师最爱说的话。")
add("dragonHelm", "龙魂战盔", "flame.circle.fill", "legendary", ".wear(.hat)",
    "受击伤害 -2，每场战斗额外一次格挡", 22, 260, defenseBonus=2, extraShield="true",
    lore="盔中封着一缕龙魂。它在你濒死时会替你咬住那一击。")
add("phoenixCoronet", "凤羽金冠", "bird.circle.fill", "legendary", ".wear(.hat)",
    "受击 -1，命中 +1", 22, 275, defenseBonus=1, damageBonus=1,
    lore="凤凰落羽所制。凤凰不死，戴它的人也总能多撑一会儿。")
add("crownOfThorns", "荆棘之冠", "hexagon", "legendary", ".wear(.hat)", "命中 +2，受击 +0", 18, 290, damageBonus=2,
    lore="越痛越强的冠冕。刺扎进皮肉时，你反而看得更清了。")
add("goldenCrown", "金乌冕", "sun.max.fill", "goldLegend", ".wear(.hat)", "受击伤害 -3", 26, 420, defenseBonus=3,
    lore="传说金乌栖于扶桑，一日一飞。此冕以其冠羽为芯，烈日不能伤。")
add("voidCrown", "虚空道冠", "circle.hexagongrid.fill", "goldLegend", ".wear(.hat)",
    "受击 -2，限时 +8 秒", 26, 460, defenseBonus=2, timeBonus=8,
    lore="戴上它，你会短暂地忘记「时间」这个词的含义——这正是它的用处。")
# 补足帽子的低中阶（越稀有越少）
add("woodenCirclet", "木环冠", "circle", "low", ".wear(.hat)", "受击伤害 -1", 9, 14, defenseBonus=1,
    lore="削木成环，聊胜于无。")
add("beggarHat", "破草帽", "cone", "low", ".wear(.hat)", "每次胜利 +1 金币", 8, 12, coinBonus=1,
    lore="别嫌破。真正的高人往往一身破衣。")
add("silkBand", "锦缎发带", "line.horizontal.3", "low", ".wear(.hat)", "限时战斗 +3 秒", 10, 20, timeBonus=3,
    lore="束发用的锦带，跑起来利索。")
add("bronzeHelm", "青铜盔", "shield", "mid", ".wear(.hat)", "受击伤害 -1", 26, 46, defenseBonus=1,
    lore="上古军械，青绿的铜锈里还嵌着旧战场的沙。")
add("cloudCap", "流云帽", "cloud", "mid", ".wear(.hat)", "限时战斗 +5 秒", 19, 55, timeBonus=5,
    lore="轻得像没戴。走神时它会替你挡一下阳光。")
add("horaryCap", "更漏冠", "clock", "mid", ".wear(.hat)", "限时战斗 +6 秒", 17, 58, timeBonus=6,
    lore="冠内嵌着微型更漏，滴答声让人心安。")
add("wolfHeadgear", "狼首盔", "pawprint", "high", ".wear(.hat)", "命中伤害 +1", 20, 88, damageBonus=1,
    lore="以头狼颅骨为形。狼群的规矩：咬住了就别松口。")
add("jadeCrown", "白玉冠", "diamond", "high", ".wear(.hat)", "受击 -1，胜利 +2 金币", 22, 105, defenseBonus=1, coinBonus=2,
    lore="世家子弟的排场。玉能养人，也能买命。")

# ══════════ 穿戴 · 衣服（32）
add("clothRobe", "粗布道衣", "tshirt", "low", ".wear(.clothes)", "受击伤害 -1", 10, 20, defenseBonus=1,
    lore="道观发的常服，洗得发白。")
add("hempShirt", "麻布短打", "tshirt.fill", "low", ".wear(.clothes)", "受击伤害 -1", 12, 24, defenseBonus=1,
    lore="干活方便，打架也方便。")
add("patchedRobe", "百衲衣", "square.grid.3x3.fill", "low", ".wear(.clothes)", "受击 -1，胜利 +1 金币", 11, 22,
    defenseBonus=1, coinBonus=1, lore="一百块碎布缝的，据说每块都来自一位施主。")
add("noviceVest", "弟子背心", "tshirt", "low", ".wear(.clothes)", "受击伤害 -1", 10, 18, defenseBonus=1,
    lore="背上绣着「勤」字，师父亲手绣的。")
add("strawCape", "蓑衣", "cloud.rain.fill", "low", ".wear(.clothes)", "受击伤害 -1", 13, 26, defenseBonus=1,
    lore="孤舟蓑笠翁，独钓寒江雪。")
add("daoRobe", "青云道袍", "tshirt.fill", "mid", ".wear(.clothes)", "受击伤害 -1，更耐用", 24, 60, defenseBonus=1,
    lore="青云直上，说的是志气，不是衣服。")
add("leatherArmor", "皮甲", "shippingbox.fill", "mid", ".wear(.clothes)", "受击伤害 -1", 26, 58, defenseBonus=1,
    lore="牛皮硝制，实用主义者的选择。")
add("chainMail", "锁子甲", "square.grid.4x3.fill", "mid", ".wear(.clothes)", "受击 -1，耐久极高", 34, 68, defenseBonus=1,
    lore="一环扣一环，像背单词一样，少一环就散。")
add("silkGown", "云锦长衫", "wave.3.right", "mid", ".wear(.clothes)", "限时战斗 +5 秒", 20, 64, timeBonus=5,
    lore="穿它去赴宴，比穿它去打架合适。")
add("herbRobe", "药香褂", "leaf.circle", "mid", ".wear(.clothes)", "每次胜利回血 1", 20, 70, regenPerWin=1,
    lore="衣襟里常年塞着药材，闻着就精神。")
add("turtleArmor", "玄武甲", "tortoise.fill", "high", ".wear(.clothes)", "受击伤害 -2", 22, 110, defenseBonus=2,
    lore="玄武负地，千年不动。穿上它你就懂什么叫「稳」。")
add("frostRobe", "霜纹长袍", "snowflake", "high", ".wear(.clothes)", "受击 -1，命中 +1", 20, 120, defenseBonus=1, damageBonus=1,
    lore="袍上霜纹会在寒冬自行蔓延，据说是活的。")
add("healerRobe", "杏林白袍", "cross.case.fill", "high", ".wear(.clothes)",
    "受击 -1，每次胜利回血 1（词医者专属）", 20, 100, restricted=HE, defenseBonus=1, regenPerWin=1,
    lore="医者不自医，但这件袍子会替他疗伤。")
add("shadowCloak", "影行披风", "moon.fill", "mid", ".wear(.clothes)",
    "受击伤害 -1（词行者专属）", 18, 55, restricted=R, defenseBonus=1,
    lore="披上它，影子会先一步替你溜走。")
add("knightPlate", "誓约胸甲", "shield.righthalf.filled", "high", ".wear(.clothes)",
    "受击 -2（词剑士专属）", 28, 115, restricted=K, defenseBonus=2,
    lore="胸甲正中有一道旧凹痕——那是他没退的那一步留下的。")
add("gamblerSuit", "花牌礼服", "suit.club.fill", "high", ".wear(.clothes)",
    "命中 +1，胜利 +2 金币（词赌徒专属）", 18, 112, restricted=GA, damageBonus=1, coinBonus=2,
    lore="上牌桌要有排场。至于袖子里有什么，那是另一回事。")
add("featherRobe", "仙羽霓裳", "bird.fill", "rare", ".wear(.clothes)", "受击伤害 -2，轻若无物", 26, 170, defenseBonus=2,
    lore="千鸟落羽织成，穿上仿佛下一步就能踏空而行。")
add("starRobe", "星河法衣", "sparkles", "rare", ".wear(.clothes)", "受击 -1，限时 +6 秒", 24, 175, defenseBonus=1, timeBonus=6,
    lore="法衣内里绣着整片星图，夜里能当地图看。")
add("greenRobe", "青囊道服", "cross.vial.fill", "rare", ".wear(.clothes)",
    "每次胜利回血 2（词医者专属）", 22, 185, restricted=HE, regenPerWin=2,
    lore="传说华佗的青囊里装着这件衣服，可惜书被烧了。")
add("saintRobe", "不朽圣袍", "moon.stars.fill", "legendary", ".wear(.clothes)", "受击伤害 -3", 24, 280, defenseBonus=3,
    lore="它不会破。你破了它都还在。")
add("dragonRobe", "蟠龙锦袍", "scale.3d", "legendary", ".wear(.clothes)",
    "受击 -2，每次胜利 +2 金币", 26, 290, defenseBonus=2, coinBonus=2,
    lore="袍上蟠龙栩栩如生。据说穿它上朝，龙会替你说话。")
add("cicadaRobe", "金蝉圣衣", "seal.fill", "goldLegend", ".wear(.clothes)", "受击伤害 -4", 28, 450, defenseBonus=4,
    lore="金蝉脱壳，此衣即壳。刀枪不入，水火不侵——但每次脱下都要三天才能穿回去。")
add("chaosRobe", "混沌天衣", "circle.dotted", "goldLegend", ".wear(.clothes)",
    "受击 -3，额外一次格挡", 28, 500, defenseBonus=3, extraShield="true",
    lore="天衣无缝。你找不到它的接缝，敌人也找不到你的破绽。")
add("roughVest", "藤编护胸", "square.split.diagonal", "low", ".wear(.clothes)", "受击伤害 -1", 9, 15, defenseBonus=1,
    lore="山民用藤条编的，防野兽尚可。")
add("cottonRobe", "棉布长袍", "tshirt", "low", ".wear(.clothes)", "受击伤害 -1", 12, 21, defenseBonus=1,
    lore="暖和。背单词到半夜时全靠它。")
add("scaleVest", "鱼鳞衬甲", "fish.fill", "mid", ".wear(.clothes)", "受击 -1，限时 +3 秒", 24, 62, defenseBonus=1, timeBonus=3,
    lore="以深潭鱼鳞缝制，滑不留手。")
add("bronzeArmor", "青铜胸甲", "square.stack.3d.up.fill", "mid", ".wear(.clothes)", "受击伤害 -1", 30, 56, defenseBonus=1,
    lore="上古战场遗物，还留着钝痕。")
add("mageRobe", "秘纹法袍", "wand.and.stars.inverse", "high", ".wear(.clothes)",
    "命中 +1，限时 +4 秒（词法师专属）", 20, 108, restricted=M, damageBonus=1, timeBonus=4,
    lore="袍上秘纹是一整套咒语的速记，法师管它叫「小抄」。")
add("wolfPelt", "狼皮大衣", "pawprint.fill", "high", ".wear(.clothes)", "命中 +1，受击 -1", 22, 118, damageBonus=1, defenseBonus=1,
    lore="猎狼者穿狼皮，是尊重，也是宣战。")
add("nightSuit", "夜行紧衣", "moon.zzz.fill", "rare", ".wear(.clothes)",
    "限时 +8 秒（词行者专属）", 20, 165, restricted=R, timeBonus=8,
    lore="贴身裁制，连呼吸都被裹住了。")
add("phoenixRobe", "不死鸟羽衣", "flame.circle", "legendary", ".wear(.clothes)",
    "受击 -2，每次胜利回血 2", 24, 300, defenseBonus=2, regenPerWin=2,
    lore="浴火重生这四个字，穿上才有资格说。")

# ══════════ 穿戴 · 首饰（30）
add("woodBeads", "木珠链", "circle.grid.cross.fill", "low", ".wear(.jewelry)", "每次胜利额外 +1 金币", 12, 18, coinBonus=1,
    lore="山寺赠的念珠，据说数一遍能静心。")
add("copperRing", "铜戒", "circle.circle", "low", ".wear(.jewelry)", "命中伤害 +1", 8, 25, damageBonus=1,
    lore="铜戒握拳时能多几分力道，仅此而已。")
add("boneAmulet", "骨符", "seal", "low", ".wear(.jewelry)", "受击伤害 -1", 10, 20, defenseBonus=1,
    lore="兽骨刻符，巫祝之物。信则灵。")
add("luckyKnot", "同心结", "heart.fill", "low", ".wear(.jewelry)", "每次胜利回血 1", 10, 24, regenPerWin=1,
    lore="不知谁送的，红线都旧了，却一直没舍得扔。")
add("copperCoinString", "铜钱串", "circle.hexagongrid", "low", ".wear(.jewelry)", "每次胜利 +2 金币", 12, 28, coinBonus=2,
    lore="一串铜钱当项链戴。俗气，但真的招财。")
add("jadePendant", "凝神玉佩", "diamond.fill", "mid", ".wear(.jewelry)", "限时战斗时限 +10 秒", 8, 70, timeBonus=10,
    lore="握住它深吸一口气，慌乱的心就定了。")
add("koiRibbon", "锦鲤发带", "fish.fill", "mid", ".wear(.jewelry)", "传说能带来好运的收藏品", 99, 25,
    lore="锦鲤跃龙门的故事人人会讲，跃过去的却总是别人。")
add("silverBell", "银铃", "bell", "mid", ".wear(.jewelry)", "限时战斗 +6 秒", 14, 60, timeBonus=6,
    lore="铃响一声，神志清明一分。")
add("tigerTooth", "虎牙坠", "pawprint", "mid", ".wear(.jewelry)", "命中伤害 +1", 12, 66, damageBonus=1,
    lore="从猛虎口中拔下的牙。至于是怎么拔的，他不肯说。")
add("moneyBag", "聚财金袋", "bag.fill", "high", ".wear(.jewelry)", "每次胜利额外 +3 金币", 14, 120, coinBonus=3,
    lore="袋口永远收不紧——金币太多了。")
add("windBell", "清风铃", "bell.fill", "high", ".wear(.jewelry)", "限时战斗 +6 秒，胜利 +1 金币", 14, 115, timeBonus=6, coinBonus=1,
    lore="风一过就响。有人说那是提醒你：时间还够。")
add("knightOath", "誓约徽记", "shield.checkered", "high", ".wear(.jewelry)",
    "额外一次格挡（词剑士专属）", 10, 118, restricted=K, extraShield="true",
    lore="骑士的誓约刻在徽记背面，磨得快看不清了，他却记得每一个字。")
add("manaCrystal", "魔力水晶", "hexagon.fill", "high", ".wear(.jewelry)",
    "命中 +1，限时 +5 秒（词法师专属）", 12, 122, restricted=M, damageBonus=1, timeBonus=5,
    lore="法师的备用魔力池。快没词儿的时候，靠它顶一下。")
add("gamblerCharm", "赌魂符", "suit.spade.fill", "high", ".wear(.jewelry)",
    "命中伤害 +1（词赌徒专属）", 12, 95, restricted=GA, damageBonus=1,
    lore="「再来一把。」——赌魂符上唯一的铭文。")
add("physicianSeal", "杏林印", "cross.circle.fill", "high", ".wear(.jewelry)",
    "每次胜利回血 2（词医者专属）", 14, 120, restricted=HE, regenPerWin=2,
    lore="悬壶济世的凭证。盖过它的药方，从不收穷人的钱。")
add("calamityBead", "避劫珠", "circle.hexagonpath.fill", "rare", ".wear(.jewelry)", "每场战斗额外一次格挡", 8, 150, extraShield="true",
    lore="劫数临头时，珠子会碎——碎一次，换你一条命。")
add("dragonMask", "龙纹面具", "theatermasks.fill", "rare", ".wear(.jewelry)", "稀世收藏，尽显威严", 99, 60,
    lore="戴上它谁也认不出你。摘下来，你可能也认不出自己。")
add("spiritLocket", "聚灵坠", "capsule.fill", "rare", ".wear(.jewelry)", "每次胜利回血 1", 16, 155, regenPerWin=1,
    lore="坠中养着一缕灵息，它会一点点还给你。")
add("shadowRing", "隐踪戒", "circle.dashed", "rare", ".wear(.jewelry)",
    "限时 +8 秒（词行者专属）", 12, 168, restricted=R, timeBonus=8,
    lore="戴上它转三圈，据说能消失——当然，那是骗小孩的。")
add("cosmosMirror", "乾坤镜", "circle.circle.fill", "legendary", ".wear(.jewelry)",
    "命中伤害 +1，受击伤害 -1", 16, 300, damageBonus=1, defenseBonus=1,
    lore="镜中乾坤，能照见词的本相。照久了会看见自己背错的每一个词。")
add("nineDragonPearl", "九龙珠", "circle.grid.3x3.fill", "legendary", ".wear(.jewelry)",
    "命中 +2", 14, 310, damageBonus=2,
    lore="九龙争珠，珠归持之者。至于九条龙去哪儿了，故事没说。")
add("oneRing", "至尊金环", "circle.fill", "legendary", ".wear(.jewelry)",
    "命中 +1，限时 +8 秒", 12, 330, damageBonus=1, timeBonus=8,
    lore="内圈刻着一行没人认得的字。戴久了总觉得有谁在叫你的名字。")
add("primalSeal", "鸿蒙道印", "hexagon.fill", "goldLegend", ".wear(.jewelry)",
    "命中伤害 +2，受击伤害 -2", 20, 500, damageBonus=2, defenseBonus=2,
    lore="鸿蒙初辟时的第一枚印。所有的词都从这里开始。")
add("fateDice", "命运骰坠", "die.face.4.fill", "goldLegend", ".wear(.jewelry)",
    "命中 +2，每次胜利 +3 金币", 18, 520, damageBonus=2, coinBonus=3,
    lore="它只有一面朝上：你想要的那面。")
add("ironBangle", "铁镯", "circle", "low", ".wear(.jewelry)", "受击伤害 -1", 11, 17, defenseBonus=1,
    lore="打铁匠的赠礼，沉得能练手劲。")
add("shellNecklace", "贝壳串", "shell.fill", "low", ".wear(.jewelry)", "限时战斗 +3 秒", 10, 15, timeBonus=3,
    lore="海边捡的。凑近能听见潮声。")
add("cloudPin", "云纹簪", "cloud.fill", "mid", ".wear(.jewelry)", "受击 -1，限时 +4 秒", 13, 64, defenseBonus=1, timeBonus=4,
    lore="簪头一朵云，云里藏着一点风。")
add("goldLeaf", "金叶佩", "leaf.fill", "mid", ".wear(.jewelry)", "每次胜利 +2 金币", 14, 72, coinBonus=2,
    lore="真金打的叶子，脉络分明。有钱人的浪漫。")
add("phoenixFeather", "凤羽坠", "flame.fill", "rare", ".wear(.jewelry)", "每次胜利回血 2", 14, 178, regenPerWin=2,
    lore="凤凰的一根尾羽。灼手，但暖。")

# ══════════ 穿戴 · 裤子（26）
add("linenPants", "麻布裤", "rectangle.split.2x1", "low", ".wear(.pants)", "受击伤害 -1", 10, 15, defenseBonus=1,
    lore="耐磨、透气、便宜，穷修士的三大美德。")
add("hideLeggings", "兽皮护腿", "pawprint", "low", ".wear(.pants)", "受击伤害 -1", 12, 20, defenseBonus=1,
    lore="猎人的护腿，膝盖处磨得最亮。")
add("cottonPants", "粗棉裤", "rectangle.split.2x1.fill", "low", ".wear(.pants)", "受击伤害 -1", 11, 18, defenseBonus=1,
    lore="娘亲缝的，针脚有点歪。")
add("wovenPants", "藤纹裤", "square.split.diagonal", "low", ".wear(.pants)", "限时战斗 +3 秒", 10, 19, timeBonus=3,
    lore="山民手艺，走山路快得很。")
add("cloudPants", "云纹裤", "cloud.fill", "mid", ".wear(.pants)", "受击伤害 -1，更耐用", 22, 50, defenseBonus=1,
    lore="腿上一朵云，走起来轻快。")
add("silkPants", "丝绸裤", "wave.3.right", "mid", ".wear(.pants)", "限时战斗 +4 秒", 20, 52, timeBonus=4,
    lore="料子太好，打架时总怕蹭破。")
add("leatherPants", "皮护裤", "shippingbox", "mid", ".wear(.pants)", "受击 -1，耐久高", 30, 54, defenseBonus=1,
    lore="佣兵最爱。血迹擦擦就没了。")
add("bronzeGreaves", "青铜胫甲", "square.stack.3d.down.right.fill", "mid", ".wear(.pants)", "受击伤害 -1", 28, 56, defenseBonus=1,
    lore="护住小腿，冲阵时最要紧的地方。")
add("galePants", "罡风战裤", "tornado", "high", ".wear(.pants)", "受击伤害 -2", 20, 100, defenseBonus=2,
    lore="裤脚常年鼓风，像有人在旁边推你一把。")
add("stonePants", "磐石胫甲", "cube.fill", "high", ".wear(.pants)", "受击 -1，耐久极高", 34, 95, defenseBonus=1,
    lore="重得离谱，但站定了谁也推不动。")
add("knightGreaves", "誓约胫甲", "shield.lefthalf.filled", "high", ".wear(.pants)",
    "受击 -2（词剑士专属）", 30, 108, restricted=K, defenseBonus=2,
    lore="剑士的膝甲从不擦亮——他从不下跪。")
add("swiftTrousers", "轻捷行裤", "hare", "high", ".wear(.pants)",
    "限时 +6 秒（词行者专属）", 20, 102, restricted=R, timeBonus=6,
    lore="缝了七个暗袋，装满了不该问的东西。")
add("flameLeggings", "焚天护腿", "flame", "rare", ".wear(.pants)", "命中 +1，受击 -1", 20, 150, damageBonus=1, defenseBonus=1,
    lore="行走时留下焦痕。别穿它进草原。")
add("tidePants", "潮汐裤", "water.waves", "rare", ".wear(.pants)", "受击 -2", 22, 145, defenseBonus=2,
    lore="布面起伏如潮，攻击落上去总会滑开。")
add("dragonscale", "龙鳞裤", "scale.3d", "legendary", ".wear(.pants)", "受击伤害 -2，坚不可摧", 26, 240, defenseBonus=2,
    lore="每一片鳞都来自不同的龙。它们不是自愿的。")
add("starPants", "星辰战裤", "star.fill", "legendary", ".wear(.pants)", "受击 -2，胜利 +2 金币", 24, 250, defenseBonus=2, coinBonus=2,
    lore="裤上星点会随夜空变化，同一条裤子从没穿出两次相同的样子。")
add("kylinPants", "麒麟金胫", "hare.fill", "goldLegend", ".wear(.pants)", "受击伤害 -3", 26, 430, defenseBonus=3,
    lore="麒麟不履生草。穿上它，你的每一步都会格外小心。")
add("chaosPants", "太初法裤", "circle.hexagongrid.circle", "goldLegend", ".wear(.pants)",
    "受击 -2，命中 +1", 26, 450, defenseBonus=2, damageBonus=1,
    lore="太初有言，言化万物。这条裤子听得懂词。")
add("beggarPants", "破布裤", "rectangle.dashed", "low", ".wear(.pants)", "每次胜利 +1 金币", 8, 10, coinBonus=1,
    lore="补丁摞补丁。别小看它，跑得比谁都快。")
add("furLeggings", "毛皮暖裤", "snowflake", "low", ".wear(.pants)", "受击伤害 -1", 13, 23, defenseBonus=1,
    lore="北境行商的必备，冻不着腿就冻不着心。")
add("scalePants", "鱼鳞胫裤", "fish", "mid", ".wear(.pants)", "受击 -1，限时 +3 秒", 24, 58, defenseBonus=1, timeBonus=3,
    lore="下水也不沉，据说渔家子弟人人一条。")
add("moonPants", "月纹裤", "moon", "mid", ".wear(.pants)", "限时战斗 +5 秒", 20, 60, timeBonus=5,
    lore="月色织成的纹路，夜里走路不用点灯。")
add("mageSkirt", "星纹法裾", "wand.and.stars", "high", ".wear(.pants)",
    "命中 +1（词法师专属）", 18, 105, restricted=M, damageBonus=1,
    lore="法袍下摆的延伸，走起来像在翻书。")
add("gamblerPants", "花纹长裤", "suit.diamond.fill", "high", ".wear(.pants)",
    "胜利 +3 金币（词赌徒专属）", 18, 110, restricted=GA, coinBonus=3,
    lore="口袋深不见底。赢的时候是好事，输的时候……也一样。")
add("thunderGreaves", "雷纹胫甲", "bolt.horizontal", "rare", ".wear(.pants)", "命中 +1，限时 +4 秒", 20, 155,
    damageBonus=1, timeBonus=4, lore="迈步带电，敌人常被自己的头发吓退。")
add("voidPants", "虚空裤", "circle.dashed.inset.filled", "legendary", ".wear(.pants)",
    "受击 -3", 24, 260, defenseBonus=3, lore="据说它其实不存在。摸得到，是你的错觉。")

# ══════════ 穿戴 · 鞋子（26）
add("strawShoes", "草鞋", "shoeprints.fill", "low", ".wear(.shoes)", "行走江湖的收藏品", 99, 8,
    lore="千里之行，始于草鞋。磨破七双，就到得了山顶。")
add("clothBoots", "布靴", "shoeprints.fill", "low", ".wear(.shoes)", "受击伤害 -1", 10, 16, defenseBonus=1,
    lore="轻便，但下雨天会灌水。")
add("hideBoots", "兽皮靴", "pawprint.circle", "low", ".wear(.shoes)", "受击伤害 -1", 12, 19, defenseBonus=1,
    lore="山里人手工缝的，防滑。")
add("woodenClogs", "木屐", "square.split.bottomrightquarter", "low", ".wear(.shoes)", "每次胜利 +1 金币", 9, 12, coinBonus=1,
    lore="踏踏作响。想偷袭的话，换一双。")
add("cloudBoots", "踏云靴", "wind", "mid", ".wear(.shoes)", "受击伤害 -1", 20, 55, defenseBonus=1,
    lore="传说能踏云而行，实际只是走路轻一点。")
add("ironBoots", "铁履", "hammer.fill", "mid", ".wear(.shoes)", "受击 -1，耐久高", 30, 60, defenseBonus=1,
    lore="踢一脚能踢断树。代价是走十里就累。")
add("hunterBoots", "猎行靴", "scope", "mid", ".wear(.shoes)", "限时战斗 +5 秒", 20, 58, timeBonus=5,
    lore="鞋底纹路是猎人自己刻的，为了不被猎物听见。")
add("windBoots", "疾风履", "wind.snow", "high", ".wear(.shoes)", "限时战斗 +6 秒", 18, 100, timeBonus=6,
    lore="穿上它跑起来，风会替你让路。")
add("earthBoots", "厚土战靴", "square.3.layers.3d", "high", ".wear(.shoes)", "受击 -2", 20, 105, defenseBonus=2,
    lore="脚踏实地，是最朴素的天赋。")
add("thiefBoots", "无声靴", "moon.zzz", "high", ".wear(.shoes)",
    "限时 +7 秒（词行者专属）", 18, 108, restricted=R, timeBonus=7,
    lore="鞋底垫了七层棉。走过雪地不留声，只留印。")
add("healerSandals", "行医草履", "cross.case", "high", ".wear(.shoes)",
    "每次胜利回血 1（词医者专属）", 20, 100, restricted=HE, regenPerWin=1,
    lore="走遍十六州的鞋。每一道磨痕后面都有一条被救的命。")
add("swiftBoots", "疾影靴", "hare.fill", "rare", ".wear(.shoes)", "受击伤害 -1，每次胜利 +1 金币", 18, 140,
    defenseBonus=1, coinBonus=1, lore="影子追不上主人，就是这双靴子的传说。")
add("lotusBoots", "青莲步履", "leaf.circle.fill", "rare", ".wear(.shoes)", "每次胜利回血 1", 18, 150, regenPerWin=1,
    lore="步步生莲。落脚处的青苔都活了过来。")
add("thunderBoots", "雷步战靴", "bolt.horizontal.circle.fill", "legendary", ".wear(.shoes)",
    "命中 +1，限时 +5 秒", 20, 260, damageBonus=1, timeBonus=5,
    lore="每一步都像一记闷雷。敌人还没看清，你已经到跟前了。")
add("voidBoots", "虚空踏", "circle.dashed", "legendary", ".wear(.shoes)", "受击 -2，胜利 +2 金币", 20, 270,
    defenseBonus=2, coinBonus=2, lore="它踩着的不是地面，是「两个词之间的空白」。")
add("sunChaser", "逐日金履", "sunrise.fill", "goldLegend", ".wear(.shoes)",
    "受击伤害 -2，限时战斗 +5 秒", 22, 380, defenseBonus=2, timeBonus=5,
    lore="夸父逐日未成，鞋留了下来。谁穿上，都得替他跑完那一段。")
add("skyWalker", "凌霄天履", "airplane", "goldLegend", ".wear(.shoes)",
    "受击 -2，命中 +1，限时 +5 秒", 24, 480, defenseBonus=2, damageBonus=1, timeBonus=5,
    lore="登天的最后一段路，没有台阶。所以要有这双鞋。")
add("bambooShoes", "竹编鞋", "leaf", "low", ".wear(.shoes)", "限时战斗 +3 秒", 10, 14, timeBonus=3,
    lore="夏天穿最舒服，冬天……换一双吧。")
add("ropeSandals", "麻绳凉履", "line.3.horizontal", "low", ".wear(.shoes)", "受击伤害 -1", 9, 11, defenseBonus=1,
    lore="麻绳绕脚，简陋但结实。")
add("silverBoots", "银纹靴", "sparkle", "mid", ".wear(.shoes)", "受击 -1，胜利 +1 金币", 22, 66, defenseBonus=1, coinBonus=1,
    lore="靴面银纹在月下会亮，很适合走夜路（也很适合被发现）。")
add("stoneBoots", "山岩靴", "cube", "mid", ".wear(.shoes)", "受击伤害 -1", 32, 62, defenseBonus=1,
    lore="山民所制，走碎石路如履平地。")
add("mageSlippers", "星语软靴", "wand.and.rays.inverse", "high", ".wear(.shoes)",
    "限时 +6 秒（词法师专属）", 18, 104, restricted=M, timeBonus=6,
    lore="法师不爱走路，所以把靴子做得很轻。")
add("knightSabatons", "誓约铁靴", "shield.fill", "high", ".wear(.shoes)",
    "受击 -2（词剑士专属）", 28, 112, restricted=K, defenseBonus=2,
    lore="铁靴踏地的声音就是他的战鼓。")
add("gamblerLoafers", "红运皮鞋", "suit.heart.fill", "rare", ".wear(.shoes)",
    "胜利 +3 金币（词赌徒专属）", 16, 160, restricted=GA, coinBonus=3,
    lore="每次赢钱他都擦一遍鞋。鞋擦得越亮，赌得越大。")
add("phoenixBoots", "焚羽战靴", "flame.circle.fill", "legendary", ".wear(.shoes)",
    "命中 +1，每次胜利回血 1", 20, 275, damageBonus=1, regenPerWin=1,
    lore="踏火不焚。据说不死鸟落地时就穿着它。")

# ══════════ 武器（40，不分类展示）
add("woodSword", "青竹剑", "chevron.forward.2", "low", ".weapon", "命中伤害 +1", 8, 20, damageBonus=1,
    lore="削竹为剑，是所有剑客的开始。别笑，它砍过妖。")
add("rustyBlade", "锈铁刀", "line.diagonal", "low", ".weapon", "命中伤害 +1", 9, 22, damageBonus=1,
    lore="锈是锈，锋还在。")
add("shortBow", "猎人短弓", "scope", "low", ".weapon", "命中伤害 +1", 10, 26, damageBonus=1,
    lore="打兔子用的。打词妖也行，只是要多打几箭。")
add("apprenticeWand", "学徒木杖", "wand.and.rays.inverse", "low", ".weapon", "命中伤害 +1", 10, 28, damageBonus=1,
    lore="第一根法杖。挥起来像在指挥一群不听话的字母。")
add("woodStaff", "枣木棍", "line.horizontal.3.decrease", "low", ".weapon", "命中伤害 +1", 12, 18, damageBonus=1,
    lore="路边捡的棍子。趁手得出乎意料。")
add("stoneAxe", "石斧", "hammer", "low", ".weapon", "命中伤害 +1", 10, 21, damageBonus=1,
    lore="最古老的武器。简单、直接、有效。")
add("throwKnife", "飞刀", "paperplane.fill", "low", ".weapon", "命中 +1，限时 +3 秒", 8, 25,
    damageBonus=1, timeBonus=3, lore="小李飞刀，例无虚发——那是别人。你的还得练。")
add("ironBlade", "玄铁重刀", "bolt.horizontal.fill", "mid", ".weapon", "命中伤害 +1，更耐用", 20, 60, damageBonus=1,
    lore="重刀无锋，大巧不工。")
add("steelSpear", "精钢长枪", "arrow.up.right", "mid", ".weapon", "命中伤害 +1", 18, 65, damageBonus=1,
    lore="一寸长一寸强。枪法讲的是距离，不是力气。")
add("windDagger", "风刃匕", "leaf.arrow.circlepath", "mid", ".weapon", "命中 +1，限时 +4 秒", 15, 72,
    damageBonus=1, timeBonus=4, lore="快，是唯一的道理。")
add("goldDice", "鎏金骰子", "die.face.6.fill", "mid", ".weapon", "命中伤害 +1（词赌徒专属）", 15, 70,
    restricted=GA, damageBonus=1, lore="他把骰子当武器扔出去。据说从没扔出过一点。")
add("healerScalpel", "青囊刀", "cross.vial", "mid", ".weapon",
    "命中 +1，每次胜利回血 1（词医者专属）", 16, 78, restricted=HE, damageBonus=1, regenPerWin=1,
    lore="能救人也能杀人。医者的刀，比谁都清楚这两者的距离。")
add("bronzeSword", "青铜古剑", "chevron.up", "mid", ".weapon", "命中伤害 +1", 24, 62, damageBonus=1,
    lore="从古墓里带出来的。剑身上的铭文没人认得。")
add("crossbow", "手弩", "arrow.right.to.line", "mid", ".weapon", "命中 +1，限时 +3 秒", 16, 68,
    damageBonus=1, timeBonus=3, lore="不需要臂力，只需要冷静。")
add("frostBow", "寒霜长弓", "scope", "high", ".weapon", "命中伤害 +1，每次胜利 +1 金币", 18, 110,
    damageBonus=1, coinBonus=1, lore="弦一拉，方圆三尺结霜。射出去的箭自带回音。")
add("magicWand", "星芒法杖", "wand.and.rays", "high", ".weapon", "命中伤害 +2", 14, 130, damageBonus=2,
    lore="杖头星芒会随咒语明暗。背错单词时它会黯下去，很伤自尊。")
add("moonBlade", "月牙弯刀", "moon.fill", "high", ".weapon", "命中伤害 +2", 15, 128, damageBonus=2,
    lore="刀如新月。挥出去的弧线，据说能割断月光。")
add("thunderHammer", "雷霆战锤", "hammer.fill", "high", ".weapon", "命中 +2，笨重", 12, 120, damageBonus=2,
    lore="举起来很慢，落下去很快。这就够了。")
add("knightLongsword", "誓约长剑", "shield.righthalf.filled", "high", ".weapon",
    "命中 +2（词剑士专属）", 20, 135, restricted=K, damageBonus=2,
    lore="剑柄缠布已被血浸透多次。剑士说：它记得每一个我救下的人。")
add("mageOrb", "秘文法球", "circle.hexagongrid.circle.fill", "high", ".weapon",
    "命中 +2（词法师专属）", 14, 138, restricted=M, damageBonus=2,
    lore="球里封着一整本词典。摇一摇，会听见沙沙的翻页声。")
add("thiefFangs", "双影匕", "arrow.left.arrow.right", "high", ".weapon",
    "命中 +2（词行者专属）", 14, 132, restricted=R, damageBonus=2,
    lore="一把在明，一把在暗。敌人永远盯错那一把。")
add("greenDragonBlade", "青龙偃月刀", "line.diagonal.arrow", "high", ".weapon",
    "命中 +2，受击 -1", 18, 145, damageBonus=2, defenseBonus=1,
    lore="八十二斤。据说某位红脸将军用它温过酒，也斩过将。")
add("immortalSword", "赤霄仙剑", "burst.fill", "rare", ".weapon", "命中伤害 +2，剑气纵横", 20, 180, damageBonus=2,
    lore="赤霄一出，斩白蛇于泽中。剑还在，蛇的传说也还在。")
add("dragonBow", "游龙弓", "arrow.up.forward", "rare", ".weapon", "命中 +2，胜利 +1 金币", 18, 190,
    damageBonus=2, coinBonus=1, lore="弓身如龙脊。拉满时会有龙吟——也可能只是风声。")
add("soulStaff", "摄魂法杖", "sparkle.magnifyingglass", "rare", ".weapon", "命中 +2，限时 +5 秒", 16, 195,
    damageBonus=2, timeBonus=5, lore="它能摄走词妖的魂。副作用是你会梦见那些词。")
add("gamblerRevolver", "六面轮盘", "die.face.6", "rare", ".weapon",
    "命中 +2，胜利 +2 金币（词赌徒专属）", 16, 200, restricted=GA, damageBonus=2, coinBonus=2,
    lore="六个格子，五个是空的。赌徒偏爱第六格。")
add("mercyBlade", "慈悲刃", "cross.case.fill", "rare", ".weapon",
    "命中 +1，每次胜利回血 2（词医者专属）", 18, 198, restricted=HE, damageBonus=1, regenPerWin=2,
    lore="刀名慈悲，因为它总是先救人，后杀敌。")
add("fangOfWolf", "狼牙棒", "pawprint.fill", "rare", ".weapon", "命中 +3，受击 +0", 16, 185, damageBonus=3,
    lore="满身尖刺，毫无技巧，全是力量。")
add("phoenixSpear", "凤翎枪", "flame.fill", "legendary", ".weapon", "命中伤害 +3", 18, 320, damageBonus=3,
    lore="枪尖一点火，能烧尽一整页错词。")
add("frostFang", "玄冰牙", "snowflake.circle.fill", "legendary", ".weapon", "命中 +3，受击 -1", 18, 340,
    damageBonus=3, defenseBonus=1, lore="拔出时寒气逼人，连词妖的呼吸都会凝住。")
add("starBow", "落星神弓", "star.circle.fill", "legendary", ".weapon", "命中 +3，胜利 +2 金币", 16, 350,
    damageBonus=3, coinBonus=2, lore="它射下来的不是箭，是星。所以每次只能射一发。")
add("shadowEdge", "无影剑", "circle.dashed.inset.filled", "legendary", ".weapon",
    "命中 +3（词行者专属）", 16, 345, restricted=R, damageBonus=3,
    lore="剑无影，出鞘时天下人只看见结果。")
add("staffOfWisdom", "智慧长杖", "book.circle.fill", "legendary", ".weapon",
    "命中 +2，限时 +8 秒（词法师专属）", 18, 355, restricted=M, damageBonus=2, timeBonus=8,
    lore="「我们不是要跑得更快，是要想得更清楚。」——杖上唯一的刻字。")
add("xuanyuanSword", "轩辕圣剑", "bolt.shield.fill", "goldLegend", ".weapon",
    "命中伤害 +3，每场战斗额外一次格挡", 22, 520, damageBonus=3, extraShield="true",
    lore="黄帝铸之，蚩尤畏之。剑在，则言正；言正，则词不惑。")
add("chaosStaff", "混元道杖", "sparkles.rectangle.stack", "goldLegend", ".weapon",
    "命中 +4", 20, 600, damageBonus=4,
    lore="一杖开天。它不背单词，它定义单词。")
add("dragonSlayer", "屠龙巨剑", "flame.circle", "goldLegend", ".weapon",
    "命中 +4，受击 -1", 20, 640, damageBonus=4, defenseBonus=1,
    lore="剑很大，很重，很钝。但它真的杀过龙。")
add("excalibur", "湖中圣剑", "drop.circle.fill", "goldLegend", ".weapon",
    "命中 +3，受击 -2", 22, 660, damageBonus=3, defenseBonus=2,
    lore="石中之剑，唯真王可拔。你拔出来了——所以别辜负它。")
add("monkeyStaff", "如意金箍棒", "arrow.up.and.down.circle.fill", "goldLegend", ".weapon",
    "命中 +4，限时 +5 秒", 22, 700, damageBonus=4, timeBonus=5,
    lore="一万三千五百斤，可大可小。「俺去也」——它的前任主人如是说。")

# ══════════ 药水（22）
add("smallHerb", "止血草", "leaf.fill", "low", ".potion", "服用回复 6 点生命", 1, 9, healAmount=6,
    lore="随手能采的野草，嚼碎按在伤口上。土法子，但管用。")
add("energyTea", "凝神茶", "cup.and.saucer.fill", "low", ".potion", "服用回复 8 点生命", 1, 12, healAmount=8,
    lore="背单词背到犯困时来一杯。")
add("healPill", "疗伤丹", "pill.fill", "low", ".potion", "服用回复 10 点生命", 1, 15, healAmount=10,
    lore="最常见的丹药，药铺整坛卖。")
add("riceWine", "米酒", "wineglass.fill", "low", ".potion", "服用回复 8 点生命", 1, 11, healAmount=8,
    lore="酒能壮胆。壮完胆，单词还是不认识。")
add("honeyWater", "蜜水", "drop.circle", "low", ".potion", "服用回复 7 点生命", 1, 10, healAmount=7,
    lore="甜的。喝一口就觉得世界温柔了些。")
add("smallSand", "碎时沙", "hourglass.bottomhalf.filled", "low", ".potion", "限时战斗 +8 秒", 1, 14, timeBonus=8,
    lore="沙漏里漏下的一点点时间。省着用。")
add("bigPill", "大还丹", "pills.fill", "mid", ".potion", "服用回复 20 点生命", 1, 35, healAmount=20,
    lore="宗门发的救命丹，一年只发两颗。")
add("timeSand", "时之沙", "hourglass", "mid", ".potion", "限时战斗中使用 +15 秒", 1, 30, timeBonus=15,
    lore="握紧它，秒针会犹豫一下。")
add("jadeDew", "玉髓露", "drop.fill", "mid", ".potion", "服用回复 25 点生命", 1, 42, healAmount=25,
    lore="玉中凝出的一滴髓液。据说能补回熬夜背书的元气。")
add("herbSoup", "十全大补汤", "takeoutbag.and.cup.and.straw.fill", "mid", ".potion", "服用回复 22 点生命", 1, 38, healAmount=22,
    lore="药材放了十种，味道很难形容。喝完确实精神。")
add("clarityPill", "醒神丸", "brain.head.profile", "mid", ".potion", "限时战斗 +18 秒", 1, 40, timeBonus=18,
    lore="一入口，脑子里的雾就散了。")
add("superPill", "醍醐灌顶露", "drop.degreesign.fill", "high", ".potion", "服用回复 35 点生命", 1, 70, healAmount=35,
    lore="醍醐灌顶。喝完那一瞬间，你会觉得所有词都认识了（只是错觉）。")
add("chronoSand", "岁月金沙", "hourglass.tophalf.filled", "high", ".potion", "限时战斗 +25 秒", 1, 65, timeBonus=25,
    lore="金沙一粒，值一刻钟。奢侈，但有时候就得奢侈。")
add("spiritBrew", "灵酿", "wineglass", "high", ".potion", "服用回复 30 点生命", 1, 62, healAmount=30,
    lore="仙人自酿。凡人喝了会睡三天，醒来伤全好了。")
add("dragonBlood", "龙血丹", "flame.circle.fill", "rare", ".potion", "服用回复 45 点生命", 1, 100, healAmount=45,
    lore="以真龙之血炼制。喝下去喉咙会烧，然后骨头会响。")
add("phoenixTear", "凤凰泪", "drop.triangle.fill", "rare", ".potion", "服用回复 50 点生命", 1, 110, healAmount=50,
    lore="凤凰垂泪，能疗百伤。它哭一次，你活一次。")
add("nirvanaSand", "涅槃沙", "hourglass.circle.fill", "rare", ".potion", "限时战斗 +32 秒", 1, 105, timeBonus=32,
    lore="沙落尽时是终点。所以它总在最后一刻停下。")
add("fullElixir", "九转还魂液", "sparkles", "legendary", ".potion", "服用回满生命", 1, 150, healAmount=99,
    lore="九转九炼，一滴还魂。药王说：这药救不了不肯自救的人。")
add("eternitySand", "永恒沙漏", "hourglass.bottomhalf.filled", "legendary", ".potion", "限时战斗 +40 秒", 1, 140, timeBonus=40,
    lore="把它倒过来，时间也跟着倒过来——一小会儿。")
add("immortalPeach", "蟠桃仙露", "circle.fill", "goldLegend", ".potion", "服用回满生命，仙气盈然", 1, 220, healAmount=99,
    lore="三千年一开花，三千年一结果。你手里这瓶，是某只猴子漏下的。")
add("ninefoldPill", "太上金丹", "circle.circle.fill", "goldLegend", ".potion", "服用回满生命", 1, 240, healAmount=99,
    lore="炉中丹成，天雷都要退三分。吃之前记得先看看有没有猴毛。")
add("timelessHour", "无尽时轮", "clock.arrow.2.circlepath", "goldLegend", ".potion", "限时战斗 +60 秒", 1, 260, timeBonus=60,
    lore="轮转不休，时间在它面前只是个提议。")

# ══════════ 宠物（22）
add("bookWorm", "书虫", "ant.fill", "low", ".pet", "每次胜利额外 +1 金币", 99, 35, coinBonus=1,
    lore="真的会吃书。好在它只吃你背错的那几页。")
add("inkCat", "墨玉猫", "cat.fill", "low", ".pet", "每次胜利回血 1", 99, 45, regenPerWin=1,
    lore="踩着墨迹在书页上走来走去，还理直气壮。")
add("clayDog", "泥塑犬", "pawprint", "low", ".pet", "每次胜利 +1 金币", 99, 30, coinBonus=1,
    lore="庙会上买的泥狗。某天早上，它自己换了个姿势。")
add("firefly", "流萤", "light.max", "low", ".pet", "限时战斗 +3 秒", 99, 32, timeBonus=3,
    lore="夜里替你照亮书页的小东西。")
add("sparrow", "灰雀", "bird", "low", ".pet", "受击伤害 -1", 99, 38, defenseBonus=1,
    lore="停在肩上叽叽喳喳，据说能预警危险。")
add("wordPup", "词灵犬", "pawprint.fill", "mid", ".pet", "每次胜利额外 +1 金币", 99, 80, coinBonus=1,
    lore="能闻出哪个词你记不牢，然后叼过来放你手上。")
add("cloudCrane", "云中鹤", "bird.fill", "mid", ".pet", "限时战斗 +5 秒", 99, 90, timeBonus=5,
    lore="鹤唳一声，人心里的急躁就散了。")
add("greenSnake", "青蛇", "lizard", "mid", ".pet", "命中伤害 +1", 99, 85, damageBonus=1,
    lore="盘在剑鞘上打盹。你出剑时它比你更兴奋。")
add("stoneLion", "小石狮", "cube.fill", "mid", ".pet", "受击伤害 -1", 99, 88, defenseBonus=1,
    lore="门口石狮的崽。走路砰砰响，但真挡得住。")
add("fireFox", "赤焰狐", "flame.fill", "high", ".pet", "命中伤害 +1", 99, 140, damageBonus=1,
    lore="尾巴一扫，词妖就着火了。它自己却不怕烫。")
add("stoneTurtle", "玄石龟", "tortoise.fill", "high", ".pet", "受击伤害 -1", 99, 150, defenseBonus=1,
    lore="慢，但从来没被打伤过。它说这叫策略。")
add("healingDeer", "灵鹿", "hare", "high", ".pet", "每次胜利回血 1", 99, 145, regenPerWin=1,
    lore="鹿角上长着草药。它会自己叼来给你。")
add("moneyToad", "金蟾", "circle.hexagongrid.circle", "high", ".pet", "每次胜利 +2 金币", 99, 148, coinBonus=2,
    lore="口含金钱的三足蟾。招财，但很吵。")
add("inkKirin", "墨麒麟", "hare.fill", "rare", ".pet", "受击伤害 -1，灵性十足", 99, 190, defenseBonus=1,
    lore="麒麟本不该现世。它说：因为你在认真背书，所以我来看看。")
add("thunderBird", "雷羽鹰", "bolt.fill", "rare", ".pet", "命中 +1，限时 +4 秒", 99, 200,
    damageBonus=1, timeBonus=4, lore="振翅带雷。它俯冲时，你只需要跟着念出那个词。")
add("whiteTiger", "白虎幼崽", "pawprint.circle.fill", "rare", ".pet", "命中 +1，受击 -1", 99, 210,
    damageBonus=1, defenseBonus=1, lore="西方白虎，主兵戈。现在它咬着你的裤脚要吃的。")
add("pixiu", "吞词貔貅", "dollarsign.circle.fill", "legendary", ".pet", "每次胜利额外 +4 金币", 99, 340, coinBonus=4,
    lore="貔貅无肛，只进不出。它吞下的每个词都会变成金币。")
add("nineTailFox", "九尾灵狐", "sparkle", "legendary", ".pet", "命中 +1，受击 -1", 99, 360,
    damageBonus=1, defenseBonus=1, lore="九条尾巴，每条记一千个词。它常笑你记性差。")
add("qilin", "麒麟", "hare.circle.fill", "legendary", ".pet", "受击 -2", 99, 370, defenseBonus=2,
    lore="麒麟出，圣人生。它跟着你，大概是看错人了——也许没看错。")
add("goldenCrow", "金乌雏", "bird.circle.fill", "goldLegend", ".pet",
    "命中伤害 +1，限时战斗 +5 秒", 99, 560, damageBonus=1, timeBonus=5,
    lore="十日并出时被射落的那只金乌，如今只剩一只雏鸟，落在你肩上。")
add("dragonWhelp", "幼龙", "lizard.fill", "goldLegend", ".pet",
    "命中 +2，受击 -1", 99, 620, damageBonus=2, defenseBonus=1,
    lore="它还不会飞，但已经会喷火了。请注意书本。")
add("phoenixChick", "凤雏", "flame.circle.fill", "goldLegend", ".pet",
    "命中 +1，每次胜利回血 2", 99, 600, damageBonus=1, regenPerWin=2,
    lore="凤凰的孩子。它每次重生都会长大一点，你每次背词也是。")

# ══════════ 精灵（22）
add("dewFae", "露珠精灵", "drop.circle.fill", "low", ".sprite", "每次胜利 +1 金币", 99, 38, coinBonus=1,
    lore="清晨叶尖上的一滴露。它以为自己是海。")
add("fireflyFae", "萤穗精灵", "light.max", "low", ".sprite", "每次战斗胜利回复 1 点生命", 99, 40, regenPerWin=1,
    lore="它一闪一闪的，像在替你数背过的词。")
add("dustFae", "尘光精灵", "sparkle", "low", ".sprite", "限时战斗 +3 秒", 99, 34, timeBonus=3,
    lore="书页翻动时飞起的那些光尘，其实都是它。")
add("mossFae", "苔灵", "leaf", "low", ".sprite", "受击伤害 -1", 99, 36, defenseBonus=1,
    lore="住在墙角的小家伙。安静，但很结实。")
add("leafFae", "叶灵", "leaf.circle.fill", "mid", ".sprite", "受击伤害 -1", 99, 85, defenseBonus=1,
    lore="一片叶子成精。它最擅长的事是「不被注意」。")
add("emberFae", "火苗精灵", "flame.circle", "mid", ".sprite", "命中伤害 +1", 99, 95, damageBonus=1,
    lore="性子急。你答得慢一点，它就烧你一下。")
add("brookFae", "溪灵", "water.waves", "mid", ".sprite", "每次胜利回血 1", 99, 90, regenPerWin=1,
    lore="潺潺的水声里藏着它的哼唱，据说能催眠词妖。")
add("windFae", "风铃精灵", "wind", "mid", ".sprite", "限时战斗 +5 秒", 99, 92, timeBonus=5,
    lore="它一路推着你走。慢了，它就在耳边吹口哨。")
add("chronoFae", "时汐精灵", "clock.badge.checkmark.fill", "high", ".sprite", "限时战斗时限 +8 秒", 99, 150, timeBonus=8,
    lore="它数着秒过日子，所以特别懂「来不及」的滋味。")
add("coinFae", "金铃精灵", "bell.circle.fill", "high", ".sprite", "每次胜利 +2 金币", 99, 145, coinBonus=2,
    lore="每赚一枚金币就叮一声。它是最诚实的账房。")
add("inkFae", "墨灵", "pencil.circle.fill", "high", ".sprite", "命中 +1，胜利 +1 金币", 99, 152,
    damageBonus=1, coinBonus=1, lore="住在砚台里。你写错字它会把墨弄脏，以示抗议。")
add("healFae", "药灵", "cross.circle", "high", ".sprite", "每次胜利回血 1", 99, 148, regenPerWin=1,
    lore="背着小药篓到处跑，见谁受伤都要管。")
add("swordFae", "剑意精灵", "wand.and.stars.inverse", "rare", ".sprite", "命中伤害 +1", 99, 200, damageBonus=1,
    lore="它本身就是一道剑意。剑客死了，剑意留下来找新主人。")
add("shieldFae", "护心精灵", "shield.checkered", "rare", ".sprite", "每场战斗额外一次格挡", 99, 210, extraShield="true",
    lore="它总挡在你身前，明明只有巴掌大。")
add("starletFae", "小星灵", "star.circle", "rare", ".sprite", "命中 +1，限时 +4 秒", 99, 205,
    damageBonus=1, timeBonus=4, lore="从星河里掉下来的碎片，还带着一点点亮。")
add("mendFae", "回春精灵", "cross.circle.fill", "legendary", ".sprite", "每次胜利回血 2", 99, 320, regenPerWin=2,
    lore="妙手回春不是医术，是它偷偷帮的忙。")
add("starFae", "星辉精灵", "star.circle.fill", "legendary", ".sprite", "命中 +1，受击 -1", 99, 340,
    damageBonus=1, defenseBonus=1, lore="它披着一整条星河当披风，走起路来银光四散。")
add("dreamFae", "梦纹精灵", "moon.zzz.fill", "legendary", ".sprite", "受击 -2", 99, 330, defenseBonus=2,
    lore="它把敌人的攻击变成一场梦。梦里你不会痛。")
add("primordialFae", "鸿蒙小仙", "sparkles.rectangle.stack.fill", "goldLegend", ".sprite",
    "命中伤害 +1，受击 -1，每次胜利 +2 金币", 99, 580, damageBonus=1, defenseBonus=1, coinBonus=2,
    lore="鸿蒙未分时它就在了。它见过第一个词被说出口的那一刻。")
add("chaosFae", "太虚仙童", "circle.hexagongrid.circle.fill", "goldLegend", ".sprite",
    "命中 +2，每次胜利回血 1", 99, 640, damageBonus=2, regenPerWin=1,
    lore="太虚之中一点灵光。它管你叫「小友」，尽管它看着像个孩子。")
add("wordSpirit", "字灵", "textformat.abc", "goldLegend", ".sprite",
    "命中 +2，限时 +6 秒", 99, 620, damageBonus=2, timeBonus=6,
    lore="它是所有单词的本源精灵。它认得你，因为你背过它。")

# ─────────── 生成 Swift 代码
lines = ["    static let catalog: [GameItem] = ["]
group_headers = {
    ".wear(.hat)": "        // ── 穿戴 · 帽子",
    ".wear(.clothes)": "        // ── 穿戴 · 衣服",
    ".wear(.jewelry)": "        // ── 穿戴 · 首饰",
    ".wear(.pants)": "        // ── 穿戴 · 裤子",
    ".wear(.shoes)": "        // ── 穿戴 · 鞋子",
    ".weapon": "        // ── 武器（刀剑弓杖锤枪，不分类展示）",
    ".potion": "        // ── 药水",
    ".pet": "        // ── 宠物",
    ".sprite": "        // ── 精灵",
}
effect_order = ["damageBonus", "defenseBonus", "extraShield", "coinBonus",
                "healAmount", "timeBonus", "regenPerWin"]
seen = set()
ids = set()
for index, (id_, name, icon, tier, category, desc, dur, price, restricted, lore, effects) in enumerate(ITEMS):
    assert id_ not in ids, f"重复 id: {id_}"
    ids.add(id_)
    if category not in seen:
        seen.add(category)
        lines.append(group_headers[category])
    head = [f'id: "{id_}"', f'name: "{name}"', f'icon: "{icon}"',
            f'tier: .{tier}', f'category: {category}']
    tail = [f'effectDesc: "{desc}"', f'maxDurability: {dur}', f'price: {price}',
            f'restrictedTo: {restricted if restricted else "nil"}',
            f'lore: "{lore}"']
    for key in effect_order:
        if key in effects:
            tail.append(f'{key}: {effects[key]}')
    comma = "," if index < len(ITEMS) - 1 else ""
    lines.append(f'        GameItem({", ".join(head)},')
    lines.append(f'                 {", ".join(tail)}){comma}')
lines.append("    ]")

path = "Sources/DailyWord/Features/Game/TowerItems.swift"
with io.open(path, encoding="utf-8") as f:
    content = f.read().split("\n")

start = next(i for i, line in enumerate(content) if "static let catalog" in line)
end = next(i for i, line in enumerate(content) if i > start and line.strip() == "]")
updated = content[:start] + lines + content[end + 1:]

with io.open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(updated))

# 统计
from collections import Counter
tier_count = Counter(item[3] for item in ITEMS)
cat_count = Counter(item[4] for item in ITEMS)
restricted_count = sum(1 for item in ITEMS if item[8])
print(f"物品总数: {len(ITEMS)}  职业限定: {restricted_count}")
print("品质分布:", {k: tier_count[k] for k in ["low", "mid", "high", "rare", "legendary", "goldLegend"]})
print("分类分布:", dict(cat_count))
