import SwiftUI
import DailyWordCore
import GRDB

/// 单词详情弹窗：完整释义 + 词形变化 + 趣味记词（词根词缀拆解）
struct WordDetailView: View {
    let item: StudyItem
    /// 独立窗口模式：由外部关闭（避免依赖 sheet 的 dismiss 环境）
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private let memory = WordMemoryService.shared

    /// 词库 headword → 释义 字典（一次性加载缓存，供拆分记忆使用）
    @State private var wordMeanings: [String: String] = [:]
    @State private var wordSet: Set<String> = []
    @State private var wordList: [String] = []

    private static let wordDictLock = NSLock()
    private static var cachedWordMeanings: [String: String]?
    private static var cachedWordSet: Set<String>?
    private static var cachedWordList: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部：单词 + 音标 + 词性
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.word.headword)
                    .font(.system(size: 26, weight: .bold))
                if let phonetic = item.word.phonetic {
                    Text("/\(phonetic)/")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let onClose { onClose() } else { dismiss() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 词性 + 完整中文释义
                    if let pos = item.word.pos {
                        Text(pos)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    Text(item.word.definitionCn)
                        .font(.body)
                        .textSelection(.enabled)

                    // 考纲
                    if let tag = memory.tagText(for: item.word) {
                        sectionDivider
                        sectionTitle("考纲")
                        Text(tag)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    // 词形变化
                    if let exchange = memory.exchangeText(item.word.exchange) {
                        sectionDivider
                        sectionTitle("词形变化")
                        Text(exchange)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    // 趣味记词（有专属记忆时显示，无记忆时不展示）
                    let fun = memory.funMemory(for: item.word.headword)
                    let root = memory.memory(for: item.word.headword)
                    let stem = memory.stemMemory(for: item.word.headword, wordSet: wordSet)
                    let split = memory.splitMemory(for: item.word.headword, wordMeanings: wordMeanings)
                    if fun != nil || root != nil || stem != nil || split != nil {
                        sectionDivider
                        sectionTitle("趣味记词")
                    }
                    if let fun {
                        Text(fun)
                            .font(.callout)
                            .foregroundColor(.orange)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let root, root != fun {
                        Text(root)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let stem, stem != fun, stem != root {
                        Text(stem)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let split, split != fun, split != root, split != stem {
                        Text(split)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    // 短语
                    if let phrases = memory.phrases(for: item.word.headword) {
                        sectionDivider
                        sectionTitle("短语")
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(phrases, id: \.self) { p in
                                Text("· " + p)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 例句（内置库 + 高亮显示）
                    let ss = AppServices.shared.sentences(for: item.word.headword); if !ss.isEmpty {
                        sectionDivider
                        sectionTitle("例句")
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(ss, id: \.self) { sentence in
                                AppServices.highlightedSentence(sentence, word: item.word.headword)
                                    .font(.callout)
                            }
                        }
                    }
                    // 同近义词
                    if let syns = memory.synonyms(for: item.word.headword) {
                        sectionDivider
                        sectionTitle("同近义词")
                        Text(syns.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    // 同词根
                    let sameRoot = memory.sameRootWords(for: item.word.headword, wordList: wordList)
                    if !sameRoot.isEmpty {
                        sectionDivider
                        sectionTitle("同词根")
                        Text(sameRoot.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 440, height: 420)
        .onAppear {
            // 一次性加载词库 headword→释义 字典（进程内缓存）
            Self.wordDictLock.lock()
            if Self.cachedWordMeanings == nil {
                if let rows = try? AppServices.shared.database.dbQueue.read({ db in
                    try Row.fetchAll(db, sql: "SELECT headword, definition_cn FROM word")
                }) {
                    var meanings: [String: String] = [:]
                    var set: Set<String> = []
                    var list: [String] = []
                    for row in rows {
                        let h = (row["headword"] as String).lowercased()
                        meanings[h] = row["definition_cn"] as String
                        set.insert(h)
                        list.append(h)
                    }
                    Self.cachedWordMeanings = meanings
                    Self.cachedWordSet = set
                    Self.cachedWordList = list
                }
            }
            wordMeanings = Self.cachedWordMeanings ?? [:]
            wordSet = Self.cachedWordSet ?? []
            wordList = Self.cachedWordList ?? []
            Self.wordDictLock.unlock()
        }
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 2)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
