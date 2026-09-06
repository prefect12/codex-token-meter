import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Usage Domain Models

struct Usage: Codable {
    var input: Int64 = 0
    var cachedInput: Int64 = 0
    var cacheCreationInput: Int64 = 0
    var cacheCreationInput1h: Int64 = 0
    var output: Int64 = 0
    var reasoningOutput: Int64 = 0
    var total: Int64 = 0

    var freshInput: Int64 { max(0, input - cachedInput - cacheCreationInput - cacheCreationInput1h) }
    var cachePercent: Double { input == 0 ? 0 : Double(cachedInput) / Double(input) * 100 }
    var totalCacheCreationInput: Int64 { cacheCreationInput + cacheCreationInput1h }

    init(
        input: Int64 = 0,
        cachedInput: Int64 = 0,
        cacheCreationInput: Int64 = 0,
        cacheCreationInput1h: Int64 = 0,
        output: Int64 = 0,
        reasoningOutput: Int64 = 0,
        total: Int64 = 0
    ) {
        self.input = input
        self.cachedInput = cachedInput
        self.cacheCreationInput = cacheCreationInput
        self.cacheCreationInput1h = cacheCreationInput1h
        self.output = output
        self.reasoningOutput = reasoningOutput
        self.total = total
    }

    private enum CodingKeys: String, CodingKey {
        case input
        case cachedInput
        case cacheCreationInput
        case cacheCreationInput1h
        case output
        case reasoningOutput
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Int64.self, forKey: .input) ?? 0
        cachedInput = try container.decodeIfPresent(Int64.self, forKey: .cachedInput) ?? 0
        cacheCreationInput = try container.decodeIfPresent(Int64.self, forKey: .cacheCreationInput) ?? 0
        cacheCreationInput1h = try container.decodeIfPresent(Int64.self, forKey: .cacheCreationInput1h) ?? 0
        output = try container.decodeIfPresent(Int64.self, forKey: .output) ?? 0
        reasoningOutput = try container.decodeIfPresent(Int64.self, forKey: .reasoningOutput) ?? 0
        total = try container.decodeIfPresent(Int64.self, forKey: .total) ?? 0
    }

    mutating func add(_ other: Usage) {
        input += other.input
        cachedInput += other.cachedInput
        cacheCreationInput += other.cacheCreationInput
        cacheCreationInput1h += other.cacheCreationInput1h
        output += other.output
        reasoningOutput += other.reasoningOutput
        total += other.total
    }

    static func delta(from previous: Usage, to current: Usage) -> Usage {
        Usage(
            input: max(0, current.input - previous.input),
            cachedInput: max(0, current.cachedInput - previous.cachedInput),
            cacheCreationInput: max(0, current.cacheCreationInput - previous.cacheCreationInput),
            cacheCreationInput1h: max(0, current.cacheCreationInput1h - previous.cacheCreationInput1h),
            output: max(0, current.output - previous.output),
            reasoningOutput: max(0, current.reasoningOutput - previous.reasoningOutput),
            total: max(0, current.total - previous.total)
        )
    }
}

struct TokenEvent: Codable {
    let timestamp: Date
    let usage: Usage
    let limitID: String?
    let limitName: String?
    let model: String?
    let provider: String?

    init(
        timestamp: Date,
        usage: Usage,
        limitID: String?,
        limitName: String?,
        model: String?,
        provider: String? = nil
    ) {
        self.timestamp = timestamp
        self.usage = usage
        self.limitID = limitID
        self.limitName = limitName
        self.model = model
        self.provider = provider
    }
}

struct DayUsage: Codable {
    let day: String
    var usage: Usage
    var turns: Int
    var sessions: Int
    var events: Int
    var modelBreakdown: [ModelUsage] = []

    init(
        day: String,
        usage: Usage,
        turns: Int,
        sessions: Int = 0,
        events: Int = 0,
        modelBreakdown: [ModelUsage] = []
    ) {
        self.day = day
        self.usage = usage
        self.turns = turns
        self.sessions = sessions
        self.events = events
        self.modelBreakdown = modelBreakdown
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case usage
        case turns
        case sessions
        case events
        case modelBreakdown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        usage = try container.decode(Usage.self, forKey: .usage)
        turns = try container.decode(Int.self, forKey: .turns)
        sessions = try container.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        events = try container.decodeIfPresent(Int.self, forKey: .events) ?? 0
        modelBreakdown = try container.decodeIfPresent([ModelUsage].self, forKey: .modelBreakdown) ?? []
    }
}

