import Foundation

/// 艾宾浩斯遗忘曲线阶梯调度器
///
/// 复习时间点取经典遗忘曲线节点：
///   30 分钟 → 12 小时 → 1 天 → 2 天 → 4 天 → 7 天 → 15 天 → 30 天，之后每次 ×2
///
/// `repetition` 记录当前处于阶梯的第几级（连续记住的次数）：
/// - 忘记：回到阶梯起点，5 分钟后重现（当天再考）
/// - 模糊：停留在当前级，按当前间隔再复习一次
/// - 记得：进入下一级
/// - 太简单：跳过一级
///
/// 走完整条阶梯（含 30 天节点）后判定为**已掌握**：进入超长间隔（180 天），
/// 到期后才会再次出现防止遗忘；期间若忘记则重新回到阶梯起点。
///
/// 30 分钟 / 12 小时这类"当天内"的节点由无感复习弹卡承接，用户不需要主动打开 App。
public struct EbbinghausScheduler: SRSScheduler {
    /// 遗忘曲线复习节点（秒）
    public static let steps: [TimeInterval] = [
        30 * 60,        // 30 分钟
        12 * 3600,      // 12 小时
        1 * 86_400,     // 1 天
        2 * 86_400,     // 2 天
        4 * 86_400,     // 4 天
        7 * 86_400,     // 7 天
        15 * 86_400,    // 15 天
        30 * 86_400     // 30 天
    ]

    /// 忘记后的重现间隔（默认 5 分钟）
    public var relearnInterval: TimeInterval = 5 * 60

    /// 已掌握后的超长间隔（180 天），到期后再出现防止遗忘
    public static let masteredInterval: TimeInterval = 180 * 86_400

    public init() {}

    /// 第 step 级对应的间隔；超出阶梯后按 ×2 递增
    public static func interval(at step: Int) -> TimeInterval {
        let index = max(0, step)
        if index < steps.count { return steps[index] }
        return steps[steps.count - 1] * pow(2, Double(index - steps.count + 1))
    }

    public func review(card: StudyCard, rating: Rating, now: Date) -> StudyCard {
        var next = card
        next.reviewCount += 1
        next.modifiedAt = now

        if rating == .again {
            next.repetition = 0
            next.lapseCount += 1
            next.state = .learning
            next.intervalDays = 0
            next.dueAt = now.addingTimeInterval(relearnInterval)
            return next
        }

        let targetStep: Int
        switch rating {
        case .hard:
            // 停留在当前级：重复刚完成的间隔
            targetStep = max(0, card.repetition - 1)
        case .good:
            targetStep = card.repetition
            next.repetition += 1
        case .easy:
            targetStep = card.repetition + 1
            next.repetition += 2
        case .again:
            fatalError("已在上方处理")
        }

        let interval: TimeInterval
        if card.state == .mastered || targetStep >= Self.steps.count {
            // 已掌握 / 走完整条阶梯：超长间隔后再出现
            interval = Self.masteredInterval
            next.state = .mastered
        } else {
            interval = Self.steps[targetStep]
            next.state = interval < 86_400 ? .learning : .review
        }

        next.intervalDays = interval / 86_400
        next.dueAt = now.addingTimeInterval(interval)
        return next
    }
}
