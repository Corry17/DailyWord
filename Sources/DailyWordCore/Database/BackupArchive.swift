import Foundation
import CoreFoundation
import GRDB

public enum BackupError: LocalizedError {
    case invalidFormat, unsupportedVersion, invalidValue(String), emptySelection
    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "不是有效的 DailyWord 备份文件"
        case .unsupportedVersion: return "备份版本不受支持，请使用兼容版本的应用"
        case .invalidValue(let field): return "备份字段无效：\(field)；未写入任何数据"
        case .emptySelection: return "请至少选择一项需要备份的数据"
        }
    }
}

/// 统一检查备份封装和 UserDefaults 数据，避免非法空值/二进制进入偏好设置。
public enum BackupArchive {
    public static func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= 64 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["app"] as? String == "DailyWord",
              let version = root["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              let sections = root["sections"] as? [String: Any], !sections.isEmpty else {
            throw BackupError.invalidFormat
        }
        guard version.doubleValue == 1 else { throw BackupError.unsupportedVersion }
        let supported: Set<String> = ["settings", "rewards", "game", "vocabulary"]
        guard !Set(sections.keys).isDisjoint(with: supported) else { throw BackupError.invalidFormat }
        for key in supported where sections[key] != nil {
            guard sections[key] is [String: Any] else { throw BackupError.invalidValue(key) }
        }
        return sections
    }

    public static func encode(sections: [String: Any]) throws -> Data {
        guard !sections.isEmpty else { throw BackupError.emptySelection }
        let root: [String: Any] = ["app": "DailyWord", "version": 1,
                                  "exportedAt": ISO8601DateFormatter().string(from: Date()), "sections": sections]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// 返回已验证的操作；顶层 null 表示删除该设置，嵌套 null 则拒绝。
    public static func defaultsChanges(_ values: [String: Any], allowedKeys: [String]) throws -> [String: Any] {
        var changes: [String: Any] = [:]
        for key in allowedKeys {
            guard let value = values[key] else { continue }
            if value is NSNull { changes[key] = NSNull(); continue }
            if let marker = value as? [String: Any], marker["__data__"] != nil {
                guard marker.count == 1, let encoded = marker["__data__"] as? String,
                      let data = Data(base64Encoded: encoded) else { throw BackupError.invalidValue(key) }
                changes[key] = data
            } else {
                guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
                    throw BackupError.invalidValue(key)
                }
                changes[key] = value
            }
        }
        return changes
    }

    public static func validateSettings(_ values: [String: Any]) throws {
        let ranges: [String: ClosedRange<Double>] = [
            "wordFontSize": 20...44, "libraryFontSize": 14...44, "quizFontSize": 14...32,
            "studyOpacity": 0...1, "quizOpacity": 0...0.85,
            "dailyNewLimit": 1...100, "ambientIntervalMinutes": 1...1440
        ]
        for (key, value) in values where !(value is NSNull) {
            if let range = ranges[key] {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, range.contains(number.doubleValue) else { throw BackupError.invalidValue(key) }
                if key == "dailyNewLimit" || key == "ambientIntervalMinutes" {
                    guard number.doubleValue.rounded() == number.doubleValue else { throw BackupError.invalidValue(key) }
                }
            } else if key.hasSuffix("ColorRGBA") {
                guard let components = value as? [Double], components.count == 4,
                      components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw BackupError.invalidValue(key) }
            } else if ["accent", "ambientPosition", "currentCollectionKey", "studyDirection"].contains(key) {
                guard let string = value as? String, !string.isEmpty else { throw BackupError.invalidValue(key) }
                let enumValues: [String: Set<String>] = [
                    "accent": ["en-US", "en-GB"], "studyDirection": ["enToCn", "cnToEn"],
                    "ambientPosition": ["topCenter", "topRight", "topLeft", "bottomRight", "bottomLeft"]
                ]
                if let allowed = enumValues[key], !allowed.contains(string) { throw BackupError.invalidValue(key) }
            } else if key == "translateWholeSentence" {
                guard let boolean = value as? NSNumber, CFGetTypeID(boolean) == CFBooleanGetTypeID() else { throw BackupError.invalidValue(key) }
            } else if key == "hotKeyBindingsV2" {
                guard let raw = value as? [String: String] else { throw BackupError.invalidValue(key) }
                var assigned: Set<String> = []
                for (_, stored) in raw {
                    guard let binding = ShortcutBinding(storage: stored) else { throw BackupError.invalidValue(key) }
                    if binding.isSet, !assigned.insert(binding.storage).inserted { throw BackupError.invalidValue(key) }
                }
            }
        }
    }

    public static func apply(_ changes: [String: Any], to defaults: UserDefaults) {
        for (key, value) in changes {
            if value is NSNull { defaults.removeObject(forKey: key) }
            else { defaults.set(value, forKey: key) }
        }
    }
}

/// 与 v1 JSON 字段兼容的强类型快照；全部解码和校验完成后才开始写库。
public struct VocabularySnapshot: Codable {
    public var studyCards: [StudyCard]
    public var reviewLogs: [ReviewLog]
    public var dailyStats: [DailyStat]

