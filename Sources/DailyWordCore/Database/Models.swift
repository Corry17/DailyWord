import Foundation
import GRDB

// MARK: - WordCollection 词库

public struct WordCollection: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "collection"

    public var id: Int64
    public var key: String
    public var name: String
    public var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, key, name
        case sortOrder = "sort_order"
    }
}

// MARK: - Word 词条（打包词库，只读）

public struct Word: Codable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "word"

    public var id: Int64
    public var headword: String
    public var phonetic: String?
    public var definitionCn: String
    public var definitionEn: String?
    public var pos: String?
    public var tags: String?
    public var frequency: Int?
    public var collins: Int?
    public var oxford: Int?
    public var exchange: String?

    enum CodingKeys: String, CodingKey {
        case id, headword, phonetic, pos, tags, frequency, collins, oxford, exchange
        case definitionCn = "definition_cn"
        case definitionEn = "definition_en"
    }
}

// MARK: - StudyCard 学习卡片（用户数据，参与同步）
// 约定：某个单词没有 StudyCard 记录 = 新词；首次自评时才创建卡片。

public struct StudyCard: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "study_card"

    public enum State: String, Codable {
        case learning   // 学习中（当天内会再次出现）
        case review     // 已进入间隔复习
        case mastered   // 已掌握（走完整条遗忘曲线阶梯，超长间隔后再出现）
        case suspended  // 已斩词
    }

    public var uuid: String
    public var wordId: Int64
    public var state: State
    public var easiness: Double        // SM-2 EF 因子，初始 2.5，下限 1.3
    public var repetition: Int         // 连续答对次数
    public var intervalDays: Double    // 当前间隔（天）
    public var dueAt: Date
    public var reviewCount: Int
    public var lapseCount: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?        // 软删除标记（为快照合并预留）

    enum CodingKeys: String, CodingKey {
        case uuid, state, easiness, repetition
        case wordId = "word_id"
        case intervalDays = "interval_days"
        case dueAt = "due_at"
        case reviewCount = "review_count"
        case lapseCount = "lapse_count"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case deletedAt = "deleted_at"
    }

    /// 首次学习某个单词时创建的初始卡片
    public static func fresh(wordId: Int64, now: Date = Date()) -> StudyCard {
        StudyCard(
            uuid: UUID().uuidString,
            wordId: wordId,
            state: .learning,
            easiness: 2.5,
            repetition: 0,
            intervalDays: 0,
            dueAt: now,
            reviewCount: 0,
            lapseCount: 0,
            createdAt: now,
            modifiedAt: now,
            deletedAt: nil
        )
    }
}

// MARK: - ReviewLog 复习流水（只追加，合并时取并集）

public struct ReviewLog: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "review_log"

    public var uuid: String
    public var cardUuid: String
    public var wordId: Int64
    public var rating: Int             // 1 忘记 / 2 模糊 / 3 记得 / 4 太简单
    public var stateBefore: String
    public var reviewedAt: Date

    enum CodingKeys: String, CodingKey {
        case uuid, rating
        case cardUuid = "card_uuid"
        case wordId = "word_id"
        case stateBefore = "state_before"
        case reviewedAt = "reviewed_at"
    }

    public init(uuid: String, cardUuid: String, wordId: Int64, rating: Int, stateBefore: String, reviewedAt: Date) {
        self.uuid = uuid
        self.cardUuid = cardUuid
        self.wordId = wordId
        self.rating = rating
        self.stateBefore = stateBefore
        self.reviewedAt = reviewedAt
    }
}

// MARK: - DailyStat 每日统计

public struct DailyStat: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "daily_stat"

    public var date: String            // 本地日期 "yyyy-MM-dd"
    public var newLearned: Int
    public var reviewed: Int
    public var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case date
        case newLearned = "new_learned"
        case reviewed
        case modifiedAt = "modified_at"
    }

    public static func localDateString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

// MARK: - StudyItem 队列条目（词 + 可选卡片）

public struct StudyItem: Identifiable, Equatable {
    public var word: Word
    public var card: StudyCard?        // nil = 新词，首次自评时创建

    public var id: Int64 { word.id }
    public var isNew: Bool { card == nil }

    public init(word: Word, card: StudyCard?) {
        self.word = word
        self.card = card
    }
}
