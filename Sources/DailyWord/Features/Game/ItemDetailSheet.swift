import SwiftUI

/// 物品详情：效果、职业限定、背景故事、获得与过期时间
struct ItemDetailSheet: View {
    let item: GameItem
    /// 已拥有时传入（用于显示耐久/获得时间/过期时间）
    let owned: OwnedItem?
    let heroContext: HeroClass?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    effectSection
                    restrictionSection
                    loreSection
                    if let owned { ownedSection(owned) }
                    metaSection
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 380, height: 480)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            ItemIcon(item: item, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.title3.bold())
                HStack(spacing: 5) {
                    TierTag(tier: item.tier)
                    Text(categoryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label("\(item.price)", systemImage: "circle.hexagongrid.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            Spacer()
        }
        .padding(16)
    }

    private var categoryText: String {
        if case .wear(let slot) = item.category {
            return "穿戴 · \(slot.label)"
        }
        return item.category.bigLabel
    }

    // MARK: - 效果

    private var effectSection: some View {
        section(title: "效果", icon: "sparkles") {
            Text(item.effectDesc)
                .font(.callout)
            VStack(alignment: .leading, spacing: 4) {
                if item.damageBonus > 0 { statRow("命中伤害", "+\(item.damageBonus)", .red) }
                if item.defenseBonus > 0 { statRow("受击减伤", "-\(item.defenseBonus)", .blue) }
                if item.extraShield { statRow("额外格挡", "每场 1 次", .cyan) }
                if item.coinBonus > 0 { statRow("胜利金币", "+\(item.coinBonus)", .yellow) }
                if item.regenPerWin > 0 { statRow("胜利回血", "+\(item.regenPerWin)", .green) }
                if item.healAmount > 0 {
                    statRow("服用回血", item.healAmount >= 99 ? "回满" : "+\(item.healAmount)", .green)
                }
                if item.timeBonus > 0 {
                    statRow(item.category == .potion ? "使用加时" : "限时加时", "+\(item.timeBonus) 秒", .orange)
                }
                if allStatsEmpty {
                    Text("纯收藏品，无战斗加成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var allStatsEmpty: Bool {
        item.damageBonus == 0 && item.defenseBonus == 0 && !item.extraShield
            && item.coinBonus == 0 && item.regenPerWin == 0
            && item.healAmount == 0 && item.timeBonus == 0
    }

    private func statRow(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(name).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.bold().monospacedDigit()).foregroundStyle(color)
        }
    }

    // MARK: - 适用范围（通用 / 限角色）

    @ViewBuilder
    private var restrictionSection: some View {
        if let restricted = item.restrictedTo {
            section(title: "适用：限角色", icon: "person.crop.circle.badge.exclamationmark") {
                HStack(spacing: 8) {
                    Image(systemName: restricted.icon)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("仅「\(restricted.name)」可装备")
                            .font(.callout.bold())
                            .foregroundStyle(.purple)
                        Text("\(restricted.skillTitle)：\(restricted.skillDesc)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let hero = heroContext {
                    Text(hero == restricted
                         ? "✅ 你当前的身份可以装备它"
                         : "⚠️ 当前身份「\(hero.name)」无法发挥它的效果")
                        .font(.caption)
                        .foregroundStyle(hero == restricted ? .green : .orange)
                }
            }
        } else if item.category == .pet || item.category == .sprite {
            let typeName = item.category == .pet ? "宠物" : "精灵"
            section(title: "类型：\(typeName)", icon: item.category == .pet ? "pawprint.fill" : "sparkles") {
                HStack(spacing: 8) {
                    Image(systemName: item.category == .pet ? "pawprint.fill" : "sparkles")
                        .foregroundStyle(.orange)
                    Text("\(typeName)——非装备，陪伴作战，拥有独立生命值与技能")
                        .font(.callout)
                }
            }
        } else {
            section(title: "适用：通用", icon: "person.3.fill") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("通用装备——五个职业皆可装备使用")
                        .font(.callout)
                }
            }
        }
    }

    // MARK: - 背景故事

    @ViewBuilder
    private var loreSection: some View {
        if !item.lore.isEmpty {
            section(title: "渊源", icon: "book.closed.fill") {
                Text(item.lore)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 状态词：穿戴/武器=耐久，宠物=饱食度，精灵=灵力
    private var stateLabel: String {
        switch item.category {
        case .pet: return "饱食度"
        case .sprite: return "灵力"
        default: return "耐久"
        }
    }

    // MARK: - 持有信息

    private func ownedSection(_ owned: OwnedItem) -> some View {
        section(title: "持有信息", icon: "clock.fill") {
            infoRow("获得时间", Self.formatter.string(from: owned.acquiredAt))
            if item.category == .pet || item.category == .sprite {
                // 宠物/精灵不显示耐久/磨损，生命值在游戏界面显示
                infoRow("类型", item.category == .pet ? "宠物" : "精灵")
            } else if item.maxDurability < 99 && item.category != .potion {
                infoRow(stateLabel, "\(owned.durability)/\(item.maxDurability)")
                ProgressView(value: Double(owned.durability), total: Double(item.maxDurability))
                    .tint(owned.durability <= 3 ? .red : item.tier.color)
            } else if item.category != .potion {
                infoRow(stateLabel, "永不磨损")
            }
            if let expires = owned.expiresAt {
                infoRow("过期时间", Self.formatter.string(from: expires))
                Text(owned.expiryText ?? "")
                    .font(.caption.bold())
                    .foregroundStyle(owned.isExpired ? .red : .orange)
            } else {
                infoRow("有效期", "永久持有")
            }
        }
    }

    private func infoRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    // MARK: - 稀有度说明

    private var metaSection: some View {
        section(title: "品质", icon: "star.circle.fill") {
            HStack(spacing: 4) {
                ForEach(ItemTier.allCases, id: \.rawValue) { tier in
                    Text(tier.label)
                        .font(.system(size: 9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(
                            tier == item.tier ? tier.color.opacity(0.28) : Color.secondary.opacity(0.08)))
                        .foregroundStyle(tier == item.tier ? tier.color : .secondary)
                }
            }
            Text(item.tier >= .legendary
                 ? "极为罕见，只在深处的境界才有机缘遇见。"
                 : "越稀有的物品，出现概率越低。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 通用小节

    @ViewBuilder
    private func section<Content: View>(title: String, icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 11))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
}
