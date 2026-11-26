import Foundation

struct AIContentPart: Codable {
    let type: String
    let text: String?
    let imageURL: AIImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    init(type: String, text: String?, imageURL: AIImageURL?) {
        self.type = type
        self.text = text
        self.imageURL = imageURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imageURL = try container.decodeIfPresent(AIImageURL.self, forKey: .imageURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
    }

    static func text(_ value: String) -> AIContentPart {
        AIContentPart(type: "text", text: value, imageURL: nil)
    }

    static func imageBase64(_ data: Data) -> AIContentPart {
        AIContentPart(
            type: "image_url",
            text: nil,
            imageURL: AIImageURL(url: "data:image/jpeg;base64,\(data.base64EncodedString())")
        )
    }
}

struct AIImageURL: Codable {
    let url: String
}

struct AIChatMessage: Codable {
    let role: String
    let content: [AIContentPart]
}

private struct AIChatRequest: Codable {
    let model: String
    let messages: [AIChatMessage]
    let temperature: Double
    let stream: Bool
}

private struct AIChatResponse: Decodable {
    let choices: [AIChoice]
}

private struct AIChoice: Decodable {
    let message: AIResponseMessage
}

private struct AIResponseMessage: Decodable {
    let content: String

    enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = text
        } else if let parts = try? container.decode([AIContentPart].self, forKey: .content) {
            content = parts.compactMap { $0.text }.joined()
        } else {
            content = ""
        }
    }
}

private struct AIErrorEnvelope: Decodable {
    let error: AIErrorDetail?
}

private struct AIErrorDetail: Decodable {
    let message: String?
}

final class OpenAICompatibleClient {
    static let shared = OpenAICompatibleClient()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    func chat(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [AIChatMessage]
    ) async throws -> String {
        let endpoint = URL(string: baseURL)?.appendingPathComponent("chat/completions")
        guard let endpoint else { throw AppError.aiNotConfigured }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AIChatRequest(model: model, messages: messages, temperature: 0.2, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.aiInvalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(AIErrorEnvelope.self, from: data))?.error?.message
                ?? String(data: data, encoding: .utf8)
                ?? "无错误详情"
            throw AppError.aiHTTP(http.statusCode, detail)
        }

        guard let decoded = try? JSONDecoder().decode(AIChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.aiInvalidResponse
        }
        return content
    }
}
