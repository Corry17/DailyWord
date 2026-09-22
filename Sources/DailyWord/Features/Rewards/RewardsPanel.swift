import SwiftUI
import DailyWordCore

/// 自我激励记录（用户自己上传的成绩，如考试分数）
struct SelfRecord: Identifiable, Codable {
    var id = UUID()
    var title: String
    var score: String
    var date: String
}

/// 我的目标（当天或未来的日期）
struct SelfGoal: Identifiable, Codable {
    var id = UUID()
    var title: String
    var date: String   // yyyy.MM.dd
}

/// 奖励面板：等级进度、连续打卡、成就（逐级进阶 + 总览）、我的目标、自我激励
struct RewardsPanel: View {
    let summary: RewardSummary

    @State private var records: [SelfRecord] = []
    @State private var newTitle = ""
    @State private var newScore = ""
    @State private var newDate = ""
    @State private var showAddRecord = false
    @State private var dateError: String?
    @State private var showOverview = false
    @State private var editingRecord: SelfRecord?
    @State private var editTitle = ""
    @State private var editScore = ""
    @State private var editDate = ""

    // 我的目标
    @State private var goals: [SelfGoal] = []
    @State private var newGoalTitle = ""
    @State private var newGoalDate = ""
    @State private var goalError: String?
    @State private var showAddGoal = false
    @State private var editingGoal: SelfGoal?
    @State private var editGoalTitle = ""
    @State private var editGoalDate = ""

    private let recordsKey = "selfMileStones"

