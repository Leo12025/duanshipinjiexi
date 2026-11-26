import Foundation

struct AIProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let models: [String]
    let defaultModel: String
    let note: String
    let requiresCustomModel: Bool
}

enum AIProviderPresets {
    static let qwen = AIProviderPreset(
        id: "qwen",
        name: "阿里云百炼 Qwen-VL",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        models: ["qwen3-vl-plus", "qwen3-vl-max", "qwen3-vl-flash", "qwen-vl-max", "qwen-vl-plus"],
        defaultModel: "qwen3-vl-plus",
        note: "中文短视频场景优选，支持图片与视频帧。推荐使用 qwen3-vl-plus，复杂画面再切 Max。",
        requiresCustomModel: false
    )

    static let doubao = AIProviderPreset(
        id: "doubao",
        name: "火山方舟豆包视觉",
        baseURL: "https://ark.cn-beijing.volces.com/api/v3",
        models: [],
        defaultModel: "",
        note: "模型 ID 为控制台创建的视觉模型 endpoint ID，请填入下方自定义模型框。",
        requiresCustomModel: true
    )

    static let zhipu = AIProviderPreset(
        id: "zhipu",
        name: "智谱 BigModel",
        baseURL: "https://open.bigmodel.cn/api/paas/v4",
        models: ["glm-4.5v", "glm-4v-plus"],
        defaultModel: "glm-4.5v",
        note: "模型名称以控制台当前可用版本为准。",
        requiresCustomModel: false
    )

    static let kimi = AIProviderPreset(
        id: "kimi",
        name: "Moonshot Kimi 视觉",
        baseURL: "https://api.moonshot.cn/v1",
        models: [],
        defaultModel: "",
        note: "视觉模型名称以控制台为准，请填入下方自定义模型框。",
        requiresCustomModel: true
    )

    static let openai = AIProviderPreset(
        id: "openai",
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        models: ["gpt-4o", "gpt-4o-mini"],
        defaultModel: "gpt-4o",
        note: "海外服务，请自行确认网络与数据合规。",
        requiresCustomModel: false
    )

    static let custom = AIProviderPreset(
        id: "custom",
        name: "自定义 OpenAI 兼容接口",
        baseURL: "",
        models: [],
        defaultModel: "",
        note: "填写任意兼容 Chat Completions 的服务地址与模型名。地址应包含 /v1 前缀。",
        requiresCustomModel: true
    )

    static let all: [AIProviderPreset] = [qwen, doubao, zhipu, kimi, openai, custom]
    static let defaultID = qwen.id

    static func preset(id: String) -> AIProviderPreset? {
        all.first { $0.id == id }
    }
}

enum AISettingsKey {
    static let providerID = "shorts.ai.providerID"
    static let model = "shorts.ai.model"
    static let customBaseURL = "shorts.ai.customBaseURL"
    static let customModel = "shorts.ai.customModel"
    static let allowUpload = "shorts.ai.allowUpload"
    static let autoSummarize = "shorts.ai.autoSummarize"
    static let frameCount = "shorts.ai.frameCount"
    static let imageMaxSize = "shorts.ai.imageMaxSize"
    static let summaryLanguage = "shorts.ai.summaryLanguage"
    static let summaryStyle = "shorts.ai.summaryStyle"

    static func keychainKey(for providerID: String) -> String {
        "shorts.ai.key.\(providerID)"
    }
}

enum AISettings {
    static var allowUpload: Bool {
        UserDefaults.standard.bool(forKey: AISettingsKey.allowUpload)
    }

    static var autoSummarize: Bool {
        UserDefaults.standard.bool(forKey: AISettingsKey.autoSummarize)
    }

    static var frameCount: Int {
        let value = UserDefaults.standard.integer(forKey: AISettingsKey.frameCount)
        return (1...12).contains(value) ? value : 5
    }

    static var imageMaxSize: Int {
        let value = UserDefaults.standard.integer(forKey: AISettingsKey.imageMaxSize)
        return [640, 768, 1024, 1280].contains(value) ? value : 1024
    }

    static var summaryLanguage: String {
        let value = UserDefaults.standard.string(forKey: AISettingsKey.summaryLanguage) ?? ""
        return value.isEmpty ? "简体中文" : value
    }

    static var summaryStyle: String {
        let value = UserDefaults.standard.string(forKey: AISettingsKey.summaryStyle) ?? ""
        return value.isEmpty ? "简洁摘要" : value
    }

    static func resolved() throws -> (providerID: String, model: String, baseURL: String, apiKey: String) {
        let defaults = UserDefaults.standard
        let providerID = defaults.string(forKey: AISettingsKey.providerID) ?? AIProviderPresets.defaultID
        let preset = AIProviderPresets.preset(id: providerID) ?? AIProviderPresets.custom

        let baseURL: String
        let model: String
        if preset.id == AIProviderPresets.custom.id {
            baseURL = defaults.string(forKey: AISettingsKey.customBaseURL) ?? ""
            model = defaults.string(forKey: AISettingsKey.customModel) ?? ""
        } else if preset.requiresCustomModel {
            baseURL = preset.baseURL
            model = defaults.string(forKey: AISettingsKey.customModel) ?? ""
        } else {
            baseURL = preset.baseURL
            let saved = defaults.string(forKey: AISettingsKey.model) ?? ""
            model = saved.isEmpty ? preset.defaultModel : saved
        }

        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = KeychainStore.string(for: AISettingsKey.keychainKey(for: providerID)) ?? ""

        guard !trimmedBaseURL.isEmpty, !trimmedModel.isEmpty, !apiKey.isEmpty else {
            throw AppError.aiNotConfigured
        }
        return (providerID, trimmedModel, trimmedBaseURL, apiKey)
    }
}
