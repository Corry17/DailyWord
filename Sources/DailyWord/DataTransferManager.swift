import Foundation
import DailyWordCore

/// 数据导入导出：跨设备迁移（设置 / 词库熟练度 / 经验成就与目标 / 游戏进度）
@MainActor
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
        "translateWholeSentence", "wordColorRGBA", "wordFontSize", "dailyNewLimit",
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
        if includeVocabulary { sections["vocabulary"] = try AppServices.shared.database.vocabularySnapshot().jsonObject() }
        return try BackupArchive.encode(sections: sections)
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

    // MARK: - 导入

    /// 应用导入数据，返回已导入的部分列表
    func importData(_ data: Data) throws -> [String] {
        let sections = try BackupArchive.decode(data)
        var imported: [String] = []
        var changes: [String: Any] = [:]

        if let settings = sections["settings"] as? [String: Any] {
            let favoriteKeys = settings.keys.filter { $0.hasPrefix("favoriteColors.") }
            changes.merge(try BackupArchive.defaultsChanges(settings, allowedKeys: settingsKeys + favoriteKeys)) { _, new in new }
            try BackupArchive.validateSettings(changes)
            imported.append("设置")
        }
        if let rewards = sections["rewards"] as? [String: Any] {
            changes.merge(try BackupArchive.defaultsChanges(rewards, allowedKeys: rewardsKeys)) { _, new in new }
            imported.append("目标与自我激励")
        }
        if let game = sections["game"] as? [String: Any] {
            changes.merge(try BackupArchive.defaultsChanges(game, allowedKeys: gameKeys)) { _, new in new }
            imported.append("游戏进度")
        }
        let snapshot = try (sections["vocabulary"] as? [String: Any]).map(VocabularySnapshot.decode)
        let stats = try AppServices.shared.database.applyBackup(snapshot: snapshot, defaultsChanges: changes, defaults: .standard)
        if let stats { imported.append("词库熟练度与成就（新增 \(stats.inserted) · 保留本地 \(stats.skipped)）") }
        return imported
    }

}