import Foundation
import DailyWordCore

/// 翻译服务：免费联网翻译（Google 非官方接口，无需 API Key），自动中英互译
final class TranslationService {
    static let shared = TranslationService()
    private init() {}

    /// 翻译失败原因
    enum TranslateError {
        case noNetwork   // 网络未连接
        case failed      // 其他失败（接口异常等）
    }

    /// 自动检测语言并互译（中文 → 英文，其他 → 中文）
    /// 后端链：Google（质量最好）→ MyMemory（兜底1）→ 百度词典（兜底2，单词/短语，无上限）
    func translate(_ text: String, request: TranslationRequest = TranslationRequest(),
                   completion: @escaping (String?, TranslateError?) -> Void) {
        guard !request.isCancelled else { completion(nil, .failed); return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(nil, .failed)
            return
        }
        googleTranslate(trimmed, cancellation: request) { result, error in
            guard !request.isCancelled else { completion(nil, .failed); return }
            if let result, !result.isEmpty {
                completion(result, nil)
            } else {
                self.myMemoryTranslate(trimmed, cancellation: request) { fallback, fallbackError in
                    guard !request.isCancelled else { completion(nil, .failed); return }
                    if let fallback, !fallback.isEmpty, !fallback.contains("MYMEMORY WARNING") {
                        completion(fallback, nil)
                    } else {
                        // MyMemory 不可用/额度用尽 → 百度词典（单词/短语无上限）
                        self.baiduSuggestTranslate(trimmed, cancellation: request, completion: completion)
                    }
                }
            }
        }
    }

