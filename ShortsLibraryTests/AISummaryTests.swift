import XCTest
@testable import ShortsLibrary

final class AISummaryTests: XCTestCase {
    func testPresetRegistry() {
        XCTAssertEqual(AIProviderPresets.defaultID, "qwen")
        XCTAssertEqual(AIProviderPresets.preset(id: "qwen")?.defaultModel, "qwen3.8-omni-flash")
        XCTAssertEqual(AIProviderPresets.preset(id: "doubao")?.requiresCustomModel, true)
        XCTAssertEqual(AIProviderPresets.preset(id: "custom")?.requiresCustomModel, true)
        XCTAssertNil(AIProviderPresets.preset(id: "unknown"))
    }

    func testVisionModelFallback() {
        XCTAssertTrue(AISettings.supportsImages(providerID: "qwen", model: "qwen3.8-omni-flash"))
        XCTAssertFalse(AISettings.supportsImages(providerID: "qwen", model: "qwen4-max"))
        XCTAssertFalse(AISettings.supportsImages(providerID: "qwen", model: "deepseek-v4.1-flash-1017"))
        XCTAssertFalse(AISettings.supportsImages(providerID: "qwen", model: "kimi-k3.1-pro"))
        XCTAssertTrue(AISettings.supportsImages(providerID: "openai", model: "gpt-4o"))
    }

    func testParseSummaryJSON() {
        let raw = """
        以下是结果：
        ```json
        {"summary":"一个测试摘要","highlights":["看点一","看点二"],"tags":["标签"],"contentType":"教程","tone":"轻松"}
        ```
        """
        let result = AISummaryService.parseSummaryText(raw)
        XCTAssertEqual(result.summary, "一个测试摘要")
        XCTAssertEqual(result.highlights, ["看点一", "看点二"])
        XCTAssertEqual(result.tags, ["标签"])
        XCTAssertEqual(result.contentType, "教程")
        XCTAssertEqual(result.tone, "轻松")
    }

    func testParseSummaryFallback() {
        let result = AISummaryService.parseSummaryText("模型没有返回 JSON，只返回了普通文本。")
        XCTAssertEqual(result.summary, "模型没有返回 JSON，只返回了普通文本。")
        XCTAssertTrue(result.highlights.isEmpty)
    }
}
