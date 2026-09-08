import Foundation

enum TaskCostEstimator {
    private struct PricingCache: Decodable {
        let version: Int
        let rates: [String: APIModelRate]
    }

    private struct ManualPriceRule: Decodable {
        let model: String
        let inputPerMillionUSD: Double
        let cachedInputPerMillionUSD: Double
        let outputPerMillionUSD: Double
    }

    private static let cachedRates: [String: APIModelRate] = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = support.appendingPathComponent("Codex Token Meter", isDirectory: true)

        var result: [String: APIModelRate] = [:]
        let cacheURL = directory.appendingPathComponent("openrouter-model-pricing.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(PricingCache.self, from: data),
           cache.version == 1 {
            result.merge(cache.rates) { _, newest in newest }
        }

        let manualURL = directory.appendingPathComponent("manual-model-pricing.json")
        if let data = try? Data(contentsOf: manualURL),
           let rules = try? JSONDecoder().decode([ManualPriceRule].self, from: data) {
            for rule in rules {
                result[normalizedModel(rule.model)] = APIModelRate(
                    inputPerMillionUSD: rule.inputPerMillionUSD,
                    cachedInputPerMillionUSD: rule.cachedInputPerMillionUSD,
                    outputPerMillionUSD: rule.outputPerMillionUSD
                )
            }
        }
        return result
    }()

    static func usdValue(for item: CodexThreadItem) -> Double? {
        guard item.tokenBreakdown.hasDetailedCounters,
              let model = item.model,
              let rate = rate(for: model) else {
            return nil
        }
        let input = max(0, item.tokenBreakdown.input)
        let cachedInput = max(0, min(item.tokenBreakdown.cachedInput, input))
        let freshInput = input - cachedInput
        // Codex output already includes reasoning. OpenCode reports reasoning as
        // a separate billed output component, which is visible through total.
        let inferredOutput = max(0, item.tokenBreakdown.total - input)
        let billedOutput = max(item.tokenBreakdown.output, inferredOutput)
        return (
            Double(freshInput) * rate.inputPerMillionUSD
                + Double(cachedInput) * rate.cachedInputPerMillionUSD
                + Double(billedOutput) * rate.outputPerMillionUSD
        ) / 1_000_000
    }

    static func displayUSD(_ value: Double) -> String {
        guard value > 0 else { return "USD 0.00" }
        if value < 0.0001 { return "< USD 0.0001" }
        if value < 1 { return String(format: "USD %.4f", value) }
        return String(format: "USD %.2f", value)
    }

    private static func rate(for modelName: String) -> APIModelRate? {
        let key = normalizedModel(modelName)
        if let exact = cachedRates[key] { return exact }
        if key.hasSuffix("-latest"), let base = cachedRates[String(key.dropLast("-latest".count))] {
            return base
        }
        if let latest = cachedRates["\(key)-latest"] { return latest }
        return BuiltInAPIModelRates.rate(for: modelName)
    }

    private static func normalizedModel(_ value: String) -> String {
        var key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while key.hasPrefix("~") { key.removeFirst() }
        return key
    }
}
