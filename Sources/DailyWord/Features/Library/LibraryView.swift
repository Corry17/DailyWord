import SwiftUI
import DailyWordCore

/// 词库浏览页：查看每个词的熟悉程度和下次出现时间
struct LibraryView: View {
    let database: AppDatabase

    @ObservedObject private var settings = AppSettings.shared
    @State private var loadedItems: [StudyItem] = []
    @State private var stats: (total: Int, learned: Int, mastered: Int) = (0, 0, 0)
    @State private var searchText = ""
    @State private var filter: Filter = .all
    @State private var showAppearance = false
    @State private var page = 0
    @State private var hasMore = true
    @State private var detailItem: StudyItem?
    private let pageSize = 400

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case new = "未学"
        case learning = "学习中"
        case review = "复习中"
        case mastered = "已掌握"
        case suspended = "已毕业"
        var id: String { rawValue }

        func matches(_ item: StudyItem) -> Bool {
            switch self {
            case .all: return true
            case .new: return item.card == nil
            case .learning: return item.card?.state == .learning
            case .review: return item.card?.state == .review
            case .mastered: return item.card?.state == .mastered
            case .suspended: return item.card?.state == .suspended
            }
        }
    }

    private var filteredItems: [StudyItem] {
        loadedItems.filter { item in
            guard filter.matches(item) else { return false }
            guard !searchText.isEmpty else { return true }
            let query = searchText.lowercased()
            return item.word.headword.lowercased().contains(query)
                || item.word.definitionCn.contains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：统计 + 筛选 + 搜索
            VStack(alignment: .leading, spacing: 10) {
                summaryBar
                HStack(spacing: 10) {
                    Picker("", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    TextField("搜索单词或释义", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
            }
            .padding(12)

            Divider()

            // 列表（LazyVStack 懒渲染 + 滚动到底部分页加载，避免上万行卡死）
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems) { item in
                        LibraryRow(item: item) { newState in
                            adjust(item, to: newState)
                        }
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            detailItem = item
                        })
                        .onAppear {
                            // 滚动到最后一行时自动加载下一页；筛选后无新匹配时最后一行不变，不会重复触发
                            if item.id == filteredItems.last?.id { loadMore() }
                        }
                        Divider().padding(.leading, 10)
                    }
                    if filteredItems.isEmpty {
                        // 当前筛选/搜索无匹配词
                        Text("无")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .collectionDidChange)) { _ in
            reload()
        }
        .onChange(of: detailItem) { item in
            // 双击词条：独立窗口弹详情（比 sheet 稳定）
            if let item {
                AppServices.shared.showWordDetail(item)
                detailItem = nil
            }
        }
    }

    private var summaryBar: some View {
        return HStack(spacing: 14) {
            Label("词库 \(stats.total)", systemImage: "books.vertical")
            Label("已学 \(stats.learned)", systemImage: "checkmark.circle")
            Label("已掌握 \(stats.mastered)", systemImage: "star.circle")
            Spacer()
            Button {
                showAppearance.toggle()
            } label: {
                Image(systemName: "textformat.size")
            }
            .buttonStyle(.plain)
            .help("显示设置：单词字号与颜色")
            .popover(isPresented: $showAppearance, arrowEdge: .bottom) {
                appearancePanel
            }
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("刷新")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// 显示设置：单词字号/颜色（仅作用于词库列表，独立于学习面板）
    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("单词显示")
                .font(.headline)
            HStack {
                Text("字号 \(Int(settings.libraryFontSize))")
                    .font(.callout)
                    .frame(width: 56, alignment: .leading)
                Slider(value: $settings.libraryFontSize, in: 14...44, step: 2)
            }
            HStack {
                ColorPicker("颜色", selection: Binding(
                    get: { settings.libraryWordColor ?? Color(nsColor: .labelColor) },
                    set: { settings.libraryWordColor = $0 }
                ))
                Spacer()
                Button("恢复默认") { settings.libraryWordColor = nil }
                    .controlSize(.small)
            }
            Divider()
            Text("释义显示")
                .font(.headline)
            HStack {
                ColorPicker("释义颜色", selection: Binding(
                    get: { settings.libraryDefinitionColor ?? Color(nsColor: .secondaryLabelColor) },
                    set: { settings.libraryDefinitionColor = $0 }
                ))
                Spacer()
                Button("恢复默认") { settings.libraryDefinitionColor = nil }
                    .controlSize(.small)
            }
            Divider()
            // 实时预览
            VStack(alignment: .leading, spacing: 4) {
                Text("example")
                    .font(.system(size: min(settings.libraryFontSize, 40), weight: .bold, design: .rounded))
                    .foregroundStyle(settings.libraryWordColor ?? Color.primary)
                Text("n. 例子，范例；榜样")
                    .font(.system(size: max(min(settings.libraryFontSize * 0.5, 18), 12)))
                    .foregroundStyle(settings.libraryDefinitionColor ?? Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("仅作用于词库列表，不影响学习面板")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 260)
    }

    private func reload() {
        page = 0
        loadedItems = []
        hasMore = true
        let key = AppSettings.shared.currentCollectionKey
        stats = (try? database.collectionStats(collectionKey: key)) ?? (0, 0, 0)
        loadMore()
    }

    /// 分页加载下一页
    private func loadMore() {
        guard hasMore else { return }
        let key = AppSettings.shared.currentCollectionKey
        guard let batch = try? database.allItems(collectionKey: key,
                                                 limit: pageSize, offset: page * pageSize) else { return }
        loadedItems.append(contentsOf: batch)
        page += 1
        hasMore = batch.count >= pageSize
    }

    /// 调整学习状态并刷新
    private func adjust(_ item: StudyItem, to state: StudyCard.State?) {
        try? database.setCardState(wordId: item.word.id, to: state)
        AppServices.shared.ambient.refreshDueCount()
        reload()
    }
}

// MARK: - 行视图

private struct LibraryRow: View {
    let item: StudyItem
    let onAdjust: (StudyCard.State?) -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 词 + 释义（双击此处查看详情）
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.word.headword)
                        .font(.system(size: librarySize, weight: .semibold))
                        .foregroundStyle(settings.libraryWordColor ?? Color.primary)
                    if let phonetic = item.word.phonetic {
                        Text("/\(phonetic)/")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(item.word.definitionCn.replacingOccurrences(of: "\n", with: "；"))
                    .font(.caption)
                    .foregroundStyle(settings.libraryDefinitionColor ?? Color.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 熟悉度 + 下次出现时间
            VStack(alignment: .trailing, spacing: 3) {
                familiarityBadge
                Text(nextDueText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // 熟悉度进度条（阶梯 0-8 级）
            ProgressView(value: familiarityProgress)
                .progressViewStyle(.linear)
                .frame(width: 56)
                .tint(familiarityColor)

            // 学习状态调整
            Menu {
                stateMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("调整学习状态")
        }
        .padding(.vertical, 2)
        // 不挂 contextMenu：macOS 上会拦截鼠标事件导致双击手势失效（状态调整已用行内 Menu）
    }

    /// 词库列表用字号：跟随题库设置按比例缩放，限制在列表可读范围
    private var librarySize: Double {
        min(max(13, settings.libraryFontSize * 0.5), 26)
    }

    @ViewBuilder
    private var stateMenuItems: some View {
        Button("重置为未学") { onAdjust(nil) }
        Button("重新开始学习（立即到期）") { onAdjust(.learning) }
        Button("标记为已掌握（180 天后再出现）") { onAdjust(.mastered) }
        Divider()
        if item.card?.state == .suspended {
            Button("恢复学习（取消毕业）") { onAdjust(.learning) }
        } else {
            Button("毕业（不再出现）", role: .destructive) { onAdjust(.suspended) }
        }
    }

    private var familiarityProgress: Double {
        guard let card = item.card else { return 0 }
        if card.state == .mastered { return 1 }
        return min(1, Double(card.repetition) / Double(EbbinghausScheduler.steps.count))
    }

    private var familiarityColor: Color {
        guard let card = item.card else { return .gray }
        switch card.state {
        case .learning: return .orange
        case .review: return .blue
        case .mastered: return .green
        case .suspended: return .gray
        }
    }

    private var familiarityBadge: some View {
        let (label, color): (String, Color) = {
            guard let card = item.card else { return ("未学", .gray) }
            switch card.state {
            case .learning: return ("学习中", .orange)
            case .review: return ("复习中 \(card.repetition)/\(EbbinghausScheduler.steps.count)", .blue)
            case .mastered: return ("已掌握", .green)
            case .suspended: return ("已毕业", .gray)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var nextDueText: String {
        guard let card = item.card else { return "—" }
        if card.state == .suspended { return "不再出现" }
        let now = Date()
        if card.dueAt <= now { return "已到期，随时出现" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return "下次出现：\(formatter.localizedString(for: card.dueAt, relativeTo: now))"
    }
}