    /// 百度词典接口（无 key、无上限，仅支持单词/短语；句子返回空）
    private func baiduSuggestTranslate(_ text: String, cancellation: TranslationRequest,
                                       completion: @escaping (String?, TranslateError?) -> Void) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://fanyi.baidu.com/sug") else {
            completion(nil, .failed)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "kw=\(encoded)".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3
        perform(request, cancellation: cancellation) { data, error in
            if let error = error as? URLError, Self.isNetworkError(error) {
                completion(nil, .noNetwork)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]],
                  let first = items.first,
                  let v = first["v"] as? String else {
                completion(nil, .failed)
                return
            }
            // 取第一个释义（分号分隔），去掉词性前缀（int./n./vi. 等）
            let firstMeaning = v.components(separatedBy: "; ").first ?? v
            let cleaned = firstMeaning.replacingOccurrences(
                of: "^(int|n|v|vt|vi|adj|adv|prep|conj|pron|num|art|abbr)\\.",
                with: "", options: .regularExpression)
            let result = cleaned.trimmingCharacters(in: .whitespaces)
            completion(result.isEmpty ? nil : result, result.isEmpty ? .failed : nil)
        }
    }

    /// Google 免费接口（client=gtx，无需 Key）
    private func googleTranslate(_ text: String, cancellation: TranslationRequest,
                                 completion: @escaping (String?, TranslateError?) -> Void) {
        // 中文 → 英文；其余 → 中文
        let targetLang = containsChinese(text) ? "en" : "zh-CN"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetLang)&dt=t&q=\(encoded)") else {
            completion(nil, .failed)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2   // Google 快速失败，及时切换 MyMemory 兜底
        perform(request, cancellation: cancellation) { data, error in
            if let error = error as? URLError, Self.isNetworkError(error) {
                completion(nil, .noNetwork)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let segments = json.first as? [Any] else {
                completion(nil, .failed)
                return
            }
            // 响应结构: [[["译文", "原文", ...], ...], ...]
            let result = segments.compactMap { segment -> String? in
                (segment as? [Any])?.first as? String
            }.joined()
            completion(result.isEmpty ? nil : result, result.isEmpty ? .failed : nil)
        }
    }

    /// MyMemory 免费接口（Google 不可达时的兜底）
    private func myMemoryTranslate(_ text: String, cancellation: TranslationRequest,
                                   completion: @escaping (String?, TranslateError?) -> Void) {
        // langpair 里的 | 必须 URL 编码（%7C），否则服务器解析失败导致不翻译
        let langPair = containsChinese(text) ? "zh-CN%7Cen" : "en%7Czh-CN"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(langPair)") else {
            completion(nil, .failed)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        perform(request, cancellation: cancellation) { data, error in
            if let error = error as? URLError, Self.isNetworkError(error) {
                completion(nil, .noNetwork)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["responseData"] as? [String: Any],
                  let rawTranslated = responseData["translatedText"] as? String else {
                completion(nil, .failed)
                return
            }
            // MyMemory 有时返回 URL 编码文本（%E5%...），需要解码
            let translated = rawTranslated.removingPercentEncoding ?? rawTranslated
            guard !translated.isEmpty else {
                completion(nil, .failed)
                return
            }
            completion(translated, nil)
        }
    }

    /// 所有回调在主队列汇总，避免逐句并发写同一个数组；取消后不启动后备接口。
    private func perform(_ request: URLRequest, cancellation: TranslationRequest,
                         completion: @escaping (Data?, Error?) -> Void) {
        guard !cancellation.isCancelled else { completion(nil, URLError(.cancelled)); return }
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard !cancellation.isCancelled else { completion(nil, URLError(.cancelled)); return }
                if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                    completion(nil, URLError(.badServerResponse))
                } else {
                    completion(data, error)
                }
            }
        }
        cancellation.onCancel { [weak task] in task?.cancel() }
        task.resume()
    }

    /// 判断是否为网络不可达类错误
    private static func isNetworkError(_ error: URLError) -> Bool {
        error.code == .notConnectedToInternet || error.code == .networkConnectionLost
            || error.code == .timedOut || error.code == .cannotFindHost
            || error.code == .cannotConnectToHost
    }

    /// 文本清洗：修复 PDF/HTML 复制产生的常见问题
    /// - 连字符断行（word-\n → word）
    /// - 行内多余空白（多空格/制表 → 单空格）
    /// - 连续换行合并（多段落 → 单换行分隔）
    static func normalizeText(_ text: String) -> String {
        let result = text.replacingOccurrences(of: "-\n", with: "")
        // 每行尾部多余空白去除 + 行内空白合并
        var out = ""
        var pendingSpace = false
        for ch in result {
            if ch == " " || ch == "\t" {
                pendingSpace = true
            } else if ch == "\n" {
                pendingSpace = false
                out.append("\n")
            } else {
                if pendingSpace {
                    if !out.isEmpty, !out.hasSuffix("\n") { out.append(" ") }
                    pendingSpace = false
                }
                out.append(ch)
            }
        }
        // 连续换行合并为单个
        while out.contains("\n\n") { out = out.replacingOccurrences(of: "\n\n", with: "\n") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 按句子切分文本（句号/问号/感叹号/分号/换行），每句一行
    /// 先清洗（修复 PDF 连字符断行、多余空白），保证段落识别正确
    func splitSentences(_ text: String) -> [String] {
        let normalized = Self.normalizeText(text)
        var sentences: [String] = []
        var current = ""
        for ch in normalized {
            current.append(ch)
            if "。！？!?.;；\n".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }

    /// 逐句翻译（保持句序对应，供双语对照高亮使用）
    /// 每批最多 12 句并发（防接口限流/超时），分批串行直到全部译完，不再截断
    /// 失败时 completion(nil, error)
    func translateSentences(_ text: String, request: TranslationRequest = TranslationRequest(),
                            completion: @escaping ([String]?, TranslateError?) -> Void) {
        guard !request.isCancelled else { return }
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else {
            completion(nil, .failed)
            return
        }
        let batchSize = 12
        var results = [String?](repeating: nil, count: sentences.count)
        var firstError: TranslateError?
        var batchIndex = 0

        func translateNextBatch() {
            guard !request.isCancelled else { return }
            let start = batchIndex * batchSize
            guard start < sentences.count else {
                // 全部批次完成
                let translated = results.compactMap { $0 }
                if translated.count == sentences.count {
                    completion(translated, nil)
                } else {
                    completion(nil, firstError ?? .failed)
                }
                return
            }
            let end = min(start + batchSize, sentences.count)
            let group = DispatchGroup()
            for i in start..<end {
                group.enter()
                translate(sentences[i], request: request) { result, error in
                    results[i] = result
                    if let error, firstError == nil { firstError = error }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                batchIndex += 1
                translateNextBatch()   // 继续下一批
            }
        }
        DispatchQueue.main.async { translateNextBatch() }
    }

    /// 文本是否包含中文（用于决定翻译方向）
    private func containsChinese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}
