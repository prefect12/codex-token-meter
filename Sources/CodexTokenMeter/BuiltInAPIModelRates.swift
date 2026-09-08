import Foundation

struct APIModelRate: Codable, Equatable {
    let inputPerMillionUSD: Double
    let cachedInputPerMillionUSD: Double
    let outputPerMillionUSD: Double
    var cacheCreationInputPerMillionUSD: Double? = nil
    var cacheCreationInput1hPerMillionUSD: Double? = nil
}

enum BuiltInAPIModelRates {
    static func rate(for modelName: String) -> APIModelRate? {
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Standard API-equivalent rates, not subscription charges. Aggregate
        // usage cannot reconstruct per-request long-context or Fast surcharges.
        // https://developers.openai.com/api/docs/models/gpt-6-astra
        if ["gpt-6-astra", "gpt-6 astra", "gpt-6-astra-wm", "openai/gpt-6-astra"].contains(name) {
            return APIModelRate(inputPerMillionUSD: 10, cachedInputPerMillionUSD: 1, outputPerMillionUSD: 50, cacheCreationInputPerMillionUSD: 12.5)
        }
        if name.contains("deepseek-v4-pro") {
            return APIModelRate(inputPerMillionUSD: 0.435, cachedInputPerMillionUSD: 0.003625, outputPerMillionUSD: 0.87)
        }
        if name.contains("deepseek-v4-flash")
            || name.contains("deepseek-chat")
            || name.contains("deepseek-reasoner") {
            return APIModelRate(inputPerMillionUSD: 0.14, cachedInputPerMillionUSD: 0.0028, outputPerMillionUSD: 0.28)
        }
        if name.contains("gpt-5.6-luna") || name.contains("gpt-5.6 luna") {
            return APIModelRate(inputPerMillionUSD: 1, cachedInputPerMillionUSD: 0.1, outputPerMillionUSD: 6, cacheCreationInputPerMillionUSD: 1.25)
        }
        if name.contains("gpt-5.6-terra") || name.contains("gpt-5.6 terra") {
            return APIModelRate(inputPerMillionUSD: 2.5, cachedInputPerMillionUSD: 0.25, outputPerMillionUSD: 15, cacheCreationInputPerMillionUSD: 3.125)
        }
        if name.contains("gpt-5.6-sol") || name.contains("gpt-5.6 sol") || name == "gpt-5.6" {
            return APIModelRate(inputPerMillionUSD: 5, cachedInputPerMillionUSD: 0.5, outputPerMillionUSD: 30, cacheCreationInputPerMillionUSD: 6.25)
        }
        if name.contains("gpt-5.5") && name.contains("cyber") {
            return APIModelRate(inputPerMillionUSD: 20, cachedInputPerMillionUSD: 2, outputPerMillionUSD: 120)
        }
        if name.contains("gpt-5.5") {
            return APIModelRate(inputPerMillionUSD: 5, cachedInputPerMillionUSD: 0.5, outputPerMillionUSD: 30)
        }
        if name.contains("gpt-5.4-mini") || name.contains("gpt-5.4 mini") {
            return APIModelRate(inputPerMillionUSD: 0.75, cachedInputPerMillionUSD: 0.075, outputPerMillionUSD: 4.5)
        }
        if name.contains("gpt-5.4") {
            return APIModelRate(inputPerMillionUSD: 2.5, cachedInputPerMillionUSD: 0.25, outputPerMillionUSD: 15)
        }
        if name.contains("gpt-5.3-codex-spark") {
            return APIModelRate(inputPerMillionUSD: 1.75, cachedInputPerMillionUSD: 0.175, outputPerMillionUSD: 14)
        }
        if name.contains("gpt-5.3-codex") || name.contains("gpt-5.2-codex") || name.contains("gpt-5.2") || name.contains("gpt-5-codex") {
            return APIModelRate(inputPerMillionUSD: 1.75, cachedInputPerMillionUSD: 0.175, outputPerMillionUSD: 14)
        }
        if name.contains("claude-sonnet-5") {
            // Anthropic launch pricing through 2026-08-31. Standard pricing after
            // the introductory period is $3 input / $15 output per million tokens.
            return APIModelRate(inputPerMillionUSD: 2, cachedInputPerMillionUSD: 0.2, outputPerMillionUSD: 10, cacheCreationInputPerMillionUSD: 2.5, cacheCreationInput1hPerMillionUSD: 4)
        }
        if name.contains("claude-fable-5") || name.contains("claude-mythos-5") {
            return APIModelRate(inputPerMillionUSD: 10, cachedInputPerMillionUSD: 1, outputPerMillionUSD: 50, cacheCreationInputPerMillionUSD: 12.5, cacheCreationInput1hPerMillionUSD: 20)
        }
        if name.contains("claude-opus-5")
            || name.contains("claude-opus-4-8")
            || name.contains("claude-opus-4-7")
            || name.contains("claude-opus-4-6")
            || name.contains("claude-opus-4-5") {
            return APIModelRate(inputPerMillionUSD: 5, cachedInputPerMillionUSD: 0.5, outputPerMillionUSD: 25, cacheCreationInputPerMillionUSD: 6.25, cacheCreationInput1hPerMillionUSD: 10)
        }
        if name.contains("claude-opus-4-1") || name.contains("claude-opus-4") {
            return APIModelRate(inputPerMillionUSD: 15, cachedInputPerMillionUSD: 1.5, outputPerMillionUSD: 75, cacheCreationInputPerMillionUSD: 18.75, cacheCreationInput1hPerMillionUSD: 30)
        }
        if name.contains("claude-sonnet-4-6") || name.contains("claude-sonnet-4-5") {
            return APIModelRate(inputPerMillionUSD: 3, cachedInputPerMillionUSD: 0.3, outputPerMillionUSD: 15, cacheCreationInputPerMillionUSD: 3.75, cacheCreationInput1hPerMillionUSD: 6)
        }
        if name.contains("claude-haiku-4-5") {
            return APIModelRate(inputPerMillionUSD: 1, cachedInputPerMillionUSD: 0.1, outputPerMillionUSD: 5, cacheCreationInputPerMillionUSD: 1.25, cacheCreationInput1hPerMillionUSD: 2)
        }
        if name.contains("claude-haiku-3") {
            return APIModelRate(inputPerMillionUSD: 0.25, cachedInputPerMillionUSD: 0.025, outputPerMillionUSD: 1.25, cacheCreationInputPerMillionUSD: 0.3, cacheCreationInput1hPerMillionUSD: 0.5)
        }
        return nil
    }
}