struct HourUsage: Codable {
    let hour: Date
    var usage: Usage
    var turns: Int
}

struct SessionUsage: Codable {
    let path: String
    let lastEvent: Date
    var turns: Int
    var usage: Usage
}

struct ModelUsage: Codable {
    let name: String
    var usage: Usage
    var turns: Int
    var events: Int
    var sessions: Int

    init(name: String, usage: Usage, turns: Int = 0, events: Int, sessions: Int) {
        self.name = name
        self.usage = usage
        self.turns = turns
        self.events = events
        self.sessions = sessions
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case usage
        case turns
        case events
        case sessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        usage = try container.decode(Usage.self, forKey: .usage)
        turns = try container.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        events = try container.decode(Int.self, forKey: .events)
        sessions = try container.decode(Int.self, forKey: .sessions)
    }
}

struct APICostEstimate {
    var usdValue: Double = 0
    var pricedTokens: Int64 = 0
    var totalTokens: Int64 = 0

    var hasUsage: Bool { totalTokens > 0 }
    var hasPricedUsage: Bool { pricedTokens > 0 }
    var coveragePercent: Double {
        guard totalTokens > 0 else { return 0 }
        return Double(pricedTokens) / Double(totalTokens) * 100
    }

    mutating func add(_ other: APICostEstimate) {
        usdValue += other.usdValue
        pricedTokens += other.pricedTokens
        totalTokens += other.totalTokens
    }
}

struct ExternalAPICostSnapshot {
    let usdValue: Double
    let totalTokens: Int64
    let updatedAt: String?
    let sourcePath: String

    var hasData: Bool {
        usdValue > 0 || totalTokens > 0
    }
}

/// A direct-provider usage report imported from the optional local API usage
/// file. The file is deliberately local and read-only; no API credentials or
/// prompts are ever handled by Token Meter.
enum ExternalAPIUsageStore {
    static func readReport(window: WindowOption, url: URL = AppSettings.externalAPICostURL, now: Date = Date()) -> TokenReport {
        switch window {
        case .day:
            return filteredReport(readReport(url: url), from: now.addingTimeInterval(-24 * 3600), to: now, fillDayCount: nil)
        case .week:
            let calendar = appCalendar()
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
            return filteredReport(readReport(url: url), from: start, to: now, fillDayCount: 7)
        case .month:
            let calendar = appCalendar()
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
            return filteredReport(readReport(url: url), from: start, to: now, fillDayCount: 30)
        }
    }

    static func readReport(hours: Int, url: URL = AppSettings.externalAPICostURL, now: Date = Date()) -> TokenReport {
        filteredReport(readReport(url: url), from: now.addingTimeInterval(-Double(max(hours, 1)) * 3600), to: now, fillDayCount: nil)
    }