    public init(studyCards: [StudyCard], reviewLogs: [ReviewLog], dailyStats: [DailyStat]) {
        self.studyCards = studyCards; self.reviewLogs = reviewLogs; self.dailyStats = dailyStats
    }
    private enum CodingKeys: String, CodingKey { case studyCards, reviewLogs, dailyStats }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        studyCards = container.contains(.studyCards) ? try container.decode([StudyCard].self, forKey: .studyCards) : []
        reviewLogs = container.contains(.reviewLogs) ? try container.decode([ReviewLog].self, forKey: .reviewLogs) : []
        dailyStats = container.contains(.dailyStats) ? try container.decode([DailyStat].self, forKey: .dailyStats) : []
    }

    public static func decode(_ object: [String: Any]) throws -> Self {
        guard ["studyCards", "reviewLogs", "dailyStats"].contains(where: { object[$0] != nil }) else {
            throw BackupError.invalidValue("vocabulary")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var snapshot = try decoder.decode(Self.self, from: JSONSerialization.data(withJSONObject: object))
        // 兼容早期备份用 0 表示未删除的记录。
        for index in snapshot.studyCards.indices where snapshot.studyCards[index].deletedAt?.timeIntervalSince1970 == 0 {
            snapshot.studyCards[index].deletedAt = nil
        }
        try snapshot.validate()
        return snapshot
    }

    public func jsonObject() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard var result = try JSONSerialization.jsonObject(with: encoder.encode(self)) as? [String: Any] else {
            throw BackupError.invalidFormat
        }
        var cards = result["studyCards"] as? [[String: Any]] ?? []
        for index in cards.indices where cards[index]["deleted_at"] == nil { cards[index]["deleted_at"] = NSNull() }
        result["studyCards"] = cards
        return result
    }

    public func validate() throws {
        func validDate(_ date: Date) -> Bool {
            let timestamp = date.timeIntervalSince1970
            return timestamp.isFinite && (0...253_402_300_799).contains(timestamp)
        }
        var ids = Set<Int64>(), uuids = Set<String>()
        for card in studyCards {
            guard card.wordId > 0, !card.uuid.isEmpty,
                  ids.insert(card.wordId).inserted, uuids.insert(card.uuid).inserted,
                  card.easiness.isFinite, (1...100).contains(card.easiness),
                  card.intervalDays.isFinite, (0...100_000).contains(card.intervalDays),
                  (0...10_000_000).contains(card.repetition), (0...10_000_000).contains(card.reviewCount),
                  (0...10_000_000).contains(card.lapseCount),
                  validDate(card.dueAt), validDate(card.createdAt), validDate(card.modifiedAt),
                  card.deletedAt.map(validDate) ?? true else { throw BackupError.invalidValue("studyCards") }
        }
        for log in reviewLogs {
            guard !log.uuid.isEmpty, !log.cardUuid.isEmpty, log.wordId > 0, (1...4).contains(log.rating),
                  ["new", "learning", "review", "mastered", "suspended"].contains(log.stateBefore),
                  validDate(log.reviewedAt) else { throw BackupError.invalidValue("reviewLogs") }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        for stat in dailyStats {
            guard let day = formatter.date(from: stat.date), formatter.string(from: day) == stat.date,
                  (0...10_000_000).contains(stat.newLearned), (0...10_000_000).contains(stat.reviewed),
                  validDate(stat.modifiedAt) else { throw BackupError.invalidValue("dailyStats") }
        }
    }
}

public struct VocabularyImportSummary {
    public var inserted = 0
    public var skipped = 0
}

extension AppDatabase {
    /// 数据库失败时不触碰设置；所有设置先校验为合法 property list，再提交数据库。
    public func applyBackup(snapshot: VocabularySnapshot?, defaultsChanges: [String: Any],
                            defaults: UserDefaults) throws -> VocabularyImportSummary? {
        for (key, value) in defaultsChanges where !(value is NSNull) {
            guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
                throw BackupError.invalidValue(key)
            }
        }
        try BackupArchive.validateSettings(defaultsChanges)
        let result = try snapshot.map(importVocabularySnapshot)
        BackupArchive.apply(defaultsChanges, to: defaults)
        return result
    }

    /// 同一次读取事务获取三个表，避免导出混用不同时刻的快照。
    public func vocabularySnapshot() throws -> VocabularySnapshot {
        try dbQueue.read { db in
            VocabularySnapshot(studyCards: try StudyCard.fetchAll(db),
                               reviewLogs: try ReviewLog.fetchAll(db), dailyStats: try DailyStat.fetchAll(db))
        }
    }

    /// 词条/流水/统计同一事务；任何写入失败整批回滚。偏好设置只在成功返回后应用。
    public func importVocabularySnapshot(_ snapshot: VocabularySnapshot) throws -> VocabularyImportSummary {
        try snapshot.validate()
        return try dbQueue.write { db in
            var result = VocabularyImportSummary()
            for card in snapshot.studyCards {
                let exists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM study_card WHERE word_id = ?)", arguments: [card.wordId]) ?? false
                if exists { result.skipped += 1; continue }
                try card.insert(db)
                result.inserted += 1
            }
            for log in snapshot.reviewLogs {
                var merged = log
                // 同词在本地有不同卡片 UUID 时，保持流水关联一致。
                if let uuid = try String.fetchOne(db, sql: "SELECT uuid FROM study_card WHERE word_id = ?", arguments: [log.wordId]) {
                    merged.cardUuid = uuid
                }
                try merged.insert(db, onConflict: .ignore)
            }
            for stat in snapshot.dailyStats {
                // 旧备份不能降低同一天已经完成的学习/复习计数。
                try db.execute(sql: """
                    INSERT INTO daily_stat (date, new_learned, reviewed, modified_at) VALUES (?, ?, ?, ?)
                    ON CONFLICT(date) DO UPDATE SET
                        new_learned = MAX(daily_stat.new_learned, excluded.new_learned),
                        reviewed = MAX(daily_stat.reviewed, excluded.reviewed),
                        modified_at = MAX(daily_stat.modified_at, excluded.modified_at)
                    """, arguments: [stat.date, stat.newLearned, stat.reviewed, stat.modifiedAt])
            }
            return result
        }
    }
}
