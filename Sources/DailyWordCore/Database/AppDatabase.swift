import Foundation
import GRDB

/// 数据库封装：单一 SQLite 文件（用户数据 + 首次启动时导入的词库）。
/// 词库表 word 为只读数据，不参与同步；用户表带 uuid/modified_at/软删除，为快照合并预留。
public final class AppDatabase {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    /// 生产环境：~/Library/Application Support/DailyWord/dailyword.sqlite
    public static func makeShared() throws -> AppDatabase {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("DailyWord", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let dbURL = supportDir.appendingPathComponent("dailyword.sqlite")
        let db = try AppDatabase(dbQueue: DatabaseQueue(path: dbURL.path))
        try db.importBundledWordsIfNeeded()
        return db
    }

    /// 测试环境：内存数据库
    public static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(dbQueue: DatabaseQueue())
    }

    // MARK: - 迁移

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // 词库表（与 Tools/dict-builder 的 schema 保持一致）
            try db.create(table: "word") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("headword", .text).notNull().unique()
                t.column("phonetic", .text)
                t.column("definition_cn", .text).notNull()
                t.column("definition_en", .text)
                t.column("pos", .text)
                t.column("tags", .text)
                t.column("frequency", .integer)
                t.column("collins", .integer)
                t.column("oxford", .integer)
                t.column("exchange", .text)
            }
            try db.create(index: "idx_word_frequency", on: "word", columns: ["frequency"])

            try db.create(table: "study_card") { t in
                t.column("uuid", .text).primaryKey()
                t.column("word_id", .integer).notNull().unique().references("word")
                t.column("state", .text).notNull()
                t.column("easiness", .double).notNull()
                t.column("repetition", .integer).notNull()
                t.column("interval_days", .double).notNull()
                t.column("due_at", .datetime).notNull()
                t.column("review_count", .integer).notNull()
                t.column("lapse_count", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("modified_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }
            try db.create(index: "idx_card_due", on: "study_card", columns: ["due_at"])

            try db.create(table: "review_log") { t in
                t.column("uuid", .text).primaryKey()
                t.column("card_uuid", .text).notNull()
                t.column("word_id", .integer).notNull()
                t.column("rating", .integer).notNull()
                t.column("state_before", .text).notNull()
                t.column("reviewed_at", .datetime).notNull()
            }

            try db.create(table: "daily_stat") { t in
                t.column("date", .text).primaryKey()
                t.column("new_learned", .integer).notNull().defaults(to: 0)
                t.column("reviewed", .integer).notNull().defaults(to: 0)
                t.column("modified_at", .datetime).notNull()
            }
        }

        // v2：多词库（collection / collection_word），与 Tools/dict-builder 的 schema 保持一致
        migrator.registerMigration("v2") { db in
            try db.create(table: "collection", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("key", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull()
            }
            try db.create(table: "collection_word", ifNotExists: true) { t in
                t.column("collection_id", .integer).notNull()
                t.column("word_id", .integer).notNull()
                t.primaryKey(["collection_id", "word_id"])
            }
            try db.create(index: "idx_collection_word_word", on: "collection_word", columns: ["word_id"])
        }
        // v3：大数据量查询索引（复习流水/打卡/到期卡）
        migrator.registerMigration("v3") { db in
            try db.create(index: "idx_review_log_rating", on: "review_log", columns: ["rating", "state_before"], ifNotExists: true)
            try db.create(index: "idx_review_log_reviewed_at", on: "review_log", columns: ["reviewed_at"], ifNotExists: true)
            try db.create(index: "idx_study_card_state", on: "study_card", columns: ["state"], ifNotExists: true)
            try db.create(index: "idx_study_card_due_at", on: "study_card", columns: ["due_at"], ifNotExists: true)
        }
        return migrator
    }

    // MARK: - 词库导入

    /// 首次启动 / 旧库升级：word 为空时整表导入；collection 为空时补充导入词库关系
    public func importBundledWordsIfNeeded() throws {
        guard let bundleURL = Bundle.module.url(forResource: "words", withExtension: "sqlite") else {
            throw DatabaseError(message: "打包词库 words.sqlite 缺失")
        }
        // ATTACH/DETACH 不能在事务内执行，故用 writeWithoutTransaction，仅对 INSERT 显式开事务
        try dbQueue.writeWithoutTransaction { db in
            let wordCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM word") ?? 0
            let colCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM collection") ?? 0
            guard colCount == 0 else { return }   // 词库关系已导入
            try db.execute(sql: "ATTACH DATABASE ? AS dict", arguments: [bundleURL.path])
            do {
                try db.inTransaction {
                    if wordCount == 0 {
                        try db.execute(sql: """
                            INSERT INTO word (id, headword, phonetic, definition_cn, definition_en, pos, tags, frequency, collins, oxford, exchange)
                            SELECT id, headword, phonetic, definition_cn, definition_en, pos, tags, frequency, collins, oxford, exchange
                            FROM dict.word
                            """)
                    } else {
                        // 旧库升级：补充导入用户库缺失的词（其他词库的词），id 重新自增分配
                        try db.execute(sql: """
                            INSERT INTO word (headword, phonetic, definition_cn, definition_en, pos, tags, frequency, collins, oxford, exchange)
                            SELECT dw.headword, dw.phonetic, dw.definition_cn, dw.definition_en, dw.pos, dw.tags, dw.frequency, dw.collins, dw.oxford, dw.exchange
                            FROM dict.word dw
                            WHERE NOT EXISTS (SELECT 1 FROM word w WHERE w.headword = dw.headword)
                            """)
                    }
                    try db.execute(sql: """
                        INSERT INTO collection (id, key, name, sort_order)
                        SELECT id, key, name, sort_order FROM dict.collection
                        """)
                    // collection_word 通过 headword 匹配本库 word.id，兼容旧库 id 顺序不一致的情况
                    try db.execute(sql: """
                        INSERT INTO collection_word (collection_id, word_id)
                        SELECT dc.collection_id, w.id
                        FROM dict.collection_word dc
                        JOIN dict.word dw ON dw.id = dc.word_id
                        JOIN word w ON w.headword = dw.headword
                        """)
                    return .commit
                }
                try db.execute(sql: "DETACH DATABASE dict")
            } catch {
                try? db.execute(sql: "DETACH DATABASE dict")
                throw error
            }
        }
    }

    // MARK: - 词库

    /// 全部词库（按顺序）
    public func collections() throws -> [WordCollection] {
        try dbQueue.read { db in
            try WordCollection.order(Column("sort_order")).fetchAll(db)
        }
    }

    /// 按词库 key 过滤的 SQL 片段（key 为 nil 时不加过滤）
    private static func collectionFilter(_ key: String?) -> (join: String, where: String, args: [DatabaseValueConvertible]) {
        guard let key else { return ("", "", []) }
        return (
            " JOIN collection_word cw ON cw.word_id = w.id JOIN collection c ON c.id = cw.collection_id",
            " AND c.key = ?",
            [key]
        )
    }

    // MARK: - 队列查询

    /// 到期需要复习的卡片（含所属单词），按到期时间排序
    public func dueItems(now: Date = Date(), collectionKey: String? = nil) throws -> [StudyItem] {
        let f = Self.collectionFilter(collectionKey)
        return try dbQueue.read { db in
            // 一次取卡、一次取词（避免每行 N+1 查询导致大数据量卡顿）
            let cards = try StudyCard.fetchAll(db, sql: """
                SELECT c.* FROM study_card c
                JOIN word w ON w.id = c.word_id
                \(f.join)
                WHERE c.due_at <= ? AND c.state != 'suspended' AND c.deleted_at IS NULL
                \(f.where)
                ORDER BY c.due_at ASC
                """, arguments: StatementArguments([now] + f.args))
            guard !cards.isEmpty else { return [] }
            let words = try Word.fetchAll(db, sql: """
                SELECT w.* FROM word w
                JOIN study_card c ON c.word_id = w.id
                \(f.join)
                WHERE c.due_at <= ? AND c.state != 'suspended' AND c.deleted_at IS NULL
                \(f.where)
                """, arguments: StatementArguments([now] + f.args))
            let wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
            return cards.compactMap { card in
                guard let word = wordsByID[card.wordId] else { return nil }
                return StudyItem(word: word, card: card)
            }
        }
    }

    /// 到期卡数量（只计数不取行，角标/弹卡刷新用）
    public func dueCount(now: Date = Date(), collectionKey: String? = nil) throws -> Int {
        let f = Self.collectionFilter(collectionKey)
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM study_card c
                JOIN word w ON w.id = c.word_id
                \(f.join)
                WHERE c.due_at <= ? AND c.state != 'suspended' AND c.deleted_at IS NULL
                \(f.where)
                """, arguments: StatementArguments([now] + f.args)) ?? 0
        }
    }

    /// 还没有学习卡片的新词，按词频从高到低（frequency 数字越小越高频）
    public func newWordItems(limit: Int, collectionKey: String? = nil) throws -> [StudyItem] {
        guard limit > 0 else { return [] }
        let f = Self.collectionFilter(collectionKey)
        return try dbQueue.read { db in
            let words = try Word.fetchAll(db, sql: """
                SELECT w.* FROM word w
                \(f.join)
                LEFT JOIN study_card c ON c.word_id = w.id
                WHERE c.uuid IS NULL
                \(f.where)
                ORDER BY CASE WHEN w.frequency IS NULL THEN 1 ELSE 0 END, w.frequency ASC, w.id ASC
                LIMIT ?
                """, arguments: StatementArguments(f.args + [limit]))
            return words.map { StudyItem(word: $0, card: nil) }
        }
    }

    /// 词库词（词 + 学习状态），词库浏览页与练习浮层使用；按词频从高到低排序
    /// limit 非 nil 时按页返回（分页浏览，避免一次性加载上万行卡顿）
    public func allItems(collectionKey: String? = nil, limit: Int? = nil, offset: Int = 0) throws -> [StudyItem] {
        let f = Self.collectionFilter(collectionKey)
        var sql = """
            SELECT w.* FROM word w
            \(f.join)
            WHERE 1=1
            \(f.where)
            ORDER BY CASE WHEN w.frequency IS NULL THEN 1 ELSE 0 END, w.frequency ASC, w.id ASC
            """
        var args: [DatabaseValueConvertible] = f.args
        if let limit {
            sql += " LIMIT ? OFFSET ?"
            args += [limit, offset]
        }
        return try dbQueue.read { db in
            let words = try Word.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            let cards = try StudyCard.fetchAll(db, sql: "SELECT * FROM study_card WHERE deleted_at IS NULL")
            let cardsByWord = Dictionary(uniqueKeysWithValues: cards.map { ($0.wordId, $0) })
            return words.map { StudyItem(word: $0, card: cardsByWord[$0.id]) }
        }
    }

    /// 当前词库统计（总数 / 已学 / 已掌握），供词库页顶部展示
    public func collectionStats(collectionKey: String?) throws -> (total: Int, learned: Int, mastered: Int) {
        let f = Self.collectionFilter(collectionKey)
        return try dbQueue.read { db in
            let total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM word w \(f.join)
                WHERE 1=1 \(f.where)
                """, arguments: StatementArguments(f.args)) ?? 0
            let learned = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM word w \(f.join)
                JOIN study_card c ON c.word_id = w.id
                WHERE c.deleted_at IS NULL
                \(f.where)
                """, arguments: StatementArguments(f.args)) ?? 0
            let mastered = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM word w \(f.join)
                JOIN study_card c ON c.word_id = w.id
                WHERE c.state = 'mastered' AND c.deleted_at IS NULL
                \(f.where)
                """, arguments: StatementArguments(f.args)) ?? 0
            return (total, learned, mastered)
        }
    }

    /// 指定词的条目（词 + 学习状态）
    public func items(forWordIds ids: [Int64]) throws -> [StudyItem] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = databaseQuestionMarks(count: ids.count)
            let words = try Word.fetchAll(
                db, sql: "SELECT * FROM word WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids))
            let cards = try StudyCard.fetchAll(
                db, sql: "SELECT * FROM study_card WHERE word_id IN (\(placeholders)) AND deleted_at IS NULL",
                arguments: StatementArguments(ids))
            let cardsByWord = Dictionary(uniqueKeysWithValues: cards.map { ($0.wordId, $0) })
            return words.map { StudyItem(word: $0, card: cardsByWord[$0.id]) }
        }
    }

    /// 今天学过/复习过的所有词 id（依据复习流水，重启 App 也能恢复）
    public func wordIdsStudiedToday(now: Date = Date()) throws -> [Int64] {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return try dbQueue.read { db in
            try Int64.fetchAll(db, sql: "SELECT DISTINCT word_id FROM review_log WHERE reviewed_at >= ?",
                               arguments: [startOfDay])
        }
    }

    /// 今天已引入的新词数量（用于扣减每日新词额度）
    public func newCardsCreatedToday(now: Date = Date()) throws -> Int {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM study_card WHERE created_at >= ?",
                             arguments: [startOfDay]) ?? 0
        }
    }

    // MARK: - 写入

    /// 一次自评的完整落库：卡片 upsert + 复习流水 + 每日统计，单事务
    public func recordReview(card: StudyCard, log: ReviewLog, isNewWord: Bool, now: Date = Date()) throws {
        try dbQueue.write { db in
            // 按 word_id upsert（不按 uuid：导入等场景可能造成同词多 uuid，避免 UNIQUE 冲突）
            try db.execute(sql: """
                INSERT INTO study_card
                    (uuid, word_id, state, easiness, repetition, interval_days, due_at,
                     review_count, lapse_count, created_at, modified_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(word_id) DO UPDATE SET
                    state = excluded.state, easiness = excluded.easiness,
                    repetition = excluded.repetition, interval_days = excluded.interval_days,
                    due_at = excluded.due_at, review_count = excluded.review_count,
                    lapse_count = excluded.lapse_count, created_at = excluded.created_at,
                    modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
                """, arguments: [
                card.uuid,
                card.wordId,
                card.state.rawValue,
                card.easiness,
                card.repetition,
                card.intervalDays,
                card.dueAt,
                card.reviewCount,
                card.lapseCount,
                card.createdAt,
                card.modifiedAt,
                card.deletedAt,
            ])
            try log.insert(db)

            let today = DailyStat.localDateString(for: now)
            if var stat = try DailyStat.fetchOne(db, key: today) {
                stat.reviewed += 1
                if isNewWord { stat.newLearned += 1 }
                stat.modifiedAt = now
                try stat.update(db)
            } else {
                let stat = DailyStat(date: today, newLearned: isNewWord ? 1 : 0, reviewed: 1, modifiedAt: now)
                try stat.insert(db)
            }
        }
    }

    /// 手动调整某个词的学习状态（词库页使用）
    /// - state 为 nil：删除卡片，重置为未学
    /// - .learning：回到阶梯起点重新学习（立即到期）
    /// - .mastered：直接标记已掌握（180 天后再出现）
    /// - .suspended：斩词，不再出现
    public func setCardState(wordId: Int64, to newState: StudyCard.State?, now: Date = Date()) throws {
        try dbQueue.write { db in
            let existing = try StudyCard.fetchOne(
                db, sql: "SELECT * FROM study_card WHERE word_id = ?", arguments: [wordId])

            guard let newState else {
                _ = try existing?.delete(db)
                return
            }

            var card = existing ?? StudyCard.fresh(wordId: wordId, now: now)
            card.state = newState
            card.modifiedAt = now
            switch newState {
            case .learning:
                card.repetition = 0
                card.intervalDays = 0
                card.dueAt = now
            case .mastered:
                card.repetition = EbbinghausScheduler.steps.count
                card.intervalDays = EbbinghausScheduler.masteredInterval / 86_400
                card.dueAt = now.addingTimeInterval(EbbinghausScheduler.masteredInterval)
            case .review, .suspended:
                break   // 保留现有排期参数
            }
            if newState == .suspended {
                // 毕业：推到大后天（约 100 年后），确保任何逻辑都不会再让它到期出现
                card.dueAt = now.addingTimeInterval(3650 * 86_400)
                card.intervalDays = 3650
            }
            try card.save(db)
        }
    }

    public func todayStat(now: Date = Date()) throws -> DailyStat? {
        try dbQueue.read { db in
            try DailyStat.fetchOne(db, key: DailyStat.localDateString(for: now))
        }
    }
}
