import Foundation
import GRDB

/// 数据导入导出：跨设备迁移（设置 / 词库熟练度 / 经验成就与目标 / 游戏进度）
final class DataTransferManager {
    static let shared = DataTransferManager()
    private init() {}

    // MARK: - 分组 Key

    private let settingsKeys = [
        "accent", "ambientIntervalMinutes", "ambientPosition", "currentCollectionKey",
        "definitionColorRGBA", "hotKeyBindingsV2",
        "libraryDefinitionColorRGBA", "libraryFontSize", "libraryWordColorRGBA",
        "quizBackgroundColorRGBA", "quizDefinitionColorRGBA", "quizFontSize",
        "quizOpacity", "quizWordColorRGBA",
        "studyBackgroundColorRGBA", "studyDirection", "studyOpacity",
        "translateWholeSentence", "wordColorRGBA", "wordFontSize",
    ]

    private let rewardsKeys = [
        "achievementUnlockedDates", "selfGoals", "selfMileStones",
    ]

    private let gameKeys = [
        "towerCoins", "towerCollected", "towerEquipped", "towerHero",
        "towerInventory", "towerPathCompleted", "towerSave", "towerShopIds",
        "towerShopStamp", "towerUnlockedStage", "towerWins",
    ]

    // MARK: - 导出

