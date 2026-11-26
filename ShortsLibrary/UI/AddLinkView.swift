import SwiftUI
import SwiftData

struct AddLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let initialURL: URL?

    @FocusState private var inputFocused: Bool

    @State private var text = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var detectedPlatform: String? {
        LinkIngestService.detectPlatform(in: text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 90)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($inputFocused)
                        .toolbar {
                            ToolbarItem(placement: .keyboard) {
                                Button("完成") { inputFocused = false }
                            }
                        }
                } header: {
                    Text("分享文案或链接")
                } footer: {
                    if let detectedPlatform {
                        Text("已识别：\(detectedPlatform)。解析后任务会进入下载队列。")
                            .foregroundStyle(.green)
                    } else {
                        Text("支持抖音、快手、小红书、B站。粘贴整段分享文案即可自动识别。")
                    }
                }

                if isWorking {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在解析公开页面…")
                        }
                    }
                }
            }
            .navigationTitle("添加链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("解析并入队") {
                        Task { await submit() }
                    }
                    .disabled(isWorking)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("知道了") { self.errorMessage = nil }
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .onAppear {
                if let initialURL {
                    text = initialURL.absoluteString
                }
            }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await LinkIngestService.ingest(text: text, modelContext: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
