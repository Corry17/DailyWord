import SwiftUI

// MARK: - 横向分类选项卡

/// 背包/图鉴公用的横向分类
enum ItemTab: String, CaseIterable, Identifiable {
    case hat, clothes, jewelry, pants, shoes, weapon, pet, sprite, potion

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hat: return "帽子"
        case .clothes: return "衣服"
        case .jewelry: return "首饰"
        case .pants: return "裤子"
        case .shoes: return "鞋子"
        case .weapon: return "武器"
        case .pet: return "宠物"
        case .sprite: return "精灵"
        case .potion: return "药水"
        }
    }

    var icon: String {
        switch self {
        case .hat: return "crown"
        case .clothes: return "tshirt.fill"
        case .jewelry: return "diamond.fill"
        case .pants: return "rectangle.split.2x1"
        case .shoes: return "shoeprints.fill"
        case .weapon: return "bolt.horizontal.fill"
        case .pet: return "pawprint.fill"
        case .sprite: return "sparkles"
        case .potion: return "pills.fill"
        }
    }

    /// 所属大类标题（穿戴五部位归到“穿戴”）
    var groupLabel: String {
        switch self {
        case .hat, .clothes, .jewelry, .pants, .shoes: return "穿戴"
        case .weapon: return "武器"
        case .pet: return "宠物"
        case .sprite: return "精灵"
        case .potion: return "药水"
        }
    }

    func matches(_ item: GameItem) -> Bool {
        switch self {
        case .hat: return item.category == .wear(.hat)
        case .clothes: return item.category == .wear(.clothes)
        case .jewelry: return item.category == .wear(.jewelry)
        case .pants: return item.category == .wear(.pants)
        case .shoes: return item.category == .wear(.shoes)
        case .weapon: return item.category == .weapon
        case .pet: return item.category == .pet
        case .sprite: return item.category == .sprite
        case .potion: return item.category == .potion
        }
    }
}

/// 横向可滚动的分类选项卡
struct ItemTabBar: View {
    @Binding var selection: ItemTab
    /// 每个分类的计数文本（如 "3/14" 或 "3"）
    let badge: (ItemTab) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ItemTab.allCases) { tab in
                    let active = tab == selection
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.label)
                                .font(.caption2.weight(active ? .bold : .regular))
                            Text(badge(tab))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 48)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(active ? Color.accentColor : .clear, lineWidth: 1)
                        )
                        .foregroundStyle(active ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - 品质标签

struct TierTag: View {
    let tier: ItemTier
    var body: some View {
        Text(tier == .demon ? "😈" : tier.label)
            .font(.caption2.weight(tier >= .rare ? .bold : .regular))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tier.color.opacity(tier >= .legendary ? 0.28 : 0.15)))
            .foregroundStyle(tier.color)
    }
}

// MARK: - 商品行

