import Foundation

@main
struct APIUsageTests {
    static func main() throws {
        try testProviderBasedPartition()
        try testScannerSeparatesSameModelByProvider()
        try testOpenRouterPricingCatalog()
        try testDeepSeekPrices()
        try testAstraPricingAndFallback()
        try testUnknownModelsRemainUnpriced()
        try testImportCanonicalizationAndWindowFiltering()
        try testVisibleSourceSelectorOptions()
        print("APIUsageTests passed")
    }

    private static func testProviderBasedPartition() throws {
        for model in [
            "deepseek-v4-flash",
            "deepseek/deepseek-v4-flash",
            "deepseek-v4-pro",
            "deepseek-chat",
            "deepseek-reasoner"
        ] {
            try require(CodexUsagePartition.api.includes(modelName: model), "\(model) should be API-billed")
            try require(!CodexUsagePartition.codex.includes(modelName: model), "\(model) must not remain in Codex")
        }
        try require(CodexUsagePartition.api.includes(modelName: "gpt-5.6-sol", provider: "openrouter"), "OpenRouter provider must be API-billed even when the model name overlaps Codex")
        try require(CodexUsagePartition.api.includes(modelName: "anthropic/claude-sonnet-5", provider: "openai"), "provider-qualified model IDs must be API-billed")
        try require(CodexUsagePartition.api.includes(modelName: "gemini-3-pro", provider: "custom-gateway"), "custom non-subscription providers must be API-billed")
        try require(CodexUsagePartition.codex.includes(modelName: "gpt-5.6-sol", provider: "openai"), "OpenAI Codex subscription model should stay in Codex")
    }

    private static func testScannerSeparatesSameModelByProvider() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-provider-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let subscriptionRoot = root.appendingPathComponent("subscription", isDirectory: true)
        let apiRoot = root.appendingPathComponent("api", isDirectory: true)
        try FileManager.default.createDirectory(at: subscriptionRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apiRoot, withIntermediateDirectories: true)
        try writeRollout(root: subscriptionRoot, name: "subscription", provider: "openai", model: "gpt-5.6-sol", total: 100)
        try writeRollout(root: subscriptionRoot, name: "openrouter", provider: "openrouter", model: "gpt-5.6-sol", total: 250)
        try writeRollout(root: apiRoot, name: "explicit-api-root", provider: "openai", model: "gpt-5.6-sol", total: 400)

