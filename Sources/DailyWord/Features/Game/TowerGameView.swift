import SwiftUI
import DailyWordCore

/// 爬塔背单词 · 修仙路
struct TowerGameView: View {
    @ObservedObject var engine: TowerGameEngine
    @State private var showInventory = false
    @State private var showCollection = false
    @State private var showRealmShop = false
    @State private var showTowerAchievements = false
    @State private var showCrippleConfirm = false
    @State private var showAbandonConfirm = false

    var body: some View {
        ZStack {
            // 魔修红黑背景（条件图层：切换身份时干净移除，避免旧背景残留导致文字不可见）
            if engine.hero == .demon {
                Color(red: 0.16, green: 0.05, blue: 0.08).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                header
                Divider()
                content
                    .id(String(describing: engine.phase))   // phase 切换时强制重建，避免视图切换竞态导致文字/布局异常
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 500, height: 620)
            .tint(engine.hero == .demon ? Color.orange : Color.accentColor)
        .preferredColorScheme(engine.hero == .demon ? .dark : .light)   // 显式浅色：避免窗口 appearance 卡深色导致文字不可见
        .overlay {
            if engine.showSkillPreview {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.orange)
                        Text("怪物技能").font(.title2.bold())
                        if let battle = engine.battle {
                            Text(battle.enemyName).font(.headline).foregroundStyle(.red)
                            Text(battle.ability.title).font(.title3.bold()).foregroundStyle(.orange)
                            Text(battle.ability.desc).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
                        }
                        HStack(spacing: 12) {
                            Button {
                                showInventory = true   // 不关闭技能预览：换完装备回来继续
                            } label: {
                                Text("更换装备")
                                    .font(.callout.bold())
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                            Button { engine.dismissSkillPreview() } label: {
                                Text("了解，开始战斗")
                                    .font(.callout.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.5), lineWidth: 1))
                }
            }
            if engine.retreatConfirming {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("撤退会有随机损失（待定）")
                            .font(.callout.bold())
                        Text("金币、生命、装备耐久、随从状态可能受损")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button { engine.cancelRetreat() } label: {
                                Text("取消").frame(width: 70)
                            }
                            .buttonStyle(.bordered)
                            Button { engine.fleeBattle() } label: {
                                Text("确认撤退").frame(width: 90)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.gray.opacity(0.35), lineWidth: 1)
                    )
                }
            }
        }
        .sheet(isPresented: $showInventory) { InventorySheet(engine: engine) }
        .sheet(isPresented: $showCollection) { CollectionSheet(engine: engine) }
        .sheet(isPresented: $showRealmShop) { ShopSheet(engine: engine) }
        .sheet(isPresented: $showTowerAchievements) { TowerAchievementsSheet() }
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 10) {
            switch engine.phase {
            case .map, .battle, .event, .merchant:
                Label("\(engine.stage.name) \(engine.floor)/\(engine.stage.floors)",
                      systemImage: engine.stage.icon)
                if engine.hero == .demon {
                    Label("\(engine.hp)", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                        .help("不死不灭：受击反噬概率 \(engine.demonBacklashChance)%（负血越深越危险）")
                } else {
                    Label("\(engine.hp)/\(engine.maxHP)", systemImage: "heart.fill")
                        .foregroundStyle(hpColor)
                }
                if engine.demonMode {
                    Label("魔化", systemImage: "flame.fill").foregroundStyle(.red)
                }
                heroBadge
            default:
                Label("问词仙道", systemImage: "mountain.2.fill")
            }
            Spacer()
            Label("\(engine.coins)", systemImage: "circle.hexagongrid.circle.fill")
                .foregroundStyle(.yellow)
                .help("金币")
            Button { showInventory = true } label: { Image(systemName: "duffle.bag.fill") }
                .buttonStyle(.plain)
                .help("背包与穿戴")
            Button { showCollection = true } label: { Image(systemName: "square.grid.3x3.fill") }
                .buttonStyle(.plain)
                .help("收集图鉴")
            Label(engine.difficulty.name, systemImage: engine.difficulty.icon)
                .foregroundStyle(.secondary)
                .help("难度由学习进度自动调整")
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// 虚拟人物 + 穿戴小图标
    private var heroBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: engine.hero.icon)
            ForEach(Array(engine.equipped.values.sorted()), id: \.self) { itemId in
                if let item = GameItem.item(itemId) {
                    Image(systemName: item.icon)
                        .font(.system(size: 8))
                        .foregroundStyle(item.tier.color)
                }
            }
        }
    }

    private var hpColor: Color {
        let ratio = Double(engine.hp) / Double(max(1, engine.maxHP))
        return ratio > 0.5 ? .green : (ratio > 0.25 ? .orange : .red)
    }

    // MARK: - 主内容

    @ViewBuilder
    private var content: some View {
        switch engine.phase {
        case .resumePrompt: resumePrompt
        case .realm: realmView
        case .demonRealm: demonRealmView
        case .map: mapView
        case .event(let event): eventView(event)
        case .merchant: ShopInline(engine: engine)
        case .battle: battleView
        case .stageClear: stageClearView
        case .pathComplete: pathCompleteView
        case .defeat: defeatView
        }
    }

    // MARK: - 继续 / 重新开始

    private var resumePrompt: some View {
        VStack(spacing: 16) {
            Text("🗼").font(.system(size: 52))
            Text("发现上次的冒险").font(.title2.bold())
            Text(engine.savedFloorDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            Button { engine.continueRun() } label: {
                Label("继续冒险", systemImage: "play.fill").frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button { engine.abandonSave() } label: {
                Label("放弃存档，回到仙道", systemImage: "arrow.counterclockwise").frame(minWidth: 150)
            }
            .controlSize(.large)
        }
        .padding(30)
    }

    // MARK: - 魔界（自断筋骨 1/100 走火入魔）

    private var demonRealmView: some View {
        VStack(spacing: 16) {
            Text("🔥").font(.system(size: 60))
            Text("走火入魔！").font(.title.bold()).foregroundStyle(.red)
            Text("断筋一剑引动心魔，你坠入了传说中的魔界——\n此地以魔入道，力量暴涨，却也反噬其身。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 6) {
                Label("魔功：每次命中伤害 +2", systemImage: "flame.fill").foregroundStyle(.red)
                Label("贪婪：战斗金币翻倍", systemImage: "circle.hexagongrid.circle.fill").foregroundStyle(.orange)
                Label("反噬：答错时多掉 1 血", systemImage: "drop.fill").foregroundStyle(.purple)
            }
            .font(.caption)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))

            Button {
                engine.enterDemonRealm()
            } label: {
                Label("踏入魔界修炼", systemImage: "flame.circle.fill")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button { engine.resistDemon() } label: {
                Text("抵住心魔，回到仙道").frame(minWidth: 180)
            }
            .controlSize(.large)
        }
        .padding(30)
    }

    // MARK: - 仙道（弯曲山路）

    private var realmView: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("⛰️ 问词仙道").font(.title2.bold())
                Text("从凡人起步，逐境而上。每一境都是一条弯曲山道，途中有岔路；全程生命共用，一人到底……")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button { showRealmShop = true } label: {
                        Label("云间商城", systemImage: "cart.fill")
                    }
                    .controlSize(.small)
                    Button { showCollection = true } label: {
                        Label("收集图鉴 \(engine.collected.count)/\(GameItem.catalog.count)",
                              systemImage: "square.grid.3x3.fill")
                    }
                    .controlSize(.small)
                    Button { showTowerAchievements = true } label: {
                        Label("仙途成就", systemImage: "trophy.fill")
                    }
                    .controlSize(.small)
                }

                windingPath

                if engine.runInProgress {
                    // 本次修仙路进行中：锁定角色
                    lockedHeroRow

                    if !engine.savedFloorDescription.isEmpty {
                        Label(engine.savedFloorDescription, systemImage: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        engine.continueRun()
                    } label: {
                        Label("继续修仙路", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        showCrippleConfirm = true
                    } label: {
                        Label("自断筋骨·重踏修仙路", systemImage: "bolt.heart")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    Text("本次修仙路已锁定角色；自断筋骨可重选道侣从凡人重头，背包与穿戴保留不变")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if engine.hero == .demon {
                    // 魔修身份：无职业选择（隐藏职业，无选择）
                    VStack(spacing: 6) {
                        Label("当前身份：魔修（隐藏职业）", systemImage: "flame.fill")
                            .font(.callout.bold())
                            .foregroundStyle(.orange)
                        Text(engine.hero.skillDesc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))

                    Button {
                        engine.start(as: engine.hero)
                    } label: {
                        Label("踏上修仙路（从凡人起）", systemImage: "figure.walk.motion")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("以当前道侣【\(engine.hero.name)】开启新一轮挑战；突破一境可存档退出，下次继续")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    // 无进行中的路、非魔修：可自由选角色
                    heroPicker

                    Button {
                        engine.start(as: engine.hero)
                    } label: {
                        Label("踏上修仙路（从凡人起）", systemImage: "figure.walk.motion")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("以当前道侣【\(engine.hero.name)】开启新一轮挑战；突破一境可存档退出，下次继续")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if engine.pathCompleted {
                    // 伏笔：不揭示全图
                    HStack(spacing: 10) {
                        Image(systemName: "cloud.fog.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("道祖之上……").font(.headline)
                            Text("十六境皆破的那一瞬，道之尽头似有一片广袤天地的轮廓一闪而过。那是幻觉，还是……？")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.08)))
                }
            }
            .padding(18)
        }
        .confirmationDialog("自断筋骨，重踏修仙路？", isPresented: $showCrippleConfirm, titleVisibility: .visible) {
            Button("确认自断筋骨（保留背包）", role: .destructive) { engine.selfCripple() }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("当前修仙路的进度将丢失，可重新选择道侣从凡人开始。背包、穿戴、图鉴与金币都会保留。")
        }
    }

    /// 锁定的道侣行（修仙路进行中不可换角色）
    private var lockedHeroRow: some View {
        HStack(spacing: 10) {
            Image(systemName: engine.hero.icon)
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("道侣：\(engine.hero.name)").font(.callout.bold())
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(engine.hero.skillTitle)：\(engine.hero.skillDesc)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.3)))
    }

    /// 仙道页人物切换（横向）：选好后进关直接开打
    private var heroPicker: some View {
        VStack(spacing: 6) {
            HStack {
                Text("道侣：\(engine.hero.name)")
                    .font(.callout.bold())
                Text("❤️ \(engine.hero.maxHP) · \(engine.hero.skillTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HeroClass.allCases.filter { $0 != .demon }) { hero in
                        let active = hero == engine.hero
                        Button {
                            engine.selectHero(hero)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: hero.icon)
                                    .font(.title3)
                                Text(hero.name)
                                    .font(.caption2.weight(active ? .bold : .regular))
                            }
                            .frame(width: 60, height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1.5)
                            )
                            .foregroundStyle(active ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .help(hero.skillDesc)
                    }
                    if engine.hero == .demon {
                        VStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text("魔修（隐藏职业）")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                        }
                        .frame(width: 60, height: 54)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.orange.opacity(0.6), lineWidth: 1.5)
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            Text(engine.hero.skillDesc)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.3)))
    }

    /// 闯关之路（横向可拖动的方框）：凡人→炼气初期→……，仅揭示已至境界 + 一个云雾伏笔
    private var windingPath: some View {
        let reached = Array(TowerStage.all.prefix(engine.unlockedStage))
        let showFog = engine.unlockedStage < TowerStage.all.count
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("闯关之路", systemImage: "map.fill").font(.caption.bold())
                Spacer()
                Text("已至 \(engine.unlockedStage)/\(TowerStage.all.count) 境")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    ForEach(Array(reached.enumerated()), id: \.element.index) { idx, stage in
                        stageNode(stage)
                        if idx < reached.count - 1 || showFog {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 3)
                        }
                    }
                    if showFog { fogNode() }
                }
                .padding(10)
            }
            .frame(height: 86)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.2)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
        }
    }

    /// 云雾锁道：不揭示前方境界名字（伏笔）
    private func fogNode() -> some View {
        VStack(spacing: 3) {
            Image(systemName: "cloud.fog.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
                .background(Circle().fill(Color.secondary.opacity(0.1)))
            Text("云雾锁道").font(.system(size: 10)).foregroundStyle(.secondary)
            Text("？？？").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(width: 70)
    }

    private func stageNode(_ stage: TowerStage) -> some View {
        let cleared = stage.index < engine.unlockedStage || (engine.pathCompleted && stage.index == TowerStage.all.count)
        let isCurrent = stage.index == engine.unlockedStage && !engine.pathCompleted
        return VStack(spacing: 3) {
            Image(systemName: stage.icon)
                .font(.title3)
                .frame(width: 40, height: 40)
                .foregroundStyle(cleared ? .green : Color.accentColor)
                .background(Circle().fill((cleared ? Color.green : Color.accentColor).opacity(isCurrent ? 0.22 : 0.12)))
                .overlay(Circle().strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
            Text(stage.name)
                .font(.system(size: 10).weight(isCurrent ? .bold : .regular))
                .lineLimit(1)
            if cleared {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9)).foregroundStyle(.green)
            } else if isCurrent {
                Text("当前").font(.system(size: 9)).foregroundStyle(Color.accentColor)
            } else {
                Text("·").font(.system(size: 9)).foregroundStyle(.clear)
            }
        }
        .frame(width: 66)
        .help("\(stage.name) · \(stage.floors) 关卡 · 境主\(stage.bossName)")
    }

    // MARK: - 境内分支

    private var mapView: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let toast = engine.toast {
                    Text(toast)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 6) {
                    Image(systemName: engine.stage.icon).foregroundStyle(Color.accentColor)
                    Text("【\(engine.stage.name)】").font(.headline)
                    Text("节点 \(min(engine.floor, engine.stage.floors))/\(engine.stage.floors)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(engine.hero == .demon ? "🔥 \(engine.hp)（反噬 \(engine.demonBacklashChance)%）" : "❤️ \(engine.hp)/\(engine.maxHP)")
                        .font(.caption).foregroundStyle(.red)
                }
                Text(engine.stage.subtitle).font(.caption2).foregroundStyle(.secondary)

                realmTrack

                Divider().padding(.horizontal, 20)

                Text(engine.floor >= engine.stage.floors ? "⚔️ 境主「\(engine.stage.bossName)」就在前方" : "选择前行的路线")
                    .font(.subheadline.bold())

                ForEach(Array(engine.choices.enumerated()), id: \.offset) { _, node in
                    Button { engine.choose(node) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: node.icon)
                                .font(.title3)
                                .frame(width: 34, height: 34)
                                .foregroundStyle(nodeColor(node))
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(routeTitle(node)).font(.subheadline.bold())
                                    if isShortcut(node) {
                                        Text("捷径").font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.red.opacity(0.15)))
                                            .foregroundStyle(.red)
                                    }
                                }
                                Text(routeDesc(node)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 16) {
                    Button {
                        engine.backToRealm()
                    } label: {
                        Label("回首页（存档）", systemImage: "house.fill")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showAbandonConfirm = true
                    } label: {
                        Label("放弃修仙路", systemImage: "flag.slash")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
            .padding(18)
        }
        .confirmationDialog("放弃本次修仙路？", isPresented: $showAbandonConfirm, titleVisibility: .visible) {
            Button("确认放弃（本次结束）", role: .destructive) { engine.abandonRun() }
            Button("继续闯关", role: .cancel) {}
        } message: {
            Text("放弃后本次修仙路直接结束，当前进度不保留（背包与穿戴仍在）。若只是想稍后再继续，请选“回首页（存档）”。")
        }
    }

    private func isShortcut(_ node: NodeType) -> Bool {
        if case .elite = node { return true }
        return false
    }

    private func routeTitle(_ node: NodeType) -> String {
        isShortcut(node) ? "捷径 · \(engine.stage.eliteName)" : node.title
    }

    private func routeDesc(_ node: NodeType) -> String {
        isShortcut(node) ? "路短但难：小 Boss 挡道，胜利可跳过一个节点" : node.desc
    }

    /// 境内弯曲山道（S 形虚线）：底部为起点，顶部为境主；节点 = 本境关卡
    private var realmTrack: some View {
        let n = max(1, engine.stage.floors)
        let rowHeight: CGFloat = 62
        let height = rowHeight * CGFloat(n) + (n == 1 ? 40 : 0)
        return GeometryReader { geo in
            let w = geo.size.width
            let point: (Int) -> CGPoint = { i in
                let y = height - rowHeight / 2 - rowHeight * CGFloat(i)   // i=0 在底
                let x = w * (i % 2 == 0 ? 0.30 : 0.70)
                return CGPoint(x: x, y: y)
            }
            ZStack {
                // 蜒蚎的虚线
                Path { path in
                    let pts = (0..<n).map(point)
                    guard let first = pts.first else { return }
                    path.move(to: first)
                    if n == 1 {
                        // 凡人：一个圈 + 一条线划向前方
                        path.addLine(to: CGPoint(x: first.x, y: first.y - rowHeight * 0.7))
                    } else {
                        for i in 1..<pts.count {
                            let prev = pts[i - 1], curr = pts[i]
                            let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                            path.addQuadCurve(to: mid, control: CGPoint(x: prev.x, y: (prev.y + mid.y) / 2))
                            path.addQuadCurve(to: curr, control: CGPoint(x: curr.x, y: (mid.y + curr.y) / 2))
                        }
                    }
                }
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))
                .foregroundStyle(Color.accentColor.opacity(0.5))

                // 节点
                ForEach(0..<n, id: \.self) { i in
                    let f = i + 1
                    trackDot(index: f, total: n, isBoss: f == n,
                             passed: f < engine.floor, current: f == engine.floor)
                        .position(point(i))
                }
            }
        }
        .frame(height: height)
    }

    private func trackDot(index: Int, total: Int, isBoss: Bool, passed: Bool, current: Bool) -> some View {
        let icon = isBoss ? "crown.fill"
            : (passed ? "checkmark" : (current ? "figure.walk" : "questionmark"))
        let color: Color = passed ? .green : (current ? Color.accentColor : (isBoss ? .red : .secondary))
        return VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption.bold())
                .frame(width: 32, height: 32)
                .foregroundStyle(color)
                .background(Circle().fill(color.opacity(current ? 0.25 : 0.12)))
                .overlay(Circle().strokeBorder(current ? color : (isBoss ? color.opacity(0.5) : .clear), lineWidth: 2))
            if isBoss {
                Text("境主").font(.system(size: 9)).foregroundStyle(.red)
            } else if current {
                Text("你在这里").font(.system(size: 9)).foregroundStyle(Color.accentColor)
            } else {
                Text("关卡\(index)").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .opacity(passed || current || isBoss ? 1 : 0.55)
    }

    private func nodeColor(_ node: NodeType) -> Color {
        switch node {
        case .boss: return .red
        case .elite: return .red
        case .rest: return .orange
        case .merchant: return .purple
        case .timedTrial: return .pink
        default: return Color.accentColor
        }
    }

    // MARK: - 突发事件

    private func eventView(_ event: TowerEvent) -> some View {
        VStack(spacing: 16) {
            Text(event.title).font(.title2.bold())
            Text(event.desc)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button {
                engine.acceptEvent(event)
            } label: {
                Label(event == .forced ? "应战！" : "接受挑战", systemImage: "bolt.fill")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            if event != .forced {
                Button {
                    engine.declineEvent(event)
                } label: {
                    Text("绕行离开").frame(minWidth: 150)
                }
                .controlSize(.large)
            }
        }
        .padding(30)
    }

    // MARK: - 战斗

    @ViewBuilder
    private var battleView: some View {
        if let battle = engine.battle {
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: battle.enemyIcon)
                            .font(.title2)
                            .foregroundStyle(battle.node == .boss ? .red : .primary)
                        Text(battle.enemyName).font(.headline)
                        if battle.isTimed {
                            Label("\(battle.timeLeft)s", systemImage: "timer")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(battle.timeLeft <= 10 ? .red : .orange)
                        }
                        Label("+\(battle.coinReward)", systemImage: "circle.hexagongrid.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<battle.enemyMaxHP, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(index < battle.enemyHP ? Color.red : Color.secondary.opacity(0.2))
                                .frame(height: 8)
                        }
                    }
                    .frame(width: 250)
                    if battle.mode == .trial {
                        Text("突发挑战：答错不扣血，超时无惩罚")
                            .font(.caption2)
                            .foregroundStyle(.pink)
                    }
                    if battle.ability != .none {
                        Label("\(battle.ability.title)：\(battle.ability.desc)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    if battle.skillsDisabled {
                        Text("🔒 职业技能已被封印")
                            .font(.caption2).foregroundStyle(.purple)
                    } else if engine.hero == .mage && battle.combo >= 2 {
                        Text("🔥 连击 ×\(battle.combo)\(battle.combo >= 3 ? "（伤害+1）" : "")")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 8)

                Divider().padding(.horizontal, 30)

                if let question = engine.question {
                    Text(question.kind.label)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .foregroundStyle(Color.accentColor)

                    Text(question.prompt)
                        .font(question.kind == .enToCn
                              ? .system(size: 30, weight: .bold, design: .rounded)
                              : .system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 24)

                    if question.kind == .spell {
                        spellArea(question)
                    } else {
                        choiceArea(question, battle: battle)
                    }

                    statusLine(battle)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func choiceArea(_ question: TowerGameEngine.Question,
                            battle: TowerGameEngine.Battle) -> some View {
        VStack(spacing: 7) {
            ForEach(question.options.indices, id: \.self) { index in
                Button { engine.answer(index) } label: {
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text(question.options[index]).lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(optionBackground(index, battle: battle, question: question),
                                in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(battle.lastAnswerCorrect != nil)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            }
        }
        .padding(.horizontal, 26)
    }

    private func spellArea(_ question: TowerGameEngine.Question) -> some View {
        VStack(spacing: 8) {
            Text(question.spellHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("输入英文单词", text: Binding(
                    get: { engine.spellInput },
                    set: { engine.spellInput = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { engine.submitSpell() }
                Button("确定") { engine.submitSpell() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ battle: TowerGameEngine.Battle) -> some View {
        HStack(spacing: 12) {
            if engine.hero == .knight {
                Label(battle.shieldAvailable ? "格挡就绪" : "格挡已用",
                      systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(battle.shieldAvailable ? Color.green : .secondary)
            }
            if battle.extraShieldAvailable {
                Label("护心符", systemImage: "seal.fill").foregroundStyle(.cyan)
            }
            if engine.hero == .rogue {
                Button { engine.skipQuestion() } label: {
                    Label("妙手跳过", systemImage: "arrow.uturn.right")
                }
                .disabled(!battle.skipAvailable || battle.lastAnswerCorrect != nil)
            }
            // 限时战斗可嗑时之沙
            if battle.isTimed,
               let sand = engine.inventory.first(where: { $0.id == "timeSand" }) {
                Button { engine.useConsumable(sand) } label: {
                    Label("时之沙", systemImage: "hourglass")
                }
            }
            if battle.canRetreat {
                Button {
                    engine.requestRetreat()
                } label: {
                    Label("撤退", systemImage: "figure.run")
                }
                .foregroundStyle(.secondary)
            }
            if let correct = battle.lastAnswerCorrect {
                Text(correct ? "⚔️ 命中！" : "💥 挨了一击")
                    .foregroundStyle(correct ? Color.green : Color.red)
                    .font(.callout.bold())
            }
        }
        .font(.caption)
        .frame(height: 24)
    }

    private func optionBackground(_ index: Int, battle: TowerGameEngine.Battle,
                                  question: TowerGameEngine.Question) -> Color {
        guard battle.lastAnswerCorrect != nil else { return Color.secondary.opacity(0.12) }
        if index == question.correctIndex { return Color.green.opacity(0.3) }
        if index == battle.chosenIndex { return Color.red.opacity(0.3) }
        return Color.secondary.opacity(0.08)
    }

    // MARK: - 结算

    private var stageClearView: some View {
        VStack(spacing: 14) {
            Text("⚡️").font(.system(size: 56))
            Text("境界突破！\(engine.justClearedStageName) 已通").font(.title2.bold())
            Text(engine.hero == .demon
                 ? "已迈入【\(engine.stage.name)】· 🔥 \(engine.hp)（反噬 \(engine.demonBacklashChance)%）"
                 : "根基更厚（上限 +5），已迈入【\(engine.stage.name)】· ❤️ \(engine.hp)/\(engine.maxHP)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let toast = engine.toast {
                Text(toast).font(.caption).foregroundStyle(.orange)
            }

            Button { engine.continueToNextStage() } label: {
                Label("乘胜追击，进入\(engine.stage.name)", systemImage: "arrow.up.circle.fill")
                    .frame(minWidth: 190)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button { engine.backToRealm() } label: {
                Text("存档退出（下次从\(engine.stage.name)继续）").frame(minWidth: 190)
            }
            .controlSize(.large)
        }
        .padding(30)
    }

    /// 伏笔：不揭示全图，只留一个悬念
    private var pathCompleteView: some View {
        VStack(spacing: 14) {
            Text("🌫️").font(.system(size: 56))
            Text("问词仙道 · 全线贯通！").font(.title.bold())
            Text("五境皆破，心魔俯首。\n就在此刻，山巅云海骤然翻涌——\n雾霭深处，仿佛有一片广袤大陆的轮廓，一闪而逝……")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button { engine.backToRealm() } label: {
                Label("下山休整", systemImage: "figure.walk.departure")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
    }

    private var defeatView: some View {
        VStack(spacing: 14) {
            Text("💀").font(.system(size: 56))
            Text("陨落于\(engine.stage.name)第 \(engine.floor) 层…").font(.title2.bold())
            Text("金币与收集不会丢失。复习一下，再来！")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button { engine.backToRealm() } label: {
                Text("回仙道重整旗鼓").frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
    }


// MARK: - 仙途成就面板（独立于学习成就总览）

struct TowerAchievementsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("🏔️ 仙途成就", systemImage: "trophy.fill")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(RewardEngine.towerAchievements()) { a in
                        cell(a)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 480, height: 520)
    }

    private func cell(_ a: Achievement) -> some View {
        let mystery = a.isMystery
        return VStack(spacing: 5) {
            Image(systemName: mystery ? "questionmark" : a.icon)
                .font(.title3)
                .frame(width: 36, height: 36)
                .foregroundStyle(mystery ? Color.purple : (a.unlocked ? Color.orange : Color.secondary))
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(mystery ? Color.purple.opacity(0.14) : Color.orange.opacity(a.unlocked ? 0.16 : 0.08))
                )
            Text(mystery ? "？？？" : a.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(mystery ? Color.purple : .primary)
                .lineLimit(1)
            Text(mystery ? "神秘成就" : a.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if mystery {
                Text("达成后揭晓")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.purple.opacity(0.8))
            } else {
                ProgressView(value: a.ratio)
                    .tint(a.unlocked ? Color.orange : Color.secondary)
                Text(a.unlocked ? "✅ +\(a.xpReward) XP"
                     : "\(a.progress)/\(a.goal) · +\(a.xpReward) XP")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(mystery ? 0 : 0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(mystery ? Color.purple.opacity(0.5)
                              : (a.unlocked ? Color.orange.opacity(0.5) : Color.clear), lineWidth: 1)
        )
    }
}

}
