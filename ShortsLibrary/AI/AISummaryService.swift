import Foundation
import SwiftData

struct AISummaryResult: Codable, Equatable {
    var summary: String
    var highlights: [String]
    var tags: [String]
    var contentType: String
    var tone: String

    init(summary: String = "", highlights: [String] = [], tags: [String] = [], contentType: String = "", tone: String = "") {
        self.summary = summary
        self.highlights = highlights
        self.tags = tags
        self.contentType = contentType
        self.tone = tone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        highlights = try container.decodeIfPresent([String].self, forKey: .highlights) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        tone = try container.decodeIfPresent(String.self, forKey: .tone) ?? ""
    }
}

@MainActor
final class AISummaryService {
    static let shared = AISummaryService()
    private static var scheduled: Set<PersistentIdentifier> = []

    private init() {}

    private static let systemPrompt = """
    你是短视频内容分析助手。请结合用户提供的标题、文案、可选转写稿和视频关键帧，输出严格的 JSON，不要输出 Markdown 代码块或解释文字。字段如下：
    {"summary":"一到两句话概括视频内容","highlights":["3到5条关键看点"],"tags":["3到6个短标签"],"contentType":"内容类型，例如教程/测评/剧情/资讯/美食/生活/其他","tone":"情绪基调，例如轻松/严肃/搞笑/专业/治愈"}
    只输出 JSON 本身。
    """

    func testConnection() async throws -> String {
        let config = try AISettings.resolved()
        let messages = [
            AIChatMessage(role: "user", content: [.text("只回复 OK 两个字母。")])
        ]
        let raw = try await OpenAICompatibleClient.shared.chat(
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            model: config.model,
            messages: messages
        )
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func summarize(
        item: LibraryItem,
        modelContext: ModelContext,
        force: Bool = false
    ) async throws -> AISummaryResult {
        guard AISettings.allowUpload else { throw AppError.aiUploadDisabled }

        if !force, item.aiStatus == "done", !item.aiSummary.isEmpty {
            return AISummaryResult(
                summary: item.aiSummary,
                highlights: item.aiHighlights,
                tags: item.aiTags,
                contentType: item.aiContentType ?? "",
                tone: item.aiTone ?? ""
            )
        }

        let config = try AISettings.resolved()
        item.aiStatus = "processing"
        item.aiError = nil
        try? modelContext.save()

        do {
            let images = await imageData(for: item)
            guard !images.isEmpty else { throw AppError.aiNoMedia }

            let text = Self.userText(for: item)
            var parts: [AIContentPart] = [.text(text)]
            for data in images {
                parts.append(.imageBase64(data))
            }
            let messages = [
                AIChatMessage(role: "system", content: [.text(Self.systemPrompt)]),
                AIChatMessage(role: "user", content: parts)
            ]

            let raw = try await OpenAICompatibleClient.shared.chat(
                baseURL: config.baseURL,
                apiKey: config.apiKey,
                model: config.model,
                messages: messages
            )
            let result = Self.parseSummaryText(raw)

            item.aiSummary = result.summary
            item.aiHighlights = result.highlights
            item.aiTags = result.tags
            item.aiContentType = result.contentType
            item.aiTone = result.tone
            item.aiProviderID = config.providerID
            item.aiModel = config.model
            item.aiStatus = "done"
            item.aiError = nil
            item.aiUpdatedAt = Date()
            item.updatedAt = Date()
            try? modelContext.save()
            return result
        } catch {
            item.aiStatus = "failed"
            item.aiError = error.localizedDescription
            item.aiUpdatedAt = Date()
            try? modelContext.save()
            throw error
        }
    }

    func scheduleAutoSummaryIfNeeded(item: LibraryItem, context: ModelContext) {
        guard AISettings.autoSummarize, AISettings.allowUpload else { return }
        guard item.aiStatus != "done", item.aiSummary.isEmpty else { return }
        let identifier = item.persistentModelID
        guard Self.scheduled.insert(identifier).inserted else { return }

        Task { @MainActor in
            defer { Self.scheduled.remove(identifier) }
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !item.isTrashed, item.aiStatus != "done" else { return }
                if Self.hasUsableMedia(item) {
                    _ = try? await Self.shared.summarize(item: item, modelContext: context)
                    return
                }
            }
        }
    }

    nonisolated static func parseSummaryText(_ raw: String) -> AISummaryResult {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonStart = text.range(of: "```json"),
           let jsonEnd = text.range(of: "```", range: jsonStart.upperBound..<text.endIndex) {
            text = String(text[jsonStart.upperBound..<jsonEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.hasPrefix("```") {
            let body = text.dropFirst(3)
            if let end = body.range(of: "```") {
                text = String(body[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") {
            text = String(text[first...last])
        }
        if let data = text.data(using: .utf8),
           let result = try? JSONDecoder().decode(AISummaryResult.self, from: data),
           !result.summary.isEmpty {
            return result
        }
        return AISummaryResult(summary: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func hasUsableMedia(_ item: LibraryItem) -> Bool {
        if item.kindEnum == .video, item.videoFile?.existsOnDisk == true { return true }
        if item.imageFiles.contains(where: { $0.existsOnDisk }) { return true }
        if item.coverFile?.existsOnDisk == true { return true }
        return false
    }

    private static func userText(for item: LibraryItem) -> String {
        var lines: [String] = [
            "标题：\(item.title)",
            "语言：\(AISettings.summaryLanguage)",
            "摘要风格：\(AISettings.summaryStyle)"
        ]
        if let author = item.author, !author.isEmpty {
            lines.append("作者：\(author)")
        }
        if let caption = item.caption, !caption.isEmpty {
            lines.append("平台文案：\(caption)")
        }
        if let transcript = item.aiTranscript, !transcript.isEmpty {
            lines.append("音频转写稿：\(transcript)")
        }
        lines.append("请结合后面的关键帧画面，输出 JSON。")
        return lines.joined(separator: "\n")
    }

    private func imageData(for item: LibraryItem) async -> [Data] {
        let maxSize = AISettings.imageMaxSize
        let count = AISettings.frameCount
        var results: [Data] = []

        if item.kindEnum == .video,
           let video = item.videoFile,
           video.existsOnDisk {
            results = await VideoFrameExtractor.frames(
                from: video.fileURL,
                count: count,
                maxSize: maxSize
            )
        }

        if results.isEmpty {
            var files = item.imageFiles.filter { $0.existsOnDisk }
            if let cover = item.coverFile, cover.existsOnDisk, !files.contains(where: { $0.relativePath == cover.relativePath }) {
                files.insert(cover, at: 0)
            }
            for file in files.prefix(count) {
                guard let image = ThumbnailCache.image(for: file.fileURL, maxPixel: maxSize),
                      let data = image.jpegData(compressionQuality: 0.72) else { continue }
                results.append(data)
            }
        }
        return results
    }
}