    /// 日期输入示例：明天（提示用户填当天或未来日期）
    private var tomorrowExample: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return f.string(from: tomorrow)
    }
    private let goalsKey = "selfGoals"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 等级
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Lv\(summary.level) · \(summary.title)")
                            .font(.headline)
                        Spacer()
                        Text("\(summary.xp) XP")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: summary.levelProgress)
                    Text("再获得 \(max(0, summary.xpForNextLevel - summary.xpInLevel)) XP 升到 Lv\(summary.level + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // 关键数据
                HStack(spacing: 14) {
                    statBlock(icon: "flame.fill", tint: .red,
                              value: "\(summary.streakDays)", label: "连续天数")
                    statBlock(icon: "trophy.fill", tint: .orange,
                              value: "\(summary.bestStreak)", label: "最长连击")
                    statBlock(icon: "bolt.fill", tint: .yellow,
                              value: "\(summary.todayXP)", label: "今日 XP")
                    statBlock(icon: "star.fill", tint: .green,
                              value: "\(summary.masteredCount)", label: "已掌握")
                }

                Divider()

                // 成就（只显示各类型最近目标，按最容易达成排序；已解锁奖杯在总览中展示）
                let inProgress = nextPerType(summary.achievements)   // 每个类型取未完成中等级最低的一个
                HStack {
                    Text("成就 🚩")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(summary.achievements.filter(\.unlocked).count)/\(summary.achievements.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                if inProgress.isEmpty {
                    Text("所有成就都已完成，太厉害了！")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    // 进行中成就可独立滑动（内容超长时滚动查看）
                    ScrollView {
                        VStack(spacing: 6) {
                            // 进行中：每个类型取未完成中等级最低的一个，最容易达成的排最前
                            ForEach(inProgress) { achievement in
                                progressRow(achievement)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                // 成就总览（已解锁奖杯墙，含获得时间）
                Button {
                    showOverview.toggle()
                } label: {
                    HStack {
                        Image(systemName: "trophy.fill")
                        Text(showOverview ? "收起成就总览 · 奖杯墙" : "成就总览 · 奖杯墙")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showOverview ? 180 : 0))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showOverview {
                    let overviewRows = groupRows(summary.achievements)
                    if overviewRows.isEmpty {
                        Text("还没有完成成就哦，努力学习吧！")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 6)
                    } else {
                        // 成就总览可独立滑动（内容超长时滚动查看）
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(overviewRows) { row in
                                    overviewRow(row)
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                }

                Divider()

                // 我的目标
                HStack {
                    Text("我的目标")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button {
                        showAddGoal.toggle()
                    } label: {
                        Label("添加目标", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                if showAddGoal {
                    HStack(spacing: 6) {
                        TextField("目标名", text: $newGoalTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        TextField("日期，如 \(tomorrowExample)", text: $newGoalDate)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 130)
                        Button("保存") { addGoal() }
                            .controlSize(.small)
                            .disabled(newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("取消") { showAddGoal = false }
                            .controlSize(.small)
                    }
                    if let goalError {
                        Text(goalError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                if goals.isEmpty {
                    Text("还没有目标，立一个当天或未来的目标，朝着它努力！")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(goals) { goal in
                                goalRow(goal)
                            }
                        }
                    }
                    .frame(maxHeight: 110)
                }

                Divider()

                // 自我激励：上传成绩
                HStack {
                    Text("自我激励")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button {
                        showAddRecord.toggle()
                    } label: {
                        Label("上传成绩", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                if showAddRecord {
                    HStack(spacing: 6) {
                        TextField("考试/名称", text: $newTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        TextField("分数", text: $newScore)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 70)
                        Button("保存") { addRecord() }
                            .controlSize(.small)
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("取消") { showAddRecord = false }
                            .controlSize(.small)
                    }
                    TextField("获得时间 yyyy.MM.dd（留空为当天）", text: $newDate)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    if let dateError {
                        Text(dateError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }

                if records.isEmpty {
                    Text("还没有成绩记录，上传考试/目标成绩，一次次激励自己！")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(records) { record in
                                recordRow(record)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }

                Text("获得经验：新学 +3 · 记得 +2 · 模糊 +1 · 掌握 +10 · 解锁成就 +30~500")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(width: 300)
            .onAppear {
                loadRecords()
                loadGoals()
            }
            .sheet(item: $editingRecord) { record in
                VStack(alignment: .leading, spacing: 10) {
                    Text("编辑成绩")
                        .font(.headline)
                    TextField("考试/名称", text: $editTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("分数", text: $editScore)
                        .textFieldStyle(.roundedBorder)
                    TextField("获得时间 yyyy.MM.dd", text: $editDate)
                        .textFieldStyle(.roundedBorder)
                    if let dateError {
                        Text(dateError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button("取消") { editingRecord = nil }
                            .keyboardShortcut(.cancelAction)
                        Button("保存") {
                            saveEdit(record)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(16)
                .frame(width: 280)
            }
            .sheet(item: $editingGoal) { goal in
                VStack(alignment: .leading, spacing: 10) {
                    Text("编辑目标")
                        .font(.headline)
                    TextField("目标名", text: $editGoalTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("日期，如 \(tomorrowExample)", text: $editGoalDate)
                        .textFieldStyle(.roundedBorder)
                    if let goalError {
                        Text(goalError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button("取消") { editingGoal = nil }
                            .keyboardShortcut(.cancelAction)
                        Button("保存") {
                            saveEditGoal(goal)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(editGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(16)
                .frame(width: 280)
            }
        }
    }

    // MARK: - 进行中成就行（最近完成在前）

    /// 每个类型取「未完成中等级最低」的一个成就，按最容易达成（进度比例）降序排列
    private func nextPerType(_ all: [Achievement]) -> [Achievement] {
        let groups: [(String, [String])] = [
            ("学习量", ["first", "hundred", "fivehundred", "thousand", "twothousand", "fivethousand", "tenthousand"]),
            ("掌握量", ["mastered50", "mastered200", "mastered500"]),
            ("毕业量", ["graduate10", "graduate50", "graduate200", "graduate500"]),
            ("等级", ["level10", "level25", "level50", "level100"]),
            ("打卡", ["streak3", "streak7", "streak30", "streak100"]),
            ("单日", ["today50", "today100"]),
        ]
        var result: [Achievement] = []
        for (_, ids) in groups {
            let groupItems = all.filter { ids.contains($0.id) }
            // 未完成中 goal 最小 = 等级最低
            if let next = groupItems.filter({ !$0.unlocked }).min(by: { $0.goal < $1.goal }) {
                result.append(next)
            }
        }
        // 最容易达成排序：进度比例降序
        return result.sorted { $0.ratio > $1.ratio }
    }

    private func progressRow(_ achievement: Achievement) -> some View {
        let mystery = achievement.isMystery
        return HStack(spacing: 8) {
            Image(systemName: mystery ? "questionmark.circle.fill" : "flag.fill")
                .font(.caption)
                .foregroundStyle(mystery ? Color.purple : .blue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(achievement.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(mystery ? Color.purple : .primary)
                    Spacer()
                    Text(mystery ? "？？？" : "\(achievement.progress)/\(achievement.goal)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: achievement.ratio)
                    .tint(mystery ? .purple : .blue)
                Text(mystery ? "神秘成就 · 达成后揭晓" : "\(achievement.detail) · 达成 +\(achievement.xpReward) XP")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - 成就总览行（一类型一奖杯 + 爬楼阶梯）
    
    /// 单个档位：成就名 + 解锁日期（nil = 未达成）
    private struct AchievementStep: Identifiable {
        let id: String
        let title: String
        let unlockedDate: String?
    }
    
    /// 总览行：类型 + 从低到高的全部档位
    private struct AchievementGroupRow: Identifiable {
        let id: String                  // 类型名
        let steps: [AchievementStep]    // 低 → 高
    }
    
    /// 每个类型一行（仅显示有达成成就的类型）；每阶保留成就名与解锁时间
    private func groupRows(_ all: [Achievement]) -> [AchievementGroupRow] {
        let groups: [(String, [String])] = [
            ("学习量", ["first", "hundred", "fivehundred", "thousand", "twothousand", "fivethousand", "tenthousand"]),
            ("掌握量", ["mastered50", "mastered200", "mastered500"]),
            ("毕业量", ["graduate10", "graduate50", "graduate200", "graduate500"]),
            ("等级", ["level10", "level25", "level50", "level100"]),
            ("打卡", ["streak3", "streak7", "streak30", "streak100"]),
            ("单日", ["today50", "today100"]),
        ]
        let allAch = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var rows: [AchievementGroupRow] = []
        for (name, ids) in groups {
            let unlockedIds = Set(all.filter(\.unlocked).map(\.id))
            // 至少一档达成才展示该类型
            guard ids.contains(where: { unlockedIds.contains($0) }) else { continue }
            let steps = ids.map { id in
                AchievementStep(id: id,
                                title: allAch[id]?.title ?? id,
                                unlockedDate: allAch[id]?.unlockedDate)
            }
            rows.append(AchievementGroupRow(id: name, steps: steps))
        }
        return rows
    }
    
    private func overviewRow(_ row: AchievementGroupRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.caption)
                .foregroundStyle(Color.yellow)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.id)
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                // 从下往上爬：顶部是最高级，底部是最低级；级别越高向右缩进越大
                ForEach(Array(row.steps.enumerated().reversed()), id: \.element.id) { index, step in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(step.unlockedDate != nil ? Color.orange : Color.gray.opacity(0.35))
                            .frame(width: 18, height: 6)
                        Text(step.title)
                            .font(.caption2)
                            .foregroundStyle(step.unlockedDate != nil ? Color.primary : Color.gray.opacity(0.45))
                        if let date = step.unlockedDate {
                            Text(date)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.orange.opacity(0.9))
                        } else {
                            Text("未达成")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.leading, CGFloat(row.steps.count - 1 - index) * 10)
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func daysBetween(_ start: String?, _ end: String) -> Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        guard let s = start.flatMap({ fmt.date(from: $0) }),
              let e = fmt.date(from: end) else { return 0 }
        return max(1, Int(e.timeIntervalSince(s) / 86400))
    }

    private func statBlock(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.callout.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 我的目标

    private func goalRow(_ goal: SelfGoal) -> some View {
        HStack {
            Image(systemName: "flag.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(goal.title)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(goalDateLabel(goal.date))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(goalRemainingDays(goal.date) < 0 ? .red : .secondary)
            Menu {
                Button("编辑") {
                    editGoalTitle = goal.title
                    editGoalDate = goal.date
                    editingGoal = goal
                }
                Button("删除", role: .destructive) { deleteGoal(goal) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.vertical, 2)
    }

    /// 目标日期文案：今天 / 还有 X 天 / 已过期
    private func goalDateLabel(_ dateText: String) -> String {
        let days = goalRemainingDays(dateText)
        if days == 0 { return "今天" }
        if days < 0 { return "已过期" }
        return "还有 \(days) 天"
    }

    private func goalRemainingDays(_ dateText: String) -> Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        guard let date = fmt.date(from: dateText) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        return Int(date.timeIntervalSince(start) / 86400)
    }

    private func loadGoals() {
        if let data = UserDefaults.standard.data(forKey: goalsKey),
           let decoded = try? JSONDecoder().decode([SelfGoal].self, from: data) {
            goals = decoded.sorted { goalRemainingDays($0.date) < goalRemainingDays($1.date) }
        }
    }

    private func persistGoals() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: goalsKey)
        }
    }

    /// 目标日期校验：必须真实有效且为当天或未来
    private func isValidGoalDate(_ text: String) -> Bool {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        guard let date = fmt.date(from: text) else { return false }
        return date >= Calendar.current.startOfDay(for: Date())
    }

    private func addGoal() {
        let title = newGoalTitle.trimmingCharacters(in: .whitespaces)
        let date = newGoalDate.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        guard isValidGoalDate(date) else {
            goalError = "日期无效：需为真实日期且是当天或未来（yyyy.MM.dd）"
            return
        }
        goals.append(SelfGoal(title: title, date: date))
        goals.sort { goalRemainingDays($0.date) < goalRemainingDays($1.date) }
        persistGoals()
        newGoalTitle = ""
        newGoalDate = ""
        goalError = nil
        showAddGoal = false
    }

    private func saveEditGoal(_ goal: SelfGoal) {
        let title = editGoalTitle.trimmingCharacters(in: .whitespaces)
        let date = editGoalDate.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        guard isValidGoalDate(date) else {
            goalError = "日期无效：需为真实日期且是当天或未来（yyyy.MM.dd）"
            return
        }
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx].title = title
            goals[idx].date = date
            goals.sort { goalRemainingDays($0.date) < goalRemainingDays($1.date) }
            persistGoals()
        }
        editingGoal = nil
        goalError = nil
    }

    private func deleteGoal(_ goal: SelfGoal) {
        goals.removeAll { $0.id == goal.id }
        persistGoals()
    }

    // MARK: - 自我激励记录

    private func recordRow(_ record: SelfRecord) -> some View {
        HStack {
            Image(systemName: "medal.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text(record.title)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(record.score)
                .font(.caption.bold().monospacedDigit())
            Text(record.date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Menu {
                Button("编辑") {
                    editTitle = record.title
                    editScore = record.score
                    editDate = record.date
                    editingRecord = record
                }
                Button("删除", role: .destructive) { deleteRecord(record) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
        .padding(.vertical, 2)
    }

    private func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([SelfRecord].self, from: data) {
            records = decoded
        }
    }

    private func persistRecords() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    /// 成绩日期校验：真实有效且不能超过当天
    private func isValidRecordDate(_ text: String) -> Bool {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy.MM.dd"
        guard let date = fmt.date(from: text) else { return false }
        return date <= Calendar.current.startOfDay(for: Date())
    }

    private func addRecord() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let dateText = newDate.trimmingCharacters(in: .whitespaces)
        if !dateText.isEmpty && !isValidRecordDate(dateText) {
            dateError = "日期无效：需为真实日期且不能超过当天（yyyy.MM.dd）"
            return
        }
        let date: String
        if dateText.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy.MM.dd"
            date = formatter.string(from: Date())
        } else {
            date = dateText
        }
        records.insert(SelfRecord(title: title, score: newScore, date: date), at: 0)
        persistRecords()
        newTitle = ""
        newScore = ""
        newDate = ""
        dateError = nil
        showAddRecord = false
    }

    private func saveEdit(_ record: SelfRecord) {
        let title = editTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let dateText = editDate.trimmingCharacters(in: .whitespaces)
        if !dateText.isEmpty && !isValidRecordDate(dateText) {
            dateError = "日期无效：需为真实日期且不能超过当天（yyyy.MM.dd）"
            return
        }
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx].title = title
            records[idx].score = editScore
            if !dateText.isEmpty {
                records[idx].date = dateText
            }
            persistRecords()
        }
        editingRecord = nil
        dateError = nil
    }

    private func deleteRecord(_ record: SelfRecord) {
        records.removeAll { $0.id == record.id }
        persistRecords()
    }
}
