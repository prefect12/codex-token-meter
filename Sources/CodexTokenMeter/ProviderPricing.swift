import Foundation

/// User-owned pricing overrides. They are intentionally local and never
/// include credentials, prompts, or provider account data.
struct ManualModelPriceRule: Codable, Identifiable {
    var id: UUID
    var provider: String
    var model: String
    var inputPerMillionUSD: Double
    var cachedInputPerMillionUSD: Double
    var outputPerMillionUSD: Double
    var updatedAt: Date
}

final class ManualModelPriceStore {
    static let shared = ManualModelPriceStore(url: AppSettings.manualModelPricingURL)
    private let url: URL
    private let lock = NSLock()
    private var rules: [ManualModelPriceRule] = []

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([ManualModelPriceRule].self, from: data) {
            rules = saved
        }
    }

    func allRules() -> [ManualModelPriceRule] { lock.lock(); defer { lock.unlock() }; return rules.sorted { $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending } }
    func rate(for model: String) -> APIModelRate? {
        lock.lock(); defer { lock.unlock() }
        guard let rule = rules.last(where: { $0.model.caseInsensitiveCompare(model) == .orderedSame }) else { return nil }
        return APIModelRate(inputPerMillionUSD: rule.inputPerMillionUSD, cachedInputPerMillionUSD: rule.cachedInputPerMillionUSD, outputPerMillionUSD: rule.outputPerMillionUSD)
    }
    func upsert(provider: String, model: String, input: Double, cached: Double, output: Double) {
        lock.lock(); defer { lock.unlock() }
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        rules.removeAll { $0.model.caseInsensitiveCompare(normalized) == .orderedSame }
        rules.append(ManualModelPriceRule(id: UUID(), provider: provider, model: normalized, inputPerMillionUSD: max(0, input), cachedInputPerMillionUSD: max(0, cached), outputPerMillionUSD: max(0, output), updatedAt: Date()))
        save()
    }
    private func save() { try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); if let data = try? JSONEncoder().encode(rules) { try? data.write(to: url, options: .atomic) } }
}