struct ItemRow: View {
    let item: GameItem
    let price: Int
    let canBuy: Bool
    let onBuy: () -> Void
    var heroContext: HeroClass? = nil
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showDetail = true
            } label: {
                HStack(spacing: 10) {
                    ItemIcon(item: item, revealed: demonRevealed)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(demonRevealed ? item.name : "???").font(.subheadline.bold())
                            TierTag(tier: item.tier)
                            Text(categoryLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let restricted = item.restrictedTo {
                                Text("\(restricted.name)专属")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                        Text("\(demonRevealed ? item.effectDesc : "???")\(item.maxDurability < 99 && item.category != .potion ? " · \(stateLabel(for: item)) \(item.maxDurability)" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .help("点击查看详情")

            Button(action: onBuy) {
                Label("\(price)", systemImage: "circle.hexagongrid.circle.fill")
            }
            .disabled(!canBuy)
        }
        .padding(9)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showDetail) {
            ItemDetailSheet(item: item, owned: nil, heroContext: heroContext)
        }
    }

    /// 魔器揭示：仅魔修身份可见真实内容
    private var demonRevealed: Bool {
        item.tier != .demon || heroContext == .demon
    }

    private var categoryLabel: String {
        if case .wear(let slot) = item.category { return slot.label }
        return item.category.bigLabel
    }

    private func stateLabel(for item: GameItem) -> String {
        switch item.category {
        case .pet: return "饱食度"
        case .sprite: return "灵力"
        default: return "耐久"
        }
    }
}

struct ItemIcon: View {
    let item: GameItem
    var size: CGFloat = 34
    /// 魔器是否揭示真容（魔修/已拥有）；false 时以 ? 示人
    var revealed: Bool = true

    var body: some View {
        Group {
            if item.tier == .demon {
                if revealed {
                    Image(systemName: item.icon)
                        .font(.system(size: size * 0.5))
                } else {
                    // 魔器未揭示：以 ? 示人（神秘）
                    Text("?")
                        .font(.system(size: size * 0.5, weight: .bold))
                }
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(item.tier.color)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24)
                    .fill(item.tier.color.opacity(item.tier >= .legendary ? 0.22 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24)
                    .strokeBorder(item.tier.color.opacity(item.tier >= .rare ? 0.7 : 0), lineWidth: 1)
            )
    }
}

// MARK: - 神秘商人（局内 · 八折）

struct ShopInline: View {
    @ObservedObject var engine: TowerGameEngine

    var body: some View {
        VStack(spacing: 14) {
            Text("🧙 神秘商人").font(.title2.bold())
            Text("「有缘人，山中相逢即是缘——八折，只此一次。」")
                .font(.callout)
                .foregroundStyle(.secondary)
            Label("\(engine.coins)", systemImage: "circle.hexagongrid.circle.fill")
                .foregroundStyle(.yellow)

            if engine.merchantOffers.isEmpty {
                Text("货已售罄").foregroundStyle(.secondary)
            }
            ForEach(engine.merchantOffers) { item in
                let price = Int(Double(item.price) * 0.8)
                ItemRow(item: item, price: price, canBuy: engine.coins >= price,
                        onBuy: { engine.buy(item, discounted: true) },
                        heroContext: engine.hero)
            }

            Button { engine.leaveMerchant() } label: {
                Text("道别，继续赶路").frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}

// MARK: - 云间商城（定时上新 + 金币刷新）

struct ShopSheet: View {
    @ObservedObject var engine: TowerGameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var secondsLeft = 0
    @State private var filter: ItemTab?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("☁️ 云间商城").font(.headline)
                Spacer()
                Label("\(engine.coins)", systemImage: "circle.hexagongrid.circle.fill")
                    .foregroundStyle(.yellow)
                Button("关闭") { dismiss() }
            }

            HStack(spacing: 8) {
                Label(secondsLeft > 0 ? "上新倒计时 \(secondsLeft / 60):\(String(format: "%02d", secondsLeft % 60))" : "即将上新",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    engine.paidRefreshShop()
                } label: {
                    Label("刷新 \(TowerGameEngine.shopManualCost)", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(engine.coins < TowerGameEngine.shopManualCost)
            }

            // 横向分类筛选（全部 / 各大类）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "全部", icon: "square.grid.2x2", active: filter == nil) { filter = nil }
                    ForEach(ItemTab.allCases) { tab in
                        let count = engine.shopOffers.filter { tab.matches($0) }.count
                        if count > 0 {
                            chip(label: "\(tab.label) \(count)", icon: tab.icon, active: filter == tab) {
                                filter = tab
                            }
                        }
                    }
                }
            }

            ScrollView {
                VStack(spacing: 8) {
                    let offers = filter.map { tab in engine.shopOffers.filter { tab.matches($0) } }
                        ?? engine.shopOffers
                    ForEach(offers) { item in
                        ItemRow(item: item, price: item.price, canBuy: engine.coins >= item.price,
                                onBuy: { engine.buy(item, discounted: false) },
                                heroContext: engine.hero)
                    }
                    if offers.isEmpty {
                        Text("这一类暂无货，刷新看看？")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            if let toast = engine.toast {
                Text(toast).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 470, height: 520)
        .onAppear {
            engine.refreshShopIfNeeded()
            secondsLeft = engine.shopSecondsLeft
        }
        .onReceive(ticker) { _ in
            secondsLeft = engine.shopSecondsLeft
            if secondsLeft == 0 { engine.refreshShopIfNeeded() }
        }
    }

    private func chip(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)))
                .foregroundStyle(active ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