        let scanner = CodexTokenScanner(rootURLs: [subscriptionRoot, apiRoot], apiRootURLs: [apiRoot])
        let codex = scanner.scan(days: 7, partition: .codex)
        let api = scanner.scan(days: 7, partition: .api)
        let all = scanner.scan(days: 7, partition: .all)
        try require(codex.usage.total == 100, "openai subscription event must remain in Codex")
        try require(api.usage.total == 650, "openrouter provider and explicit API root events must move to API")
        try require(all.usage.total == codex.usage.total + api.usage.total, "provider partitions must merge exactly once")
    }

    private static func testOpenRouterPricingCatalog() throws {
        let fixture = """
        {"data":[{"id":"anthropic/claude-test","canonical_slug":"anthropic/claude-test-20260806","pricing":{"prompt":"0.000003","completion":"0.000015","input_cache_read":"0.0000003","input_cache_write":"0.00000375"}}]}
        """
        guard let parsed = OpenRouterPricingCatalog.parseCatalog(Data(fixture.utf8)),
              let rate = parsed.rates["anthropic/claude-test"] else {
            throw TestFailure(message: "OpenRouter fixture should parse")
        }
        try require(parsed.modelCount == 1, "catalog should retain the provider model count")
        try require(rate == APIModelRate(inputPerMillionUSD: 3, cachedInputPerMillionUSD: 0.3, outputPerMillionUSD: 15, cacheCreationInputPerMillionUSD: 3.75), "per-token OpenRouter prices should convert to per-million rates")
    }

    private static func testDeepSeekPrices() throws {
        let flash = APICostEstimator.estimate(
            usage: Usage(input: 1_000_000, output: 1_000_000, total: 2_000_000),
            modelName: "deepseek-v4-flash"
        )
        try require(abs(flash.usdValue - 0.42) < 0.000_000_1, "Flash input/output price should match DeepSeek official pricing")

        let pro = APICostEstimator.estimate(
            usage: Usage(input: 1_000_000, cachedInput: 1_000_000, output: 1_000_000, total: 2_000_000),
            modelName: "deepseek-v4-pro"
        )
        try require(abs(pro.usdValue - 0.873625) < 0.000_000_1, "Pro cached-input/output price should match DeepSeek official pricing")
    }

    private static func testUnknownModelsRemainUnpriced() throws {
        let report = TokenReport(
            usage: Usage(input: 1_000, total: 1_000),
            modelBreakdown: [ModelUsage(name: "unknown-provider/model", usage: Usage(input: 1_000, total: 1_000), events: 1, sessions: 1)]
        )
        let estimate = APICostEstimator.estimate(report: report)
        try require(estimate.usdValue == 0, "unknown models must not inherit a default price")
        try require(estimate.coveragePercent == 0, "unknown models must reduce price coverage")
    }

    private static func testAstraPricingAndFallback() throws {
        // Use the Work alias to exercise built-in prices without a live catalog.
        let usage = Usage(input: 300_000, cachedInput: 100_000, cacheCreationInput: 100_000, output: 100_000, reasoningOutput: 50_000, total: 400_000)
        let estimate = APICostEstimator.estimate(usage: usage, modelName: "gpt-6-astra-wm")
        try require(abs(estimate.usdValue - 7.35) < 0.000_000_1, "Astra must price fresh/cache-read/cache-write/output separately without double-counting reasoning")
        try require(estimate.coveragePercent == 100, "Astra tokens should be priced")
        for name in ["GPT-6 Astra", "gpt-6-astra", "openai/gpt-6-astra"] {
            try require(APICostEstimator.estimate(usage: usage, modelName: name).coveragePercent == 100, "Astra alias should be priced: \(name)")
        }
        try require(APICostEstimator.estimate(usage: usage, modelName: "gpt-6-unknown").coveragePercent == 0, "Unknown GPT-6 models must not inherit Astra prices")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("astra-catalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = CodexModelRoutingStore(codexHomeURL: root)
        try require(store.loadModels().first?.slug == "gpt-6-astra", "Offline model list should offer Astra")
        let fixture = """
        {"models":[{"slug":"gpt-6-astra","display_name":"GPT-6-Astra","visibility":"list","supported_reasoning_levels":[{"effort":"high","description":"High"},{"effort":"ultra","description":"Ultra"}]}]}
        """
        try Data(fixture.utf8).write(to: root.appendingPathComponent("models_cache.json"))
        try require(store.loadModels().first?.supportedReasoningEfforts == ["high", "ultra"], "Live Codex catalog must remain authoritative")
    }

    private static func testImportCanonicalizationAndWindowFiltering() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("api-usage-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("api-usage.json")
        let fixture = """
        {
          "by_day": [
            {
              "day": "2026-08-01",
              "usage": {"input_tokens": 1000, "output_tokens": 100, "total_tokens": 1100},
              "models": [
                {"model": "deepseek-chat", "usage": {"input_tokens": 600, "output_tokens": 60, "total_tokens": 660}},
                {"model": "deepseek-reasoner", "usage": {"input_tokens": 400, "output_tokens": 40, "total_tokens": 440}}
              ]
            },
            {
              "day": "2026-08-06",
              "usage": {"input_tokens": 2000, "output_tokens": 200, "total_tokens": 2200},
              "models": [
                {"model": "deepseek/deepseek-v4-pro", "usage": {"input_tokens": 2000, "output_tokens": 200, "total_tokens": 2200}}
              ]
            }
          ]
        }
        """
        try Data(fixture.utf8).write(to: url, options: .atomic)

        let full = ExternalAPIUsageStore.readReport(url: url)
        try require(full.usage.total == 3_300, "full import should aggregate every day")
        try require(full.modelBreakdown.map(\.name).sorted() == ["deepseek-v4-flash", "deepseek-v4-pro"], "legacy aliases and provider prefixes should canonicalize")

        let now = ISO8601DateFormatter().date(from: "2026-08-06T12:00:00Z")!
        let day = ExternalAPIUsageStore.readReport(window: .day, url: url, now: now)
        try require(day.usage.total == 2_200, "24h import should exclude older day buckets")
        try require(day.modelBreakdown.map(\.name) == ["deepseek-v4-pro"], "24h model totals should come from selected days")

        let week = ExternalAPIUsageStore.readReport(window: .week, url: url, now: now)
        try require(week.usage.total == 3_300, "7d import should include both fixture days")
    }

    private static func testVisibleSourceSelectorOptions() throws {
        try require(
            QuotaViewOption.selectorOptions(for: [.api]) == [.api],
            "a single API source should not show a redundant total option"
        )
        try require(
            QuotaViewOption.selectorOptions(for: [.claude, .api]) == [.all, .claude, .api],
            "Claude + API should show a total containing only those sources"
        )
        try require(
            QuotaViewOption.selectorOptions(for: [.api, .codex, .claude]) == [.all, .codex, .claude, .api],
            "source selector order should remain stable regardless of stored order"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure(message: message)
        }
    }

    private static func writeRollout(root: URL, name: String, provider: String, model: String, total: Int64) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let rows = [
            "{\"timestamp\":\"\(timestamp)\",\"type\":\"session_meta\",\"payload\":{\"model_provider\":\"\(provider)\"}}",
            "{\"timestamp\":\"\(timestamp)\",\"type\":\"turn_context\",\"payload\":{\"model\":\"\(model)\",\"effort\":\"high\"}}",
            "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"input_tokens\":\(total),\"cached_input_tokens\":0,\"output_tokens\":0,\"reasoning_output_tokens\":0,\"total_tokens\":\(total)}}"
        ]
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(
            to: root.appendingPathComponent("rollout-\(name).jsonl"),
            options: .atomic
        )
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
