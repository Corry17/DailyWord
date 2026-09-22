import Foundation

/// 可独立测试的引导进度；令牌用于拒绝已退出、切步或重开前的延迟回调。
public struct OnboardingProgress {
    public enum Step: Int, CaseIterable, Hashable {
        case welcome, menubar, study, library, quiz, appearance
        case opacityDemo, movement, tripleClose, translation, rewards, game, complete
    }

    public enum Interaction {
        case studyRated, quizAnswered, opacityChanged, panelMoved, tripleClosed

        var step: Step {
            switch self {
            case .studyRated: return .study
            case .quizAnswered: return .quiz
            case .opacityChanged: return .opacityDemo
            case .panelMoved: return .movement
            case .tripleClosed: return .tripleClose
            }
        }
    }

    public private(set) var step: Step = .welcome
    public private(set) var isActive = false
    public private(set) var revision = UUID()
    public private(set) var completedInteractions: Set<Step> = []

    public init() {}

    public mutating func start() {
        step = .welcome
        isActive = true
        completedInteractions = []
        revision = UUID()
    }

    public mutating func stop() {
        isActive = false
        revision = UUID()
    }

    public func accepts(_ token: UUID) -> Bool {
        isActive && revision == token
    }

    @discardableResult
    public mutating func advance(ifCurrent token: UUID) -> Bool {
        guard accepts(token), let next = Step(rawValue: step.rawValue + 1) else { return false }
        step = next
        revision = UUID()
        return true
    }

    @discardableResult
    public mutating func back() -> Bool {
        guard isActive, let previous = Step(rawValue: step.rawValue - 1) else { return false }
        step = previous
        revision = UUID()
        return true
    }

    @discardableResult
    public mutating func record(_ interaction: Interaction) -> Bool {
        guard isActive, step == interaction.step else { return false }
        return completedInteractions.insert(step).inserted
    }
}

/// 引导演示只维护内存状态，不持有数据库、学习会话或用户设置。
public struct OnboardingDemoState {
    public static let word = "apple"
    public static let definition = "n. 苹果"
    public static let options = ["n. 书", "n. 苹果", "n. 水", "n. 花"]
    public static let correctOption = 1
    public private(set) var isRevealed = false
    public private(set) var rating: Int?
    public private(set) var quizCorrect: Bool?
    public var quizInput = ""
    public private(set) var opacity = 0.85

    public init() {}
    public mutating func flip() { isRevealed.toggle() }
    @discardableResult
    public mutating func rate(_ value: Int) -> Bool {
        guard isRevealed, (1...4).contains(value) else { return false }
        rating = value
        return true
    }
    @discardableResult
    public mutating func choose(_ index: Int) -> Bool {
        guard Self.options.indices.contains(index) else { return false }
        quizCorrect = index == Self.correctOption
        return quizCorrect == true
    }
    @discardableResult
    public mutating func submitSpelling() -> Bool {
        quizCorrect = quizInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == Self.word
        return quizCorrect == true
    }
    @discardableResult
    public mutating func adjustOpacity(_ delta: Double) -> Bool {
        let old = opacity
        opacity = min(1, max(0, opacity + delta))
        return old != opacity
    }
}

/// 通用窗口边界限制，支持负坐标副屏和大于可视区的窗口。
public enum WindowPlacement {
    public static func clampedFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        let width = min(max(1, frame.width), visibleFrame.width)
        let height = min(max(1, frame.height), visibleFrame.height)
        return CGRect(x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
                      width: width, height: height)
    }
}

/// 气泡按实际锚点所在屏幕定位；空间不足时不画误导箭头，退回屏内居中。
public struct OnboardingPlacement {
    public enum Arrow { case up, down, left, right, none }
    public let origin: CGPoint
    public let arrow: Arrow
    public let arrowOffset: CGFloat

    public static func resolve(anchor: CGRect?, visibleFrame: CGRect, size: CGSize,
                               preferBelow: Bool = false) -> OnboardingPlacement {
        let margin: CGFloat = 8
        let gap: CGFloat = 6
        let area = visibleFrame.insetBy(dx: margin, dy: margin)
        func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(lower, upper))
        }
        func clamped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: clamp(point.x, area.minX, area.maxX - size.width),
                    y: clamp(point.y, area.minY, area.maxY - size.height))
        }
        func centered() -> OnboardingPlacement {
            OnboardingPlacement(origin: clamped(CGPoint(x: area.midX - size.width / 2,
                                                        y: area.midY - size.height / 2)),
                                arrow: .none, arrowOffset: 0)
        }
        guard let anchor, !anchor.isEmpty else { return centered() }
        guard preferBelow || anchor.intersects(visibleFrame) else { return centered() }
        let directions: [Arrow] = preferBelow ? [.up, .down, .right, .left] : [.right, .left, .up, .down]
        for arrow in directions {
            var point: CGPoint
            switch arrow {
            case .right: point = CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
            case .left: point = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
            case .up:
                // 菜单栏锚点在可视区上方，向下贴边后仍保持箭头指向真实图标。
                point = CGPoint(x: anchor.midX - size.width / 2,
                                y: min(anchor.minY - gap - size.height, area.maxY - size.height))
            case .down:
                point = CGPoint(x: anchor.midX - size.width / 2, y: max(anchor.maxY + gap, area.minY))
            case .none: return centered()
            }
            if arrow == .left || arrow == .right {
                guard point.x >= area.minX, point.x + size.width <= area.maxX else { continue }
            } else {
                guard point.y >= area.minY, point.y + size.height <= area.maxY else { continue }
            }
            point = clamped(point)
            let horizontal = arrow == .up || arrow == .down
            let limit = max(0, (horizontal ? size.width : size.height) / 2 - 28)
            let offset = horizontal ? anchor.midX - point.x - size.width / 2
                : point.y + size.height / 2 - anchor.midY
            return OnboardingPlacement(origin: point, arrow: arrow,
                                       arrowOffset: clamp(offset, -limit, limit))
        }
        return centered()
    }
}