    static func readReport(days: Int, url: URL = AppSettings.externalAPICostURL, now: Date = Date()) -> TokenReport {
        let dayCount = max(days, 1)
        let calendar = appCalendar()
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(dayCount - 1), to: now) ?? now)
        return filteredReport(readReport(url: url), from: start, to: now, fillDayCount: dayCount)
    }

    static func readReport(from start: Date, to end: Date, url: URL = AppSettings.externalAPICostURL) -> TokenReport {
        filteredReport(readReport(url: url), from: min(start, end), to: max(start, end), fillDayCount: nil)
    }

    static func readReport(url: URL = AppSettings.externalAPICostURL) -> TokenReport {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TokenReport()
        }

        let updatedAt = date(object["updated_at"] ?? object["updatedAt"])
        let topUsage = usage(object["usage"] as? [String: Any] ?? object)
        let daysValue = object["by_day"] ?? object["byDay"] ?? object["days"]
        let days = (daysValue as? [[String: Any]] ?? []).compactMap(day)
        let hoursValue = object["by_hour"] ?? object["byHour"] ?? object["hours"]
        let hours = (hoursValue as? [[String: Any]] ?? []).compactMap(hour)
        var models = mergedModels(
            (object["models"] as? [[String: Any]] ?? object["model_breakdown"] as? [[String: Any]] ?? []).compactMap(model)
        )
        if models.isEmpty {
            models = mergedModels(days.flatMap(\.modelBreakdown))
        }

        var report = TokenReport()
        report.byDay = days.sorted { $0.day < $1.day }
        report.byHour = hours.sorted { $0.hour < $1.hour }
        report.modelBreakdown = models
        report.usage = topUsage.total > 0 || topUsage.input > 0 || topUsage.output > 0
            ? topUsage
            : days.reduce(Usage()) { partial, day in
                var value = partial
                value.add(day.usage)
                return value
            }
        if report.usage.total == 0 {
            report.usage.total = int64(object["total_tokens"] ?? object["tokens"] ?? object["usage_tokens"]) ?? 0
        }
        if report.usage.input == 0, report.usage.output == 0, report.usage.total > 0 {
            report.usage.input = report.usage.total
        }
        report.turns = days.reduce(0) { $0 + $1.turns }
        report.events = days.reduce(0) { $0 + $1.events }
        report.sessions = days.reduce(0) { $0 + $1.sessions }
        if report.turns == 0, report.usage.total > 0 { report.turns = 1 }
        if report.events == 0, report.usage.total > 0 { report.events = 1 }
        if report.byDay.isEmpty, report.usage.total > 0 {
            let day = updatedAt.map { appCalendar().startOfDay(for: $0) } ?? appCalendar().startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.calendar = appCalendar()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            report.byDay = [DayUsage(day: formatter.string(from: day), usage: report.usage, turns: report.turns, sessions: report.sessions, events: report.events, modelBreakdown: models)]
        }
        report.scannedAt = updatedAt ?? Date()
        return report
    }

    private static func filteredReport(_ source: TokenReport, from start: Date, to end: Date, fillDayCount: Int?) -> TokenReport {
        let calendar = appCalendar()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let startDay = formatter.string(from: start)
        let endDay = formatter.string(from: end)
        let selectedDays = source.byDay.filter { $0.day >= startDay && $0.day <= endDay }
        let selectedHours = source.byHour.filter { $0.hour >= start && $0.hour <= end }

        var report = TokenReport(scannedAt: source.scannedAt)
        report.byHour = selectedHours
        if let fillDayCount {
            let existing = Dictionary(uniqueKeysWithValues: selectedDays.map { ($0.day, $0) })
            report.byDay = (0..<fillDayCount).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start)) else { return nil }
                let key = formatter.string(from: date)
                return existing[key] ?? DayUsage(day: key, usage: Usage(), turns: 0)
            }
        } else {
            report.byDay = selectedDays
        }

        if !selectedHours.isEmpty {
            for hour in selectedHours {
                report.usage.add(hour.usage)
                report.turns += hour.turns
            }
        } else {
            for day in selectedDays {
                report.usage.add(day.usage)
                report.turns += day.turns
                report.sessions += day.sessions
                report.events += day.events
            }
        }
        report.modelBreakdown = mergedModels(selectedDays.flatMap(\.modelBreakdown))
        if report.modelBreakdown.isEmpty,
           selectedDays.count == source.byDay.count,
           !source.modelBreakdown.isEmpty {
            report.modelBreakdown = source.modelBreakdown
        }
        report.topSessions = source.topSessions.filter { $0.lastEvent >= start && $0.lastEvent <= end }
        report.limitNames = source.limitNames
        return report
    }

    private static func day(_ object: [String: Any]) -> DayUsage? {
        let key = (object["day"] ?? object["date"] ?? object["start_date"]) as? String
        guard let key, !key.isEmpty else { return nil }
        let usageValue = object["usage"] as? [String: Any] ?? object
        let models = mergedModels(
            (object["models"] as? [[String: Any]] ?? object["model_breakdown"] as? [[String: Any]] ?? []).compactMap(model)
        )
        return DayUsage(
            day: key,
            usage: usage(usageValue),
            turns: int(object["turns"]) ?? int(object["requests"]) ?? 0,
            sessions: int(object["sessions"]) ?? 0,
            events: int(object["events"]) ?? int(object["requests"]) ?? 0,
            modelBreakdown: models
        )
    }

    private static func hour(_ object: [String: Any]) -> HourUsage? {
        guard let value = object["hour"] ?? object["timestamp"] ?? object["start_time"],
              let parsed = date(value) else { return nil }
        return HourUsage(
            hour: parsed,
            usage: usage(object["usage"] as? [String: Any] ?? object),
            turns: int(object["turns"] ?? object["requests"]) ?? 0
        )
    }

    private static func model(_ object: [String: Any]) -> ModelUsage? {
        guard let name = (object["name"] ?? object["model"]) as? String, !name.isEmpty else { return nil }
        return ModelUsage(
            name: canonicalModelName(name),
            usage: usage(object["usage"] as? [String: Any] ?? object),
            turns: int(object["turns"]) ?? int(object["requests"]) ?? 0,
            events: int(object["events"]) ?? int(object["requests"]) ?? 0,
            sessions: int(object["sessions"]) ?? 0
        )
    }

    private static func canonicalModelName(_ name: String) -> String {
        switch name.lowercased() {
        case "deepseek-chat", "deepseek-reasoner", "deepseek/deepseek-v4-flash":
            return "deepseek-v4-flash"
        case "deepseek/deepseek-v4-pro":
            return "deepseek-v4-pro"
        default:
            return name
        }
    }

    private static func mergedModels(_ models: [ModelUsage]) -> [ModelUsage] {
        var buckets: [String: ModelUsage] = [:]
        for model in models {
            var merged = buckets[model.name] ?? ModelUsage(
                name: model.name,
                usage: Usage(),
                events: 0,
                sessions: 0
            )
            merged.usage.add(model.usage)
            merged.turns += model.turns
            merged.events += model.events
            merged.sessions += model.sessions
            buckets[model.name] = merged
        }
        return buckets.values.sorted { lhs, rhs in
            if lhs.usage.total != rhs.usage.total {
                return lhs.usage.total > rhs.usage.total
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func usage(_ object: [String: Any]) -> Usage {
        let input = int64(object["input"] ?? object["input_tokens"] ?? object["prompt_tokens"]) ?? 0
        let cached = int64(object["cached_input"] ?? object["cachedInput"] ?? object["cache_read_input_tokens"] ?? object["cached_tokens"]) ?? 0
        let output = int64(object["output"] ?? object["output_tokens"] ?? object["completion_tokens"]) ?? 0
        let total = int64(object["total"] ?? object["total_tokens"] ?? object["tokens"]) ?? max(0, input + output)
        return Usage(input: input, cachedInput: cached, output: output, total: total)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let number = value as? Double { return Date(timeIntervalSince1970: number) }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
                ?? { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"; return formatter.date(from: string) }()
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}

struct APIModelRate: Codable, Equatable {
    let inputPerMillionUSD: Double
    let cachedInputPerMillionUSD: Double
    let outputPerMillionUSD: Double
    var cacheCreationInputPerMillionUSD: Double? = nil
    var cacheCreationInput1hPerMillionUSD: Double? = nil
}

enum APICostEstimator {
    static func estimate(report: TokenReport) -> APICostEstimate {
        var estimate = APICostEstimate()
        if report.modelBreakdown.isEmpty {
            return APICostEstimate(usdValue: 0, pricedTokens: 0, totalTokens: report.usage.total)
        }

        var modelTotal: Int64 = 0
        for model in report.modelBreakdown {
            modelTotal += model.usage.total
            estimate.add(Self.estimate(usage: model.usage, modelName: model.name))
        }
        if report.usage.total > modelTotal {
            estimate.totalTokens += report.usage.total - modelTotal
        }
        return estimate
    }

    static func estimate(day: DayUsage) -> APICostEstimate {
        var estimate = APICostEstimate()
        if day.modelBreakdown.isEmpty {
            return APICostEstimate(usdValue: 0, pricedTokens: 0, totalTokens: day.usage.total)
        }

        var modelTotal: Int64 = 0
        for model in day.modelBreakdown {
            modelTotal += model.usage.total
            estimate.add(Self.estimate(usage: model.usage, modelName: model.name))
        }
        if day.usage.total > modelTotal {
            estimate.totalTokens += day.usage.total - modelTotal
        }
        return estimate
    }

    static func estimate(usage: Usage, modelName: String) -> APICostEstimate {
        guard let rate = rate(for: modelName) else {
            return APICostEstimate(usdValue: 0, pricedTokens: 0, totalTokens: usage.total)
        }
        let totalOnlyInput = usage.input == 0 && usage.output == 0 && usage.total > 0 ? usage.total : usage.input
        let cachedInput = max(Int64(0), min(usage.cachedInput, totalOnlyInput))
        let cacheCreationInput = max(Int64(0), min(usage.cacheCreationInput, max(0, totalOnlyInput - cachedInput)))
        let cacheCreationInput1h = max(Int64(0), min(usage.cacheCreationInput1h, max(0, totalOnlyInput - cachedInput - cacheCreationInput)))
        let freshInput = max(Int64(0), totalOnlyInput - cachedInput - cacheCreationInput - cacheCreationInput1h)
        let cacheCreationRate = rate.cacheCreationInputPerMillionUSD ?? rate.inputPerMillionUSD
        let cacheCreation1hRate = rate.cacheCreationInput1hPerMillionUSD ?? cacheCreationRate
        let value = (
            Double(freshInput) * rate.inputPerMillionUSD
                + Double(cachedInput) * rate.cachedInputPerMillionUSD
                + Double(cacheCreationInput) * cacheCreationRate
                + Double(cacheCreationInput1h) * cacheCreation1hRate
                + Double(usage.output) * rate.outputPerMillionUSD
        ) / 1_000_000
        return APICostEstimate(usdValue: value, pricedTokens: usage.total, totalTokens: usage.total)
    }

    private static func rate(for modelName: String) -> APIModelRate? {
        if let manualRate = ManualModelPriceStore.shared.rate(for: modelName) {
            return manualRate
        }
        if let catalogRate = OpenRouterPricingCatalog.shared.rate(for: modelName) {
            return catalogRate
        }
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
        if name.contains("claude-opus-4-1")
            || name.contains("claude-opus-4") {
            return APIModelRate(inputPerMillionUSD: 15, cachedInputPerMillionUSD: 1.5, outputPerMillionUSD: 75, cacheCreationInputPerMillionUSD: 18.75, cacheCreationInput1hPerMillionUSD: 30)
        }
        if name.contains("claude-sonnet-4-6")
            || name.contains("claude-sonnet-4-5") {
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

// MARK: - Machine attribution

/// Codex usage grouped by the machine whose rollout logs produced it. `localName` marks this Mac;
/// any other name is a folder under `~/.codex/remote/<name>/` holding logs synced from elsewhere.
struct MachineUsage: Codable {
    static let localName = "local"

    let name: String
    var usage: Usage
    var sessions: Int
    var events: Int
    var turns: Int

    var isLocal: Bool { name == Self.localName }
}

struct TokenReport: Codable {
    var usage = Usage()
    var sessions = 0
    var events = 0
    var turns = 0
    var byDay: [DayUsage] = []
    var byHour: [HourUsage] = []
    var topSessions: [SessionUsage] = []
    var modelBreakdown: [ModelUsage] = []
    var limitNames: Set<String> = []
    var scannedAt = Date()
    var machineBreakdown: [MachineUsage] = []
}

extension TokenReport {
    private enum CodingKeys: String, CodingKey {
        case usage, sessions, events, turns, byDay, byHour, topSessions, modelBreakdown, limitNames, scannedAt, machineBreakdown
    }

    // Cached reports written before machine attribution existed have no `machineBreakdown`;
    // decode it as optional so an old cache file still loads instead of being thrown away.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage) ?? Usage()
        sessions = try container.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        events = try container.decodeIfPresent(Int.self, forKey: .events) ?? 0
        turns = try container.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        byDay = try container.decodeIfPresent([DayUsage].self, forKey: .byDay) ?? []
        byHour = try container.decodeIfPresent([HourUsage].self, forKey: .byHour) ?? []
        topSessions = try container.decodeIfPresent([SessionUsage].self, forKey: .topSessions) ?? []
        modelBreakdown = try container.decodeIfPresent([ModelUsage].self, forKey: .modelBreakdown) ?? []
        limitNames = try container.decodeIfPresent(Set<String>.self, forKey: .limitNames) ?? []
        scannedAt = try container.decodeIfPresent(Date.self, forKey: .scannedAt) ?? Date()
        machineBreakdown = try container.decodeIfPresent([MachineUsage].self, forKey: .machineBreakdown) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usage, forKey: .usage)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(events, forKey: .events)
        try container.encode(turns, forKey: .turns)
        try container.encode(byDay, forKey: .byDay)
        try container.encode(byHour, forKey: .byHour)
        try container.encode(topSessions, forKey: .topSessions)
        try container.encode(modelBreakdown, forKey: .modelBreakdown)
        try container.encode(limitNames, forKey: .limitNames)
        try container.encode(scannedAt, forKey: .scannedAt)
        try container.encode(machineBreakdown, forKey: .machineBreakdown)
    }
}

// MARK: - Cross-device usage reporting

struct MachineUsageIdentity: Codable {
    var installationID: String
    var displayName: String
    var hostName: String
    var timeZoneIdentifier: String
    var trackingStartedAt: Date
}

struct MachineDayUsageRecord: Codable {
    var day: String
    var usage: Usage
    var turns: Int
    var modelBreakdown: [ModelUsage]
    var apiEquivalentUSD: Double
    var apiEquivalentPricedTokens: Int64
    var firstObservedAt: Date
    var lastObservedAt: Date
}

struct AccountQuotaWindowObservation: Codable, Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?
}

struct AccountQuotaLimitObservation: Codable, Equatable {
    var id: String
    var name: String
    var planType: String?
    var primary: AccountQuotaWindowObservation?
    var secondary: AccountQuotaWindowObservation?
}

struct AccountQuotaObservation: Codable {
    var observedAt: Date
    var limits: [AccountQuotaLimitObservation]
}

struct MachineUsageHistoryFile: Codable {
    var version: Int
    var machine: MachineUsageIdentity
    var updatedAt: Date
    var localCodexByDay: [String: MachineDayUsageRecord]
    var accountQuotaObservations: [AccountQuotaObservation]
    var latestAccountUsage: AccountUsageSnapshot?
}

struct MachineLocalUsageSummary: Codable {
    var usage: Usage
    var turns: Int
    var activeDays: Int
    var firstDay: String?
    var lastDay: String?
    var apiEquivalentUSD: Double
    var apiEquivalentPricedTokens: Int64
}

struct MachineUsageReportSemantics: Codable {
    let accountQuotaScope = "Official account-level quota observed by this installation; it already includes activity from all devices and must not be summed across machines."
    let deviceUsageScope = "Codex tokens found in local rollout logs configured on this installation; compare or sum these rows by installation_id only when logs are not duplicated between machines."
    let apiEquivalentScope = "Estimated API-equivalent value of local tokens; it is not a subscription bill or an official charge."
}

struct MachineLocalUsageExport: Codable {
    var summary: MachineLocalUsageSummary
    var dailyUsage: [MachineDayUsageRecord]
}

struct MachineOfficialAccountExport: Codable {
    var latestQuota: AccountQuotaObservation?
    var quotaObservations: [AccountQuotaObservation]
    var latestProfileUsage: AccountUsageSnapshot?
}

struct MachineUsageExportReport: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String
    var machine: MachineUsageIdentity
    var semantics: MachineUsageReportSemantics
    var deviceLocalCodex: MachineLocalUsageExport
    var officialAccount: MachineOfficialAccountExport
}

struct RepoInsightDay: Codable {
    let day: String
    var conversations: Int
    var turns: Int
    var compressions: Int
}

struct RepoInsightTurnBuckets: Codable {
    var short: Int = 0
    var medium: Int = 0
    var long: Int = 0
    var extraLong: Int = 0
}

struct RepoInsightCompressionBuckets: Codable {
    var zero: Int = 0
    var one: Int = 0
    var two: Int = 0
    var threePlus: Int = 0
}

struct RepoInsightHour: Codable {
    let hour: Int
    var conversations: Int
    var turns: Int
    var tokens: Int64
}

struct ReasoningEffortSummary: Codable {
    var effort: String
    var runs: Int
    var tasks: Int
    var usage: Usage
    var medianTokens: Int64
    var p90Tokens: Int64
}

struct ReasoningModelEffortSummary: Codable {
    var model: String
    var effort: String
    var runs: Int
    var tasks: Int
    var projectCount: Int?
    var usage: Usage
    var medianTokens: Int64
    var p90Tokens: Int64
}

struct ReasoningDailyModelEffortSummary: Codable {
    var day: String
    var model: String
    var effort: String
    var runs: Int
    var usage: Usage
    var runTokenTotals: [Int64]

    var medianTokens: Int64 {
        let sorted = runTokenTotals.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[(sorted.count - 1) / 2]
    }
}

struct ReasoningInsightsReport: Codable {
    var taskCount: Int
    var runCount: Int
    var usage: Usage
    var knownRunCount: Int
    var knownTokenCount: Int64
    var efforts: [ReasoningEffortSummary]
    var modelEfforts: [ReasoningModelEffortSummary]
    var dailyModelEfforts: [ReasoningDailyModelEffortSummary]

    var runCoveragePercent: Double {
        guard runCount > 0 else { return 0 }
        return Double(knownRunCount) / Double(runCount) * 100
    }

    var tokenCoveragePercent: Double {
        guard usage.total > 0 else { return 0 }
        return Double(knownTokenCount) / Double(usage.total) * 100
    }
}

func mergedReasoningInsightsReports(_ reports: [ReasoningInsightsReport?]) -> ReasoningInsightsReport? {
    let values = reports.compactMap { $0 }
    guard !values.isEmpty else { return nil }
    var effortBuckets: [String: ReasoningEffortSummary] = [:]
    var modelBuckets: [String: ReasoningModelEffortSummary] = [:]
    var dailyBuckets: [String: ReasoningDailyModelEffortSummary] = [:]
    var taskCount = 0
    var runCount = 0
    var usage = Usage()
    var knownRunCount = 0
    var knownTokenCount: Int64 = 0
    for report in values {
        taskCount += report.taskCount
        runCount += report.runCount
        usage.add(report.usage)
        knownRunCount += report.knownRunCount
        knownTokenCount += report.knownTokenCount
        for effort in report.efforts {
            var bucket = effortBuckets[effort.effort] ?? ReasoningEffortSummary(effort: effort.effort, runs: 0, tasks: 0, usage: Usage(), medianTokens: 0, p90Tokens: 0)
            bucket.runs += effort.runs
            bucket.tasks += effort.tasks
            bucket.usage.add(effort.usage)
            bucket.medianTokens = max(bucket.medianTokens, effort.medianTokens)
            bucket.p90Tokens = max(bucket.p90Tokens, effort.p90Tokens)
            effortBuckets[effort.effort] = bucket
        }
        for model in report.modelEfforts {
            let key = "\(model.model)\u{1F}\(model.effort)"
            var bucket = modelBuckets[key] ?? ReasoningModelEffortSummary(model: model.model, effort: model.effort, runs: 0, tasks: 0, projectCount: model.projectCount, usage: Usage(), medianTokens: 0, p90Tokens: 0)
            bucket.runs += model.runs
            bucket.tasks += model.tasks
            bucket.projectCount = max(bucket.projectCount ?? 0, model.projectCount ?? 0)
            bucket.usage.add(model.usage)
            bucket.medianTokens = max(bucket.medianTokens, model.medianTokens)
            bucket.p90Tokens = max(bucket.p90Tokens, model.p90Tokens)
            modelBuckets[key] = bucket
        }
        for daily in report.dailyModelEfforts {
            let key = "\(daily.day)\u{1F}\(daily.model)\u{1F}\(daily.effort)"
            var bucket = dailyBuckets[key] ?? ReasoningDailyModelEffortSummary(day: daily.day, model: daily.model, effort: daily.effort, runs: 0, usage: Usage(), runTokenTotals: [])
            bucket.runs += daily.runs
            bucket.usage.add(daily.usage)
            bucket.runTokenTotals.append(contentsOf: daily.runTokenTotals)
            dailyBuckets[key] = bucket
        }
    }
    return ReasoningInsightsReport(taskCount: taskCount, runCount: runCount, usage: usage, knownRunCount: knownRunCount, knownTokenCount: knownTokenCount, efforts: effortBuckets.values.sorted { CodexTokenScanner.reasoningEffortRank($0.effort) < CodexTokenScanner.reasoningEffortRank($1.effort) }, modelEfforts: modelBuckets.values.sorted { $0.model == $1.model ? CodexTokenScanner.reasoningEffortRank($0.effort) < CodexTokenScanner.reasoningEffortRank($1.effort) : $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending }, dailyModelEfforts: dailyBuckets.values.sorted { $0.day == $1.day ? $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending : $0.day < $1.day })
}

struct RepoInsight: Codable {
    var key: String
    var displayName: String
    var primaryFolder: String
    var folders: Set<String>
    var conversations: Int
    var turns: Int
    var compressions: Int
    var tokens: Int64
    var conversationsWithCompression: Int
    var longestTurns: Int
    var longestTokens: Int64
    var maxCompressions: Int
    var abortedTurns: Int
    var completedTurns: Int
    var activeDays: Set<String>
    var turnBuckets: RepoInsightTurnBuckets
    var compressionBuckets: RepoInsightCompressionBuckets
    var days: [RepoInsightDay]
    var hours: [RepoInsightHour]

    var averageTurnsPerConversation: Double {
        conversations == 0 ? 0 : Double(turns) / Double(conversations)
    }

    var averageCompressionsPerConversation: Double {
        conversations == 0 ? 0 : Double(compressions) / Double(conversations)
    }

    var compressionConversationRate: Double {
        conversations == 0 ? 0 : Double(conversationsWithCompression) / Double(conversations)
    }

    var risk: RepoInsightRisk {
        if averageCompressionsPerConversation >= 1.0
            || maxCompressions >= 8
            || compressionConversationRate >= 0.45 {
            return .frequentCompression
        }
        if averageCompressionsPerConversation >= 0.35
            || longestTurns >= 40
            || averageTurnsPerConversation >= 12 {
            return .longRunning
        }
        if conversations >= 10
            && averageTurnsPerConversation <= 5
            && averageCompressionsPerConversation < 0.2 {
            return .wellSplit
        }
        return .healthy
    }
}

enum RepoInsightRisk {
    case frequentCompression
    case longRunning
    case wellSplit
    case healthy
}

struct RepoInsightsReport: Codable {
    var rows: [RepoInsight]
    var scannedAt: Date
    var windowDays: Int
    var reasoning: ReasoningInsightsReport? = nil
}

struct AccountUsageSummary: Codable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct AccountUsageDailyBucket: Codable {
    let startDate: String
    let tokens: Int64
}

struct AccountUsageSnapshot: Codable {
    let summary: AccountUsageSummary
    let dailyUsageBuckets: [AccountUsageDailyBucket]
    let readAt: Date

    var hasData: Bool {
        (summary.lifetimeTokens ?? 0) > 0 || dailyUsageBuckets.contains { $0.tokens > 0 }
    }

    func report(days dayCount: Int, useLifetimeTotal: Bool = false) -> TokenReport {
        let count = max(dayCount, 1)
        let calendar = appCalendar()
        let formatter = dayFormatter()
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        var byDate: [String: Int64] = [:]
        for bucket in dailyUsageBuckets {
            byDate[String(bucket.startDate.prefix(10)), default: 0] += bucket.tokens
        }
        var report = TokenReport(scannedAt: readAt)
        report.byDay = (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            let key = formatter.string(from: date)
            let total = byDate[key] ?? 0
            return DayUsage(day: key, usage: Usage(total: total), turns: 0)
        }
        let dailyTotal = report.byDay.reduce(Int64(0)) { $0 + $1.usage.total }
        report.usage.total = useLifetimeTotal ? max(summary.lifetimeTokens ?? 0, dailyTotal) : dailyTotal
        return report
    }

    func report(window: WindowOption) -> TokenReport {
        switch window {
        case .day:
            let todayReport = report(days: 1)
            if todayReport.usage.total > 0 {
                return todayReport
            }
            return latestDayReport() ?? todayReport
        case .week:
            return report(days: 7)
        case .month:
            return report(days: 30)
        }
    }

    private func latestDayReport() -> TokenReport? {
        guard let bucket = dailyUsageBuckets.last(where: { $0.tokens > 0 }) else {
            return nil
        }
        var report = TokenReport(scannedAt: readAt)
        let day = String(bucket.startDate.prefix(10))
        report.usage.total = bucket.tokens
        report.byDay = [DayUsage(day: day, usage: Usage(total: bucket.tokens), turns: 0)]
        return report
    }
}
