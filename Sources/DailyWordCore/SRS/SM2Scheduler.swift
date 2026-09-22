import Foundation

/// 自评等级：对应界面上的四个按键 1-4
public enum Rating: Int, CaseIterable {
    case again = 1   // 忘记
    case hard = 2    // 模糊
    case good = 3    // 记得
    case easy = 4    // 太简单

    /// 映射到 SM-2 的 quality (0-5)
    public var quality: Double {
        switch self {
        case .again: return 2
        case .hard: return 3
        case .good: return 4
        case .easy: return 5
        }
    }
}

/// 间隔重复调度器协议：MVP 用 SM-2，后续可替换为 FSRS
public protocol SRSScheduler {
    func review(card: StudyCard, rating: Rating, now: Date) -> StudyCard
}

/// 经典 SM-2 算法实现
/// - 忘记：repetition 归零，10 分钟后重新出现（当天再考）
/// - 成功：间隔按 1 天 → 6 天 → 上次间隔 × EF 递增；"太简单"额外 ×1.3
public struct SM2Scheduler: SRSScheduler {
    /// 忘记后的重学间隔（默认 10 分钟）
    public var relearnInterval: TimeInterval = 10 * 60
    /// EF 因子下限
    public static let minEasiness = 2.5 - 1.2 // 1.3

    public init() {}

    public func review(card: StudyCard, rating: Rating, now: Date) -> StudyCard {
        var next = card
        next.reviewCount += 1
        next.modifiedAt = now

        // EF 更新（SM-2 公式），所有评分都会影响难度因子
        let q = rating.quality
        let newEF = card.easiness + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        next.easiness = max(Self.minEasiness, newEF)

        if rating == .again {
            next.repetition = 0
            next.lapseCount += 1
            next.state = .learning
            next.intervalDays = 0
            next.dueAt = now.addingTimeInterval(relearnInterval)
            return next
        }

        // 成功回忆：计算下一个间隔（天）
        let interval: Double
        switch next.repetition {
        case 0:
            interval = rating == .easy ? 3 : 1
        case 1:
            interval = 6
        default:
            var days = (card.intervalDays * next.easiness).rounded()
            if rating == .easy { days = (days * 1.3).rounded() }
            interval = max(days, card.intervalDays + 1)
        }

        next.repetition += 1
        next.intervalDays = interval
        next.state = .review
        next.dueAt = now.addingTimeInterval(interval * 86_400)
        return next
    }
}
