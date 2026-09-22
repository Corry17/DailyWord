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
    /// 词义连线：当前选中的词（等待选释义）
    @State private var selectedMatchWord: String?

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
                        Text("确认撤退？").font(.callout.bold())
                        Text(engine.retreatPenalty())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
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
                // 宠物/精灵生命点 + 状态
                if engine.petMaxHP > 0 {
                    Label("\(engine.petHP)/\(engine.petMaxHP) \(petStateIcon(engine.petState))", systemImage: "pawprint.fill")
                        .foregroundStyle(petStateColor(engine.petState))
                        .help("宠物·\(petStateName(engine.petState))")
                }
                if engine.spriteMaxHP > 0 {
                    Label("\(engine.spriteHP)/\(engine.spriteMaxHP) \(petStateIcon(engine.spriteState))", systemImage: "sparkles")
                        .foregroundStyle(petStateColor(engine.spriteState))
                        .help("精灵·\(petStateName(engine.spriteState))")
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
                    // 宠物/精灵生命点
                    if engine.petMaxHP > 0 {
                        Text("🐾 \(engine.petHP)/\(engine.petMaxHP)")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if engine.spriteMaxHP > 0 {
                        Text("✨ \(engine.spriteHP)/\(engine.spriteMaxHP)")
                            .font(.caption2).foregroundStyle(.purple)
                    }
                }
                Text(engine.stage.subtitle).font(.caption2).foregroundStyle(.secondary)

                realmTrack

                Divider().padding(.horizontal, 20)

                Text(engine.groupChoices.isEmpty
                     ? (engine.floor >= engine.stage.floors ? "⚔️ 境主「\(engine.stage.bossName)」就在前方" : "选择前行的路线")
                     : "🏕️ 组内休整——选择下一步")
                    .font(.subheadline.bold())

                // S2 分叉口：路线预览卡（险路/平路/秘路）
                if !engine.branchRoutes.isEmpty {
                    Text("前方分叉口——选择你的路线")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                    ForEach(engine.branchRoutes, id: \.self) { route in
                        Button { engine.chooseRoute(route) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: route.icon)
                                    .font(.title3)
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(routeColor(route))
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(route.title).font(.subheadline.bold())
                                        Text(route.badge).font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(routeColor(route).opacity(0.15)))
                                            .foregroundStyle(routeColor(route))
                                        Text("难度 \(route.stars)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(route.desc).font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        Text(route.stageCountText).font(.caption2).foregroundStyle(.secondary)
                                        Text(route.rewardText).font(.caption2)
                                            .foregroundStyle(route == .perilous ? .orange : .secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.isRouteUsed(route))
                        .opacity(engine.isRouteUsed(route) ? 0.4 : 1)
                    }
                }

                /// 组内选择：每战后选择下一行动（继续/休息/突击）
                if !engine.groupChoices.isEmpty {
                    GroupChoiceCards(engine: engine)
                }

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
                                    // 关卡组节点：标注组内连战关数
                                    if engine.groupCount(for: node) > 0 {
                                        Text("\(engine.groupCount(for: node)) 关连战").font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                                            .foregroundStyle(.orange)
                                    }
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

    /// 节点三态：未挑战（原色）/ 挑战中（橙）/ 已通关（绿）；下方标注关卡组关数+子关卡进度
    private func trackDot(index: Int, total: Int, isBoss: Bool, passed: Bool, current: Bool) -> some View {
        let icon = isBoss ? "crown.fill"
            : (passed ? "checkmark" : (current ? "figure.walk" : "questionmark"))
        let color: Color = passed ? .green : (current ? .orange : (isBoss ? .red : .secondary))
        let cnt = isBoss ? 0 : engine.groupCount
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
                Text("挑战中 · \(cnt) 关").font(.system(size: 9)).foregroundStyle(.orange)
            } else {
                Text("关卡\(index) · \(cnt) 关").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            // 子关卡进度点（非Boss节点显示组内关数进度）
            if !isBoss, cnt > 0 {
                HStack(spacing: 3) {
                    ForEach(1...cnt, id: \.self) { i in
                        Circle()
                            .fill(passed ? Color.green : (current && i == 1 ? Color.orange : Color.secondary.opacity(0.35)))
                            .frame(width: 5, height: 5)
                    }
                }
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

    private func routeColor(_ route: RouteType) -> Color {
        switch route {
        case .perilous: return .red
        case .steady: return .green
        case .mystery: return .purple
        }
    }

    // MARK: - 组内选择卡片

    /// 关卡组内选择：进度条 + 三条行动路线（继续/休息/突击）
    @ViewBuilder
    private func GroupChoiceCards(engine: TowerGameEngine) -> some View {
        VStack(spacing: 8) {
            // 组进度条
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x2.fill")
                    .foregroundStyle(Color.accentColor)
                Text("关卡组 \(engine.groupIndex)/\(engine.groupTotal)")
                    .font(.callout.bold())
                Spacer()
                // 当前血量：帮助决策是否调息
                Text(engine.hero == .demon ? "🔥 \(engine.hp)" : "❤️ \(engine.hp)/\(engine.maxHP)")
                    .font(.callout.monospacedDigit().bold())
                    .foregroundStyle(engine.hero == .demon ? .orange : hpColor)
            }
            .padding(.horizontal, 4)

            // 进度点
            HStack(spacing: 4) {
                ForEach(1...engine.groupTotal, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < engine.groupIndex ? Color.green : (i == engine.groupIndex ? Color.accentColor : Color.secondary.opacity(0.3)))
                        .frame(height: 4)
                }
            }

            Divider()

            Text("选择下一行动")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(engine.groupChoices, id: \.self) { choice in
                Button { engine.chooseGroupChoice(choice) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: groupChoiceIcon(choice))
                            .font(.title3)
                            .frame(width: 34, height: 34)
                            .foregroundStyle(groupChoiceColor(choice))
                            .background(groupChoiceColor(choice).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(groupChoiceTitle(choice)).font(.subheadline.bold())
                            Text(groupChoiceDesc(choice)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(groupChoiceColor(choice))
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(groupChoiceColor(choice).opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1))
    }

    private func groupChoiceIcon(_ choice: GroupChoice) -> String {
        switch choice {
        case .normal: return engine.nextSubBattleNode?.icon ?? "figure.walk"
        case .rest: return "drop.fill"
        case .rush: return engine.rushSubBattleNode?.icon ?? "flame"
        }
    }

    private func groupChoiceColor(_ choice: GroupChoice) -> Color {
        switch choice {
        case .normal: return Color.accentColor
        case .rest: return .orange
        case .rush: return .red
        }
    }

    private func groupChoiceTitle(_ choice: GroupChoice) -> String {
        switch choice {
        case .normal:
            if let node = engine.nextSubBattleNode {
                let preview = engine.previewSubBattle(node)
                return "进入 · \(preview.name)"
            }
            return "继续战斗"
        case .rest:
            return "调息恢复 +5"
        case .rush:
            if let node = engine.rushSubBattleNode {
                let preview = engine.previewSubBattle(node)
                return "突击 · \(preview.name)"
            }
            return "突击收尾"
        }
    }

    private func groupChoiceDesc(_ choice: GroupChoice) -> String {
        switch choice {
        case .normal:
            if let node = engine.nextSubBattleNode {
                let tag = subBattleTag(node)
                return "\(tag) · 进入下一关继续答题"
            }
            return "进入下一关，继续战斗"
        case .rest:
            return "消耗时间调息，恢复 5 点生命"
        case .rush:
            if let node = engine.rushSubBattleNode {
                let preview = engine.previewSubBattle(node)
                return "跳过中间直取「\(preview.name)」\(preview.icon)"
            }
            return "跳过中间关卡，直取组首领"
        }
    }

    /// 子关卡类型标签
    private func subBattleTag(_ node: NodeType) -> String {
        switch node {
        case .elite: return "⚡精英"
        case .timedTrial: return "⏳限时"
        case .battle: return "⚔️普通"
        default: return ""
        }
    }

    // MARK: - 宠物/精灵状态

    private func petStateColor(_ state: TowerGameEngine.PetSpriteState) -> Color {
        switch state {
        case .healthy: return .green
        case .injured: return .orange
        case .critical: return .red
        case .gone: return .secondary
        }
    }

    private func petStateIcon(_ state: TowerGameEngine.PetSpriteState) -> String {
        switch state {
        case .healthy: return "👍"
        case .injured: return "⚠️"
        case .critical: return "💀"
        case .gone: return "✖️"
        }
    }

    private func petStateName(_ state: TowerGameEngine.PetSpriteState) -> String {
        switch state {
        case .healthy: return "健康"
        case .injured: return "受伤"
        case .critical: return "濒死"
        case .gone: return "已离去"
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

            if event == .ruins {
                // 上古遗迹：三选一宝箱
                ForEach(Array(engine.ruinsOptions.enumerated()), id: \.offset) { idx, opt in
                    Button { engine.selectRuinsOption(idx) } label: {
                        Text(opt).frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(idx == 0 ? .yellow : (idx == 1 ? .green : .red))
                    .controlSize(.large)
                }
                Button {
                    engine.declineEvent(event)
                } label: {
                    Text("绕行离开").frame(minWidth: 150)
                }
                .controlSize(.large)
            } else {
                // 通用事件按钮
                let acceptLabel: String = {
                    switch event {
                    case .forced: return "应战！"
                    case .robber: return "应战！"
                    case .wordTide: return "迎战词妖潮！"
                    case .spring: return "饮泉疗伤"
                    case .earBomb: return "凝神抵御"
                    case .mindTrial: return "进入幻境"
                    case .forkRoad: return "走左边"
                    case .luckFall: return "沐浴祥光"
                    case .wordSpirit: return "花费 30 金币"
                    case .realmSuppress: return "硬闯（惩罚加重）"
                    case .opportunity: return "接受挑战"
                    case .trial: return "接受挑战"
                    default: return "接受"
                    }
                }()
                Button {
                    engine.acceptEvent(event)
                } label: {
                    Label(acceptLabel, systemImage: "bolt.fill")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if event != .forced, event != .robber, event != .wordTide, event != .earBomb, event != .mindTrial, event != .luckFall {
                    Button {
                        engine.declineEvent(event)
                    } label: {
                        Text("绕行离开").frame(minWidth: 150)
                    }
                    .controlSize(.large)
                }
            }
        }
        .padding(30)
    }

    // MARK: - 战斗

    @ViewBuilder
    private var battleView: some View {
        if let battle = engine.battle {
            VStack(spacing: 10) {
                // 战斗提示（宠物技能/墓穴等）
                if let toast = engine.toast {
                    Text(toast)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: battle.enemyIcon)
                            .font(.title2)
                            .foregroundStyle(battle.node == .boss ? .red : .primary)
                        Text(battle.enemyName).font(.headline)
                        // 关卡组进度：第几关/共几关（魔修火焰图标，普适剑图标）
                        if engine.groupTotal > 0 {
                            Label("\(engine.groupIndex)/\(engine.groupTotal)",
                                  systemImage: engine.hero == .demon ? "flame.fill" : "sword")
                                .font(.callout.monospacedDigit().bold())
                                .foregroundStyle(engine.hero == .demon ? .red : .orange)
                            // 阶段类型标签
                            Text(subBattleTag(battle.node))
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                .foregroundStyle(Color.accentColor)
                        }
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
                                .fill(index < battle.enemyHP
                                      ? (Double(index) / Double(max(1, battle.enemyMaxHP)) > 0.5
                                         ? Color.red : (Double(index) / Double(max(1, battle.enemyMaxHP)) > 0.25
                                                         ? Color.orange : Color.yellow))
                                      : Color.secondary.opacity(0.2))
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

                    if question.kind == .listen {
                        Text("🎧 听音辨义——选择正确释义")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(question.prompt)
                            .font(question.kind == .enToCn
                                  ? .system(size: 30, weight: .bold, design: .rounded)
                                  : .system(size: 17, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 24)
                    }

                    if question.kind == .listen || question.kind == .listenSpell {
                        // 听音辨词/听音拼写：播放按钮
                        Button {
                            SpeechService.shared.speak(question.word.headword)
                        } label: {
                            Label("🔊 播放发音", systemImage: "speaker.wave.3.fill")
                                .font(.title2)
                                .padding(10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if question.kind == .listen {
                        // 听音辨词：四选一
                        choiceArea(question, battle: battle)
                    } else if question.kind == .match || question.kind == .sentenceMatch {
                        matchArea(question)
                    } else if question.kind == .spell || question.kind == .listenSpell {
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

    /// 词义连线：左列单词 + 右列释义，点词→点释义配对（4 对全配自动判分）
    private func matchArea(_ question: TowerGameEngine.Question) -> some View {
        let leftWords = question.pairs.map(\.word).shuffled()
        let rightDefs = question.pairs.map(\.definition).shuffled()
        return HStack(alignment: .top, spacing: 14) {
            // 左列：单词
            VStack(spacing: 6) {
                ForEach(leftWords, id: \.self) { word in
                    let paired = engine.matchAnswers[word]
                    Button {
                        selectedMatchWord = selectedMatchWord == word ? nil : word
                    } label: {
                        Text(word)
                            .font(.callout.bold())
                            .frame(maxWidth: 130, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(selectedMatchWord == word ? Color.accentColor.opacity(0.2)
                                      : (paired != nil ? Color.green.opacity(0.15) : Color.secondary.opacity(0.08))))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selectedMatchWord == word ? Color.accentColor
                                              : (paired != nil ? Color.green : .clear), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(paired != nil)
                }
            }
            // 右列：释义
            VStack(spacing: 6) {
                ForEach(rightDefs, id: \.self) { def in
                    let usedBy = engine.matchAnswers.first(where: { $0.value == def })?.key
                    Button {
                        if let w = selectedMatchWord {
                            engine.selectMatchPair(word: w, definition: def)
                            selectedMatchWord = nil
                        }
                    } label: {
                        Text(def)
                            .font(.caption)
                            .frame(maxWidth: 200, alignment: .leading)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(usedBy != nil ? Color.green.opacity(0.15) : Color.secondary.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(usedBy != nil ? Color.green : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedMatchWord == nil || usedBy != nil)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
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
                .onHover { hovering in
                    // hover 效果仅在有选项指示灯时生效
                }
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
                HStack(spacing: 6) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(correct ? Color.green : Color.red)
                    Text(correct ? "命中！" : "挨了一击")
                        .foregroundStyle(correct ? Color.green : Color.red)
                        .font(.callout.bold())
                    if correct, battle.perfect {
                        Label("完美 ×1.5", systemImage: "star.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                    }
                }
            }
            if battle.weakened {
                Label("破绽：首领攻击减半", systemImage: "shield.slash.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
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
