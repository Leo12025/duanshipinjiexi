import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AISettingsKey.providerID) private var providerID = AIProviderPresets.defaultID
    @AppStorage(AISettingsKey.model) private var model = AIProviderPresets.qwen.defaultModel
    @AppStorage(AISettingsKey.customBaseURL) private var customBaseURL = ""
    @AppStorage(AISettingsKey.customModel) private var customModel = ""
    @AppStorage(AISettingsKey.allowUpload) private var allowUpload = false
    @AppStorage(AISettingsKey.autoSummarize) private var autoSummarize = false
    @AppStorage(AISettingsKey.frameCount) private var frameCount = 5
    @AppStorage(AISettingsKey.imageMaxSize) private var imageMaxSize = 1024
    @AppStorage(AISettingsKey.summaryLanguage) private var summaryLanguage = "简体中文"
    @AppStorage(AISettingsKey.summaryStyle) private var summaryStyle = "简洁摘要"

    @State private var apiKey = ""
    @State private var message: String?
    @State private var isTesting = false

    private var preset: AIProviderPreset {
        AIProviderPresets.preset(id: providerID) ?? AIProviderPresets.custom
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("服务商", selection: $providerID) {
                        ForEach(AIProviderPresets.all) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    if !preset.models.isEmpty {
                        Picker("优选模型", selection: $model) {
                            ForEach(preset.models, id: \.self) { item in
                                Text(item).tag(item)
                            }
                        }
                        if !AISettings.supportsImages(providerID: providerID, model: model) {
                            Text("当前为纯文本模型，不会发送关键帧画面。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if preset.id == AIProviderPresets.custom.id {
                        TextField("Base URL，例如 https://api.example.com/v1", text: $customBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if preset.requiresCustomModel {
                        TextField(preset.id == AIProviderPresets.custom.id ? "模型名称" : "模型 ID / endpoint ID", text: $customModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SecureField("API Key", text: apiKeyBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(preset.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("服务商与模型")
                }

                Section {
                    Toggle("允许上传画面与文案", isOn: $allowUpload)
                    Toggle("下载完成后自动总结", isOn: $autoSummarize)
                        .disabled(!allowUpload)
                    Stepper(value: $frameCount, in: 1...12) {
                        Text("关键帧数量：\(frameCount)")
                    }
                    Picker("图片长边", selection: $imageMaxSize) {
                        ForEach([640, 768, 1024, 1280], id: \.self) { value in
                            Text("\(value) px").tag(value)
                        }
                    }
                    Picker("摘要语言", selection: $summaryLanguage) {
                        ForEach(["简体中文", "English", "日本語"], id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    Picker("摘要风格", selection: $summaryStyle) {
                        ForEach(["简洁摘要", "详细解读", "只看干货"], id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                } header: {
                    Text("解析设置")
                } footer: {
                    Text("开启上传后，标题、平台文案、封面和关键帧会发送到所选服务商。API Key 仅保存在本机 Keychain，不会写入资料库备份。")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Label("测试连接", systemImage: "network")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(message.hasPrefix("连接成功") ? .green : .red)
                    }
                } footer: {
                    Text("测试会发送一条最简文本请求，用于验证地址、模型和 Key 是否可用。")
                }
            }
            .navigationTitle("AI 解析设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                if !preset.models.contains(model) { model = preset.defaultModel }
                loadAPIKey(for: providerID)
            }
            .onChange(of: providerID) { _, newValue in
                if let next = AIProviderPresets.preset(id: newValue) {
                    model = next.defaultModel
                }
                loadAPIKey(for: newValue)
                message = nil
            }
            .onChange(of: allowUpload) { _, newValue in
                if !newValue { autoSummarize = false }
            }
        }
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKey },
            set: { newValue in
                apiKey = newValue
                KeychainStore.setString(newValue, for: AISettingsKey.keychainKey(for: providerID))
            }
        )
    }

    private func loadAPIKey(for id: String) {
        apiKey = KeychainStore.string(for: AISettingsKey.keychainKey(for: id)) ?? ""
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let reply = try await AISummaryService.shared.testConnection()
            message = "连接成功：\(String(reply.prefix(40)))"
        } catch {
            message = error.localizedDescription
        }
    }
}