    func exportData(includeSettings: Bool, includeVocabulary: Bool,
                    includeRewards: Bool, includeGame: Bool) throws -> Data {
        var sections: [String: Any] = [:]
        if includeSettings {
            // 设置全量导出：未设置的 key 也导出 null（导入时全覆盖/恢复默认）
            var settings = defaultsDict(for: settingsKeys, includeMissingAsNull: true)
            let all = UserDefaults.standard.dictionaryRepresentation()
            for (key, value) in all where key.hasPrefix("favoriteColors.") {
                if let data = value as? Data {
                    settings[key] = ["__data__": data.base64EncodedString()]
                } else if JSONSerialization.isValidJSONObject([key: value]) {
                    settings[key] = value
                }
            }
            sections["settings"] = settings
        }
        if includeRewards { sections["rewards"] = defaultsDict(for: rewardsKeys) }
        if includeGame { sections["game"] = defaultsDict(for: gameKeys) }
        if includeVocabulary { sections["vocabulary"] = try exportVocabulary() }
        let root: [String: Any] = [
            "app": "DailyWord",
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "sections": sections,
        ]
        return try JSONSerialization.data(withJSONObject: root,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    private func defaultsDict(for keys: [String], includeMissingAsNull: Bool = false) -> [String: Any] {
        let all = UserDefaults.standard.dictionaryRepresentation()
        var dict: [String: Any] = [:]
        for key in keys {
            guard let value = all[key] else {
                // 全量导出模式：未设置的 key 也导出 null（导入时恢复默认）
                if includeMissingAsNull { dict[key] = NSNull() }
                continue
            }
            if let data = value as? Data {
                dict[key] = ["__data__": data.base64EncodedString()]
            } else if JSONSerialization.isValidJSONObject([key: value]) {
                dict[key] = value
            }
        }
        return dict
    }

    private func exportVocabulary() throws -> [String: Any] {
        let queue = AppServices.shared.database.dbQueue
        let cards = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT uuid, word_id, state, easiness, repetition, interval_days, due_at,
                       review_count, lapse_count, created_at, modified_at, deleted_at
                FROM study_card
                """).map { row -> [String: Any] in
                [
                    "uuid": row["uuid"] as String,
                    "word_id": row["word_id"] as Int64,
                    "state": row["state"] as String,
                    "easiness": row["easiness"] as Double,
                    "repetition": row["repetition"] as Int,
                    "interval_days": row["interval_days"] as Double,
                    "due_at": (row["due_at"] as Date?)?.timeIntervalSince1970 ?? 0,
                    "review_count": row["review_count"] as Int,
                    "lapse_count": row["lapse_count"] as Int,
                    "created_at": (row["created_at"] as Date?)?.timeIntervalSince1970 ?? 0,
                    "modified_at": (row["modified_at"] as Date?)?.timeIntervalSince1970 ?? 0,
                    "deleted_at": (row["deleted_at"] as Date?)?.timeIntervalSince1970,
                ]
            }
        }
        let (logs, stats) = try exportReviewStats()
        return ["studyCards": cards, "reviewLogs": logs, "dailyStats": stats]
    }

    /// 复习流水（XP 来源）+ 每日统计（打卡来源）
    private func exportReviewStats() throws -> ([[String: Any]], [[String: Any]]) {
        let queue = AppServices.shared.database.dbQueue
        let logs = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT uuid, card_uuid, word_id, rating, state_before, reviewed_at
                FROM review_log
                """).map { row -> [String: Any] in
                [
                    "uuid": row["uuid"] as String,
                    "card_uuid": row["card_uuid"] as String,
                    "word_id": row["word_id"] as Int64,
                    "rating": row["rating"] as Int,
                    "state_before": row["state_before"] as String,
                    "reviewed_at": (row["reviewed_at"] as Date?)?.timeIntervalSince1970 ?? 0,
                ]
            }
        }
        let stats = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT date, new_learned, reviewed, modified_at FROM daily_stat")
                .map { row -> [String: Any] in
                [
                    "date": row["date"] as String,
                    "new_learned": row["new_learned"] as Int,
                    "reviewed": row["reviewed"] as Int,
                    "modified_at": (row["modified_at"] as Date?)?.timeIntervalSince1970 ?? 0,
                ]
            }
        }
        return (logs, stats)
    }

    // MARK: - 导入

    /// 应用导入数据，返回已导入的部分列表
    func importData(_ data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["sections"] as? [String: Any] else {
            throw ImportError.invalidFormat
        }
        var imported: [String] = []

        if let settings = sections["settings"] as? [String: Any] {
            let favoriteKeys = settings.keys.filter { $0.hasPrefix("favoriteColors.") }
            apply(defaults: settings, keys: settingsKeys + favoriteKeys)
            imported.append("设置")
        }
        if let rewards = sections["rewards"] as? [String: Any] {
            apply(defaults: rewards, keys: rewardsKeys)
            imported.append("目标与自我激励")
        }
        if let game = sections["game"] as? [String: Any] {
            apply(defaults: game, keys: gameKeys)
            imported.append("游戏进度")
        }
        if let vocabulary = sections["vocabulary"] as? [String: Any] {
            let stats = try importVocabulary(vocabulary)
            imported.append("词库熟练度与成就（新增 \(stats.inserted) · 升级 \(stats.upgraded)）")
        }
        return imported
    }

    enum ImportError: Error {
        case invalidFormat
    }

    private func apply(defaults dict: [String: Any], keys: [String]) {
        let defaults = UserDefaults.standard
        for key in keys {
            guard let value = dict[key] else { continue }
            if value is NSNull {
                // 全量覆盖：备份中该 key 为空 → 删除本地（恢复默认）
                defaults.removeObject(forKey: key)
            } else if let marker = value as? [String: String],
               let b64 = marker["__data__"],
               let data = Data(base64Encoded: b64) {
                defaults.set(data, forKey: key)
            } else {
                defaults.set(value, forKey: key)
            }
        }
    }

    /// 熟练度等级（用于取最高）
    private static func stateLevel(_ state: String) -> Int {
        switch state {
        case "suspended": return 5
        case "mastered": return 4
        case "review": return 3
        case "learning": return 2
        case "new": return 1
        default: return 0
        }
    }

    /// 词库熟练度导入：取本地和导入的最高熟练度（state 等级更高者胜）；
    /// review_log 按 uuid 忽略；daily_stat 按 date 替换
    private func importVocabulary(_ vocabulary: [String: Any]) throws -> (inserted: Int, skipped: Int, upgraded: Int) {
        let queue = AppServices.shared.database.dbQueue
        var insertedCount = 0
        var skippedCount = 0
        var upgradedCount = 0
        try queue.write { db in
            if let cards = vocabulary["studyCards"] as? [[String: Any]] {
                for card in cards {
                    let wordId = card["word_id"] as? Int64 ?? 0
                    let importState = card["state"] as? String ?? "new"
                    let importLevel = Self.stateLevel(importState)

                    // 查本地
                    if let localRow = try Row.fetchOne(db, sql: "SELECT state, easiness, repetition, interval_days, due_at, review_count, lapse_count, created_at, modified_at, deleted_at FROM study_card WHERE word_id = ?", arguments: [wordId]) {
                        let localState = localRow["state"] as String
                        let localLevel = Self.stateLevel(localState)
                        skippedCount += 1
                        if importLevel > localLevel {
                            // 导入的熟练度更高 → 升级
                            try db.execute(sql: """
                                UPDATE study_card SET
                                    state = ?, easiness = ?, repetition = ?, interval_days = ?,
                                    due_at = ?, review_count = ?, lapse_count = ?, modified_at = ?
                                WHERE word_id = ?
                                """, arguments: [
                                importState,
                                card["easiness"] as? Double ?? 2.5,
                                card["repetition"] as? Int ?? 0,
                                card["interval_days"] as? Double ?? 0,
                                date(fromTimestamp: card["due_at"]),
                                card["review_count"] as? Int ?? 0,
                                card["lapse_count"] as? Int ?? 0,
                                date(fromTimestamp: card["modified_at"]),
                                wordId,
                            ])
                            upgradedCount += 1
                        }
                    } else {
                        // 本地无 → 插入新卡
                        insertedCount += 1
                        // deleted_at 为 null/0 时存 NULL（否则词库页视为已删除）
                        let deletedAt: Date? = {
                            guard let ts = card["deleted_at"] as? NSNumber, ts.doubleValue > 0 else { return nil }
                            return Date(timeIntervalSince1970: ts.doubleValue)
                        }()
                        try db.execute(sql: """
                            INSERT INTO study_card
                                (uuid, word_id, state, easiness, repetition, interval_days, due_at,
                                 review_count, lapse_count, created_at, modified_at, deleted_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """, arguments: [
                            card["uuid"] as? String ?? UUID().uuidString,
                            wordId,
                            importState,
                            card["easiness"] as? Double ?? 2.5,
                            card["repetition"] as? Int ?? 0,
                            card["interval_days"] as? Double ?? 0,
                            date(fromTimestamp: card["due_at"]),
                            card["review_count"] as? Int ?? 0,
                            card["lapse_count"] as? Int ?? 0,
                            date(fromTimestamp: card["created_at"]),
                            date(fromTimestamp: card["modified_at"]),
                            deletedAt,
                        ])
                    }
                }
            }
        }
        // 兼容旧备份：复习流水/每日统计曾放在 vocabulary 里
        try importReviewLogs(vocabulary["reviewLogs"] as? [[String: Any]])
        try importDailyStats(vocabulary["dailyStats"] as? [[String: Any]])
        // 导入统计日志（定位"没合并"问题）
        let line = "[导入] \(Date()) study_card: 插入 \(insertedCount) 条，跳过（本地已有）\(skippedCount) 条，升级 \(upgradedCount) 条\n"
        if let data = line.data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: "/tmp/dailyword_debug.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: "/tmp/dailyword_debug.log"))
            }
        }
        return (insertedCount, skippedCount, upgradedCount)
    }

    private func importReviewLogs(_ logs: [[String: Any]]?) throws {
        guard let logs, !logs.isEmpty else { return }
        let queue = AppServices.shared.database.dbQueue
        try queue.write { db in
            for log in logs {
                try db.execute(sql: "INSERT OR IGNORE INTO review_log (uuid, card_uuid, word_id, rating, state_before, reviewed_at) VALUES (?, ?, ?, ?, ?, ?)", arguments: [
                    log["uuid"] as? String ?? UUID().uuidString,
                    log["card_uuid"] as? String ?? "",
                    log["word_id"] as? Int64 ?? 0,
                    log["rating"] as? Int ?? 0,
                    log["state_before"] as? String ?? "new",
                    date(fromTimestamp: log["reviewed_at"]),
                ])
            }
        }
    }

    private func importDailyStats(_ stats: [[String: Any]]?) throws {
        guard let stats, !stats.isEmpty else { return }
        let queue = AppServices.shared.database.dbQueue
        try queue.write { db in
            for stat in stats {
                try db.execute(sql: "INSERT OR REPLACE INTO daily_stat (date, new_learned, reviewed, modified_at) VALUES (?, ?, ?, ?)", arguments: [
                    stat["date"] as? String ?? "",
                    stat["new_learned"] as? Int ?? 0,
                    stat["reviewed"] as? Int ?? 0,
                    date(fromTimestamp: stat["modified_at"]),
                ])
            }
        }
    }

    private func date(fromTimestamp value: Any?) -> Date {
        if let ts = value as? NSNumber {
            return Date(timeIntervalSince1970: ts.doubleValue)
        }
        return Date(timeIntervalSince1970: 0)
    }
}