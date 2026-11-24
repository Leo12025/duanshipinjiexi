import SwiftUI
import SwiftData

struct AddLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let initialURL: URL?

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
                } header: {
                    Text("分享文案或链接")
                } footer: {
                    if let detectedPlatform {
                        Text("已识别：\(detectedPlatform)。解析后任务会进入下载队列。")
                            .foregroundStyle(.green)
                    } else {
                        Text("支持抖音、快手、小红书。粘贴整段分享文案即可自动识别。")
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
            .alert("提示", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
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
            if let initialURL {
                try await LinkIngestService.ingest(url: initialURL, modelContext: modelContext)
            } else {
                try await LinkIngestService.ingest(text: text, modelContext: modelContext)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
