import SwiftUI

// MARK: - 背包（横向分类切换）

struct InventorySheet: View {
    @ObservedObject var engine: TowerGameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var tab: ItemTab = .weapon
    @State private var detail: OwnedItem?

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("🎒 背包与穿戴").font(.headline)
                if !engine.canChangeEquipment {
                    Text("⚠️ 打关中不可更换装备")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("\(engine.inventory.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(engine.coins)", systemImage: "circle.hexagongrid.circle.fill")
                    .foregroundStyle(.yellow)
                Button("关闭") { dismiss() }
            }

            ItemTabBar(selection: $tab) { tab in
                "\(owned(in: tab).count)"
            }

            // 当前分类已装备的一件
            if let equippedItem = equippedItem(in: tab) {
                HStack(spacing: 6) {
                    Text(stateLabel(for: equippedItem)).font(.caption2).foregroundStyle(.secondary)
                    ItemIcon(item: equippedItem, size: 20, revealed: engine.isDemonItemRevealed(equippedItem))
                    Text(equippedItem.name).font(.caption.bold())
                    TierTag(tier: equippedItem.tier)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            ScrollView {
                VStack(spacing: 8) {
                    let items = owned(in: tab)
                    if items.isEmpty {
                        Text("暂无\(tab.label)，去商城或秘宝洞窟看看吧")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                    }
                    ForEach(items.sorted { ($0.item?.tier ?? .low) > ($1.item?.tier ?? .low) }) { owned in
                        row(owned)
                    }
                }
            }

            if let toast = engine.toast {
                Text(toast).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 470, height: 540)
        .sheet(item: $detail) { owned in
            if let item = owned.item {
                ItemDetailSheet(item: item, owned: owned, heroContext: engine.hero)
            }
        }
    }

    private func owned(in tab: ItemTab) -> [OwnedItem] {
        engine.inventory.filter { owned in
            guard let item = owned.item else { return false }
            // 魔器：魔修或已拥有（获得后揭示真容）才显示；其余隐藏
            if item.tier == .demon, engine.hero != .demon, !engine.collected.contains(item.id) { return false }
            return tab.matches(item)
        }
    }

    private func equippedItem(in tab: ItemTab) -> GameItem? {
        owned(in: tab).compactMap(\.item).first { engine.isEquipped($0) }
    }

    @ViewBuilder
    private func row(_ owned: OwnedItem) -> some View {
        if let item = owned.item {
            HStack(spacing: 10) {
                Button {
                    detail = owned
                } label: {
                    HStack(spacing: 10) {
                        ItemIcon(item: item, revealed: engine.isDemonItemRevealed(item))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(engine.isDemonItemRevealed(item) ? item.name : "???").font(.subheadline.bold())
                                TierTag(tier: item.tier)
                                if engine.isEquipped(item) {
                                    Text(stateLabel(for: item)).font(.caption2).foregroundStyle(.green)
                                }
                                if !engine.usable(item) {
                                    Text("限定不可用").font(.caption2).foregroundStyle(.red)
                                }
                                if let expiry = owned.expiryText {
                                    Label(expiry, systemImage: "clock.badge.exclamationmark")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Text("\(engine.isDemonItemRevealed(item) ? item.effectDesc : "???")\(durabilityText(item: item, owned: owned))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if item.category == .potion {
                    Button("使用") { engine.useConsumable(owned) }
                        .disabled(item.timeBonus > 0 || !engine.canChangeEquipment)   // 打关禁换装
                } else if engine.isEquipped(item) {
                    Button(isCompanion(item) ? "召回" : "卸下") {
                        if let key = item.category.equipKey { engine.unequip(key) }
                    }
                    .disabled(!engine.canChangeEquipment)
                } else {
                    Button(isCompanion(item) ? "携带" : "装备") { engine.equip(owned) }
                        .disabled(!engine.canChangeEquipment || !engine.usable(item))   // 打关禁换装 + 限定不符灰显
                        .help(!engine.usable(item) ? "当前角色无法使用该限定装备" : "")
                }
            }
            .padding(9)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func durabilityText(item: GameItem, owned: OwnedItem) -> String {
        guard item.maxDurability < 99, item.category != .potion else { return "" }
        return " · \(stateLabel(for: item)) \(owned.durability)/\(item.maxDurability)"
    }

    /// 宠物/精灵不是"装备"，用随从语义
    private func isCompanion(_ item: GameItem) -> Bool {
        item.category == .pet || item.category == .sprite
    }

    /// 状态词：穿戴/武器=耐久，宠物=饱食度，精灵=灵力
    private func stateLabel(for item: GameItem) -> String {
        switch item.category {
        case .pet: return "饱食度"
        case .sprite: return "灵力"
        default: return "耐久"
        }
    }
}

// MARK: - 收集图鉴（横向分类切换，未获得显示 ???）

struct CollectionSheet: View {
    @ObservedObject var engine: TowerGameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var tab: ItemTab = .hat
    @State private var detail: GameItem?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("📜 收集图鉴").font(.headline)
                Text("\(engine.collected.count)/\(GameItem.catalog.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
            }

            ItemTabBar(selection: $tab) { tab in
                let items = GameItem.catalog.filter { tab.matches($0) }
                let owned = items.filter { engine.collected.contains($0.id) }.count
                return "\(owned)/\(items.count)"
            }

            HStack(spacing: 6) {
                Text(tab.groupLabel == tab.label ? tab.label : "\(tab.groupLabel) · \(tab.label)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                // 该分类的品质分布
                ForEach(ItemTier.allCases, id: \.rawValue) { tier in
                    let count = GameItem.catalog.filter { tab.matches($0) && $0.tier == tier }.count
                    if count > 0 {
                        Text("\(tier == .demon ? "😈" : tier.label)\(count)")
                            .font(.system(size: 9))
                            .foregroundStyle(tier.color)
                    }
                }
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(GameItem.catalog.filter { tab.matches($0) }.sorted { $0.tier < $1.tier }) { item in
                        cell(item)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 490, height: 540)
        .sheet(item: $detail) { item in
            ItemDetailSheet(item: item,
                            owned: engine.inventory.first { $0.id == item.id },
                            heroContext: engine.hero)
        }
    }

    private func cell(_ item: GameItem) -> some View {
        let unlocked = engine.collected.contains(item.id)
        // 魔器未揭示：非魔修且未拥有时以 ? 示人（获得后/魔修可见真容）
        let demonHidden = item.tier == .demon && engine.hero != .demon && !engine.collected.contains(item.id)
        return Button {
            if unlocked, !demonHidden { detail = item }
        } label: {
            VStack(spacing: 5) {
                Group {
                    if item.tier == .demon, demonHidden {
                        Text("?").font(.title3.bold())          // 魔器未揭示：紫色 ? 剪影
                    } else {
                        Image(systemName: unlocked ? item.icon : "questionmark")
                            .font(.title3)
                    }
                }
                .frame(width: 40, height: 40)
                .foregroundStyle(unlocked && !demonHidden ? item.tier.color : Color.purple)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(unlocked && !demonHidden ? item.tier.color.opacity(0.14) : (item.tier == .demon ? Color.purple.opacity(0.1) : Color.secondary.opacity(0.1)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(unlocked && !demonHidden && item.tier >= .rare ? item.tier.color.opacity(0.7) : .clear,
                                          lineWidth: 1)
                    )
                Text(unlocked && !demonHidden ? item.name : "？？？")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(demonHidden ? Color.purple : .primary)
                TierTag(tier: item.tier).opacity(unlocked && !demonHidden ? 1 : 0.35)
            }
            .padding(7)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(demonHidden ? "？？？" : (unlocked ? "点击查看详情" : "尚未收集"))
    }
}
