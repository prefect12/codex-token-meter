import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Cost History And Estimation

struct OpenRouterPricingCatalogStatus {
    let modelCount: Int
    let fetchedAt: Date?
}

/// Read-only pricing catalog backed by OpenRouter's public Models API.
/// Only model identifiers and token prices are persisted; no API key, usage,
/// prompts, or response content is sent to OpenRouter.
final class OpenRouterPricingCatalog {
    static let shared = OpenRouterPricingCatalog(
        cacheURL: AppSettings.openRouterPricingCatalogCacheURL,
        endpointURL: URL(string: "https://openrouter.ai/api/v1/models?output_modalities=text")!
    )

    private struct CacheFile: Codable {
        let version: Int
        let fetchedAt: Date
        let modelCount: Int
        let rates: [String: APIModelRate]
    }

    private let cacheURL: URL
    private let endpointURL: URL
    private let session: URLSession
    private let lock = NSLock()
    private var rates: [String: APIModelRate] = [:]
    private var fetchedAt: Date?
    private var modelCount = 0
    private var refreshInFlight = false
    private let refreshInterval: TimeInterval = 24 * 60 * 60

    init(cacheURL: URL, endpointURL: URL, session: URLSession? = nil) {
        self.cacheURL = cacheURL
        self.endpointURL = endpointURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
        loadCache()
    }

    func rate(for modelName: String) -> APIModelRate? {
        let key = Self.normalizedKey(modelName)
        lock.lock()
        defer { lock.unlock() }
        if let exact = rates[key] {
            return exact
        }
        if key.hasSuffix("-latest") {
            return rates[String(key.dropLast("-latest".count))]
        }
        return rates["\(key)-latest"]
    }

    func status() -> OpenRouterPricingCatalogStatus {
        lock.lock()
        defer { lock.unlock() }
        return OpenRouterPricingCatalogStatus(modelCount: modelCount, fetchedAt: fetchedAt)
    }

    func refreshIfNeeded(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        lock.lock()
        let fresh = fetchedAt.map { Date().timeIntervalSince($0) < refreshInterval } ?? false
        if refreshInFlight || (!force && fresh) {
            lock.unlock()
            completion?(false)
            return
        }
        refreshInFlight = true
        lock.unlock()

        session.dataTask(with: endpointURL) { [weak self] data, response, _ in
            guard let self else { return }
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let parsed = data.flatMap(Self.parseCatalog)
            let succeeded = statusCode.map { (200..<300).contains($0) } != false
                && parsed?.rates.isEmpty == false
            if let parsed, succeeded {
                let now = Date()
                self.lock.lock()
                self.rates = parsed.rates
                self.modelCount = parsed.modelCount
                self.fetchedAt = now
                self.refreshInFlight = false
                self.lock.unlock()
                self.saveCache(CacheFile(version: 1, fetchedAt: now, modelCount: parsed.modelCount, rates: parsed.rates))
            } else {
                self.lock.lock()
                self.refreshInFlight = false
                self.lock.unlock()
            }
            completion?(succeeded)
        }.resume()
    }

    static func parseCatalog(_ data: Data) -> (rates: [String: APIModelRate], modelCount: Int)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["data"] as? [[String: Any]] else {
            return nil
        }
        var result: [String: APIModelRate] = [:]
        for model in models {
            guard let id = model["id"] as? String,
                  let pricing = model["pricing"] as? [String: Any],
                  let prompt = number(pricing["prompt"]),
                  let completion = number(pricing["completion"]) else {
                continue
            }
            let cacheRead = number(pricing["input_cache_read"]) ?? prompt
            let cacheWrite = number(pricing["input_cache_write"])
            let rate = APIModelRate(
                inputPerMillionUSD: prompt * 1_000_000,
                cachedInputPerMillionUSD: cacheRead * 1_000_000,
                outputPerMillionUSD: completion * 1_000_000,
                cacheCreationInputPerMillionUSD: cacheWrite.map { $0 * 1_000_000 }
            )
            var aliases = [id]
            if let canonical = model["canonical_slug"] as? String {
                aliases.append(canonical)
            }
            for alias in aliases {
                let key = normalizedKey(alias)
                result[key] = rate
                if key.hasSuffix("-latest") {
                    result[String(key.dropLast("-latest".count))] = rate
                }
            }
        }
        return (result, models.count)
    }

    private static func normalizedKey(_ value: String) -> String {
        var key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while key.hasPrefix("~") {
            key.removeFirst()
        }
        return key
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheFile.self, from: data),
              cache.version == 1 else {
            return
        }
        rates = cache.rates
        fetchedAt = cache.fetchedAt
        modelCount = cache.modelCount
    }

    private func saveCache(_ cache: CacheFile) {
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.prettySorted.encode(cache)
            try data.write(to: cacheURL, options: [.atomic])
        } catch {
            NSLog("AI Token Meter failed to save OpenRouter pricing catalog: \(error)")
        }
    }
}

struct CostHistoryWeekSnapshot: Codable {
    var limitID: String
    var limitName: String
    var weekStart: String
    var maxUsedPercent: Double
    var lastUsedPercent: Double
    var lastRemainingPercent: Double
    var observedCount: Int
    var firstSeenAt: String
    var updatedAt: String
    var resetAt: String?
}

struct CostHistoryEvent: Codable {
    var type: String
    var limitID: String
    var weekStart: String
    var previousUsedPercent: Double
    var currentUsedPercent: Double
    var observedAt: String
    var note: String
}

struct CostHistoryFile: Codable {
    var version: Int = 1
    var updatedAt: String?
    var weeks: [String: CostHistoryWeekSnapshot] = [:]
    var events: [CostHistoryEvent] = []
}

final class CostHistoryStore {
    static let shared = CostHistoryStore(url: AppSettings.costHistoryURL)

    private static let resetDropThreshold = 1.0
    private static let resetLowWatermark = 0.5

    private let url: URL
    private var file: CostHistoryFile
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(CostHistoryFile.self, from: data) {
            self.file = decoded
        } else {
            self.file = CostHistoryFile()
        }
    }

    func maxUsedPercent(limitID: String, weekStart: Date) -> Double? {
        let key = snapshotKey(limitID: limitID, weekStart: weekStart)
        return file.weeks[key]?.maxUsedPercent
    }

    func resetCycleCount(limitID: String, weekStart: Date) -> Int {
        resetEvents(limitID: limitID, weekStart: weekStart).count
    }

    func resetBaseUsedPercent(limitID: String, weekStart: Date) -> Double? {
        let explicitEvents = resetEvents(limitID: limitID, weekStart: weekStart)
        if let first = explicitEvents.first {
            return first.previousUsedPercent
        }
        return nil
    }

    func resetEvents(limitID: String, weekStart: Date) -> [CostHistoryEvent] {
        let weekStartText = dayFormatter().string(from: weekStart)
        return file.events
            .filter {
                $0.type == "weekly_usage_percent_drop"
                    && $0.limitID == limitID
                    && $0.weekStart == weekStartText
            }
            .sorted {
                eventDate($0) ?? .distantPast < eventDate($1) ?? .distantPast
            }
    }

    func record(limits: [LiveRateLimit], observedAt: Date = Date()) {
        guard !limits.isEmpty else { return }
        var changed = false
        let observedAtText = isoFormatter.string(from: observedAt)
        for limit in limits {
            guard let weekly = limit.secondary else { continue }
            let weekStart = appCalendar().dateInterval(of: .weekOfYear, for: observedAt)?.start ?? appCalendar().startOfDay(for: observedAt)
            let key = snapshotKey(limitID: limit.id, weekStart: weekStart)
            let usedPercent = max(0, min(100, weekly.usedPercent))
            let remainingPercent = max(0, min(100, weekly.remainingPercent))
            let resetAtText = weekly.resetsAt.map { isoFormatter.string(from: $0) }

            if var snapshot = file.weeks[key] {
                if Self.isResetDrop(previousUsedPercent: snapshot.lastUsedPercent, currentUsedPercent: usedPercent) {
                    file.events.append(CostHistoryEvent(
                        type: "weekly_usage_percent_drop",
                        limitID: limit.id,
                        weekStart: snapshot.weekStart,
                        previousUsedPercent: snapshot.lastUsedPercent,
                        currentUsedPercent: usedPercent,
                        observedAt: observedAtText,
                        note: "OpenAI live quota usage dropped; treating this as a reset/refresh observation."
                    ))
                }
                snapshot.limitName = limit.name
                snapshot.maxUsedPercent = max(snapshot.maxUsedPercent, usedPercent)
                snapshot.lastUsedPercent = usedPercent
                snapshot.lastRemainingPercent = remainingPercent
                snapshot.observedCount += 1
                snapshot.updatedAt = observedAtText
                snapshot.resetAt = resetAtText
                file.weeks[key] = snapshot
                changed = true
            } else {
                file.weeks[key] = CostHistoryWeekSnapshot(
                    limitID: limit.id,
                    limitName: limit.name,
                    weekStart: dayFormatter().string(from: weekStart),
                    maxUsedPercent: usedPercent,
                    lastUsedPercent: usedPercent,
                    lastRemainingPercent: remainingPercent,
                    observedCount: 1,
                    firstSeenAt: observedAtText,
                    updatedAt: observedAtText,
                    resetAt: resetAtText
                )
                changed = true
            }
        }
        if changed {
            file.updatedAt = observedAtText
            file.events = Array(file.events.suffix(200))
            save()
        }
    }

    private func snapshotKey(limitID: String, weekStart: Date) -> String {
        "\(limitID)|\(dayFormatter().string(from: weekStart))"
    }

    private static func isResetDrop(previousUsedPercent: Double, currentUsedPercent: Double) -> Bool {
        let drop = previousUsedPercent - currentUsedPercent
        guard drop >= resetDropThreshold else { return false }
        return currentUsedPercent <= resetLowWatermark
    }

    private func eventDate(_ event: CostHistoryEvent) -> Date? {
        isoFormatter.date(from: event.observedAt)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.prettySorted.encode(file)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("AI Token Meter failed to save cost history: \(error)")
        }
    }
}

extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - Quota Cycle History

enum QuotaWindowKind: String, Codable {
    case fiveHour = "primary"
    case weekly = "secondary"
}

struct QuotaCycleRecord: Codable {
    var limitID: String
    var kind: String
    var windowMinutes: Int
    var resetAt: String
    var maxUsedPercent: Double
    var lastUsedPercent: Double
    var observedCount: Int
    var firstSeenAt: String
    var lastSeenAt: String
    var backfilled: Bool?

    var isBackfilled: Bool { backfilled == true }
}

struct QuotaCycleFile: Codable {
    var version: Int = 1
    var updatedAt: String?
    var cycles: [QuotaCycleRecord] = []
}

/// Tracks one record per observed rate-limit cycle, keyed by the cycle's
/// `resetsAt` boundary instead of calendar weeks, so history matches the
/// rolling reset schedule Codex actually uses.
final class QuotaCycleStore {
    static let shared = QuotaCycleStore(url: AppSettings.quotaCycleHistoryURL)

    private static let maxCyclesPerWindow: [QuotaWindowKind: Int] = [.fiveHour: 96, .weekly: 60]

    private let url: URL
    private var file: QuotaCycleFile
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(QuotaCycleFile.self, from: data) {
            self.file = decoded
            if file.version < 2 {
                // Version 2 rebuilds legacy seeds from observed usage-drop
                // events, giving contiguous ranges and preserving mid-cycle
                // promo refreshes; drop the old calendar-week estimates.
                file.cycles.removeAll { $0.isBackfilled }
                file.version = 2
                backfillWeeklyCyclesFromCostHistory()
                save()
            }
        } else {
            self.file = QuotaCycleFile(version: 2)
            backfillWeeklyCyclesFromCostHistory()
            save()
        }
    }

    func cycles(limitID: String, kind: QuotaWindowKind) -> [QuotaCycleRecord] {
        file.cycles
            .filter { $0.limitID == limitID && $0.kind == kind.rawValue }
            .sorted { ($0.resetAtDate(isoFormatter) ?? .distantPast) > ($1.resetAtDate(isoFormatter) ?? .distantPast) }
    }

    func record(limits: [LiveRateLimit], observedAt: Date = Date()) {
        guard !limits.isEmpty else { return }
        var changed = false
        for limit in limits {
            let windows: [(QuotaWindowKind, RateWindow)] = [
                limit.primary.map { (.fiveHour, $0) },
                limit.secondary.map { (.weekly, $0) }
            ].compactMap { $0 }
            for (kind, window) in windows {
                guard let resetsAt = window.resetsAt, window.windowMinutes > 0 else { continue }
                if upsert(limitID: limit.id, kind: kind, window: window, resetsAt: resetsAt, observedAt: observedAt) {
                    changed = true
                }
            }
        }
        if changed {
            prune()
            file.updatedAt = isoFormatter.string(from: observedAt)
            save()
        }
    }

    private func upsert(limitID: String, kind: QuotaWindowKind, window: RateWindow, resetsAt: Date, observedAt: Date) -> Bool {
        // `resetsAt` can drift a little between reads of the same cycle, so
        // match against a tolerance proportional to the window length.
        let toleranceSeconds = min(max(Double(window.windowMinutes) * 60 * 0.1, 20 * 60), 24 * 3600)
        let usedPercent = max(0, min(100, window.usedPercent))
        let observedAtText = isoFormatter.string(from: observedAt)

        if let index = file.cycles.firstIndex(where: { record in
            record.limitID == limitID
                && record.kind == kind.rawValue
                && record.resetAtDate(isoFormatter).map { abs($0.timeIntervalSince(resetsAt)) <= toleranceSeconds } == true
        }) {
            var record = file.cycles[index]
            record.windowMinutes = window.windowMinutes
            record.resetAt = isoFormatter.string(from: resetsAt)
            record.maxUsedPercent = max(record.maxUsedPercent, usedPercent)
            record.lastUsedPercent = usedPercent
            record.observedCount += 1
            record.lastSeenAt = observedAtText
            record.backfilled = nil
            file.cycles[index] = record
            return true
        }

        file.cycles.append(QuotaCycleRecord(
            limitID: limitID,
            kind: kind.rawValue,
            windowMinutes: window.windowMinutes,
            resetAt: isoFormatter.string(from: resetsAt),
            maxUsedPercent: usedPercent,
            lastUsedPercent: usedPercent,
            observedCount: 1,
            firstSeenAt: observedAtText,
            lastSeenAt: observedAtText
        ))
        return true
    }

    /// Seeds weekly cycles from the legacy cost history. Observed usage-drop
    /// events are the primary cycle boundaries (each event records the exact
    /// moment and the final used percent of the cycle it ended, including
    /// mid-cycle promo refreshes). Scheduled reset times from week snapshots
    /// only fill gaps where no drop was observed, and only when they sit a
    /// plausible window length after the previous boundary. Ranges come out
    /// contiguous, with `windowMinutes` equal to the real cycle span.
    private func backfillWeeklyCyclesFromCostHistory() {
        guard let data = try? Data(contentsOf: AppSettings.costHistoryURL),
              let legacy = try? JSONDecoder().decode(CostHistoryFile.self, from: data) else {
            return
        }
        let day: TimeInterval = 86_400
        let weekStartParser = dayFormatter()
        let limitIDs = Set(legacy.weeks.values.map(\.limitID)).union(legacy.events.map(\.limitID))
        var seeded: [QuotaCycleRecord] = []
        for limitID in limitIDs {
            let snapshots = legacy.weeks.values.filter { $0.limitID == limitID }
            let events: [(time: Date, peak: Double)] = legacy.events
                .filter { $0.limitID == limitID && $0.type == "weekly_usage_percent_drop" }
                .compactMap { event in
                    isoFormatter.date(from: event.observedAt).map { ($0, event.previousUsedPercent) }
                }
                .sorted { $0.time < $1.time }

            var boundaries: [(time: Date, peak: Double?)] = events.map { ($0.time, $0.peak) }
            let scheduledEnds = snapshots
                .compactMap { $0.resetAt.flatMap { isoFormatter.date(from: $0) } }
                .sorted()
            for scheduled in scheduledEnds {
                if boundaries.contains(where: { abs($0.time.timeIntervalSince(scheduled)) < day }) { continue }
                if let previous = boundaries.map(\.time).filter({ $0 < scheduled }).max() {
                    // A genuine next reset sits roughly one window after the
                    // previous boundary; anything else is a stale schedule
                    // superseded by an early refresh.
                    let gap = scheduled.timeIntervalSince(previous)
                    guard gap > 5.5 * day, gap < 8.5 * day else { continue }
                }
                boundaries.append((scheduled, nil))
                boundaries.sort { $0.time < $1.time }
            }
            guard !boundaries.isEmpty else { continue }

            let firstSeen = snapshots.compactMap { isoFormatter.date(from: $0.firstSeenAt) }.min()
            var previousEnd = firstSeen ?? boundaries[0].time.addingTimeInterval(-7 * day)
            for boundary in boundaries {
                let interval = boundary.time.timeIntervalSince(previousEnd)
                let cycleStart = previousEnd
                previousEnd = boundary.time
                guard interval > 6 * 3600 else { continue }

                let peak: Double
                if let eventPeak = boundary.peak {
                    peak = eventPeak
                } else {
                    let nearLast = snapshots
                        .filter { snapshot in
                            guard let updated = isoFormatter.date(from: snapshot.updatedAt) else { return false }
                            return updated > boundary.time.addingTimeInterval(-4 * day)
                                && updated < boundary.time.addingTimeInterval(day)
                        }
                        .map(\.lastUsedPercent)
                        .max()
                    let overlapMax = snapshots
                        .filter { snapshot in
                            guard let weekStart = weekStartParser.date(from: snapshot.weekStart) else { return false }
                            return weekStart < boundary.time && weekStart.addingTimeInterval(7 * day) > cycleStart
                        }
                        .map(\.maxUsedPercent)
                        .max()
                    peak = nearLast ?? overlapMax ?? 0
                }

                seeded.append(QuotaCycleRecord(
                    limitID: limitID,
                    kind: QuotaWindowKind.weekly.rawValue,
                    windowMinutes: max(1, Int(interval / 60)),
                    resetAt: isoFormatter.string(from: boundary.time),
                    maxUsedPercent: max(0, min(100, peak)),
                    lastUsedPercent: max(0, min(100, peak)),
                    observedCount: 1,
                    firstSeenAt: isoFormatter.string(from: cycleStart),
                    lastSeenAt: isoFormatter.string(from: boundary.time),
                    backfilled: true
                ))
            }
        }
        guard !seeded.isEmpty else { return }
        file.cycles.append(contentsOf: seeded)
    }

    private func prune() {
        for kind in [QuotaWindowKind.fiveHour, .weekly] {
            let limitIDs = Set(file.cycles.filter { $0.kind == kind.rawValue }.map(\.limitID))
            for limitID in limitIDs {
                let keep = Set(
                    cycles(limitID: limitID, kind: kind)
                        .prefix(Self.maxCyclesPerWindow[kind] ?? 40)
                        .map(\.resetAt)
                )
                file.cycles.removeAll {
                    $0.limitID == limitID && $0.kind == kind.rawValue && !keep.contains($0.resetAt)
                }
            }
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.prettySorted.encode(file)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("AI Token Meter failed to save quota cycle history: \(error)")
        }
    }
}

extension QuotaCycleRecord {
    func resetAtDate(_ formatter: ISO8601DateFormatter) -> Date? {
        formatter.date(from: resetAt)
    }

    func cycleStartDate(_ formatter: ISO8601DateFormatter) -> Date? {
        guard let end = resetAtDate(formatter), windowMinutes > 0 else { return nil }
        return end.addingTimeInterval(-Double(windowMinutes) * 60)
    }
}

func costEstimateLimit(from limits: [LiveRateLimit]) -> LiveRateLimit? {
    limits.first { $0.id == QuotaViewOption.codex.liveLimitID }
}

func mergedTokenReport(_ reports: [TokenReport], scannedAt: Date = Date()) -> TokenReport {
    var merged = TokenReport(scannedAt: scannedAt)
    var dayBuckets: [String: DayUsage] = [:]
    var hourBuckets: [Date: HourUsage] = [:]
    var modelBuckets: [String: ModelUsage] = [:]
    var sessions: [SessionUsage] = []

    for report in reports {
        merged.usage.add(report.usage)
        merged.sessions += report.sessions
        merged.events += report.events
        merged.turns += report.turns
        merged.limitNames.formUnion(report.limitNames)
        sessions.append(contentsOf: report.topSessions)

        for day in report.byDay {
            var existing = dayBuckets[day.day] ?? DayUsage(day: day.day, usage: Usage(), turns: 0, modelBreakdown: [])
            existing.usage.add(day.usage)
            existing.turns += day.turns
            existing.sessions += day.sessions
            existing.events += day.events
            existing.modelBreakdown = mergedModelBreakdown(existing.modelBreakdown + day.modelBreakdown)
            dayBuckets[day.day] = existing
        }

        for hour in report.byHour {
            var existing = hourBuckets[hour.hour] ?? HourUsage(hour: hour.hour, usage: Usage(), turns: 0)
            existing.usage.add(hour.usage)
            existing.turns += hour.turns
            hourBuckets[hour.hour] = existing
        }

        for model in report.modelBreakdown {
            var existing = modelBuckets[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            existing.usage.add(model.usage)
            existing.turns += model.turns
            existing.events += model.events
            existing.sessions += model.sessions
            modelBuckets[model.name] = existing
        }
    }

    merged.byDay = dayBuckets.values.sorted { $0.day < $1.day }
    merged.byHour = hourBuckets.values.sorted { $0.hour < $1.hour }
    merged.modelBreakdown = modelBuckets.values.sorted { $0.usage.total > $1.usage.total }
    merged.topSessions = sessions.sorted { $0.usage.total > $1.usage.total }.prefix(8).map { $0 }
    return merged
}

private func mergedModelBreakdown(_ models: [ModelUsage]) -> [ModelUsage] {
    var buckets: [String: ModelUsage] = [:]
    for model in models {
        var existing = buckets[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
        existing.usage.add(model.usage)
        existing.turns += model.turns
        existing.events += model.events
        existing.sessions += model.sessions
        buckets[model.name] = existing
    }
    return buckets.values.sorted { $0.usage.total > $1.usage.total }
}

func mergedRepoInsightsReport(_ reports: [RepoInsightsReport], scannedAt: Date = Date(), windowDays: Int) -> RepoInsightsReport {
    var buckets: [String: RepoInsight] = [:]
    for report in reports {
        for row in report.rows {
            if var existing = buckets[row.key] {
                existing.folders.formUnion(row.folders)
                existing.conversations += row.conversations
                existing.turns += row.turns
                existing.compressions += row.compressions
                existing.tokens += row.tokens
                existing.conversationsWithCompression += row.conversationsWithCompression
                existing.longestTurns = max(existing.longestTurns, row.longestTurns)
                existing.longestTokens = max(existing.longestTokens, row.longestTokens)
                existing.maxCompressions = max(existing.maxCompressions, row.maxCompressions)
                existing.abortedTurns += row.abortedTurns
                existing.completedTurns += row.completedTurns
                existing.activeDays.formUnion(row.activeDays)
                existing.turnBuckets.short += row.turnBuckets.short
                existing.turnBuckets.medium += row.turnBuckets.medium
                existing.turnBuckets.long += row.turnBuckets.long
                existing.turnBuckets.extraLong += row.turnBuckets.extraLong
                existing.compressionBuckets.zero += row.compressionBuckets.zero
                existing.compressionBuckets.one += row.compressionBuckets.one
                existing.compressionBuckets.two += row.compressionBuckets.two
                existing.compressionBuckets.threePlus += row.compressionBuckets.threePlus
                existing.days = mergedRepoInsightDays(existing.days + row.days)
                existing.hours = mergedRepoInsightHours(existing.hours + row.hours)
                buckets[row.key] = existing
            } else {
                buckets[row.key] = row
            }
        }
    }

    let rows = buckets.values.sorted {
        if $0.compressions != $1.compressions {
            return $0.compressions > $1.compressions
        }
        if $0.conversations != $1.conversations {
            return $0.conversations > $1.conversations
        }
        if $0.tokens != $1.tokens {
            return $0.tokens > $1.tokens
        }
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
    return RepoInsightsReport(
        rows: rows,
        scannedAt: scannedAt,
        windowDays: windowDays,
        reasoning: mergedReasoningInsightsReports(reports.map(\.reasoning))
    )
}

private func mergedRepoInsightDays(_ days: [RepoInsightDay]) -> [RepoInsightDay] {
    var buckets: [String: RepoInsightDay] = [:]
    for day in days {
        var existing = buckets[day.day] ?? RepoInsightDay(day: day.day, conversations: 0, turns: 0, compressions: 0)
        existing.conversations += day.conversations
        existing.turns += day.turns
        existing.compressions += day.compressions
        buckets[day.day] = existing
    }
    return buckets.values.sorted { $0.day < $1.day }
}

private func mergedRepoInsightHours(_ hours: [RepoInsightHour]) -> [RepoInsightHour] {
    var buckets: [Int: RepoInsightHour] = [:]
    for hour in hours {
        var existing = buckets[hour.hour] ?? RepoInsightHour(hour: hour.hour, conversations: 0, turns: 0, tokens: 0)
        existing.conversations += hour.conversations
        existing.turns += hour.turns
        existing.tokens += hour.tokens
        buckets[hour.hour] = existing
    }
    return buckets.values.sorted { $0.hour < $1.hour }
}

func profileReportWithLocalFallback(_ profileReport: TokenReport, localReport: TokenReport?) -> TokenReport {
    guard let localReport, !profileReport.byDay.isEmpty, !localReport.byDay.isEmpty else {
        return profileReport
    }

    var localByDay: [String: DayUsage] = [:]
    for day in localReport.byDay {
        localByDay[day.day] = day
    }

    var merged = profileReport
    var localReplacementUsage = Usage()
    var replacedProfileTotal: Int64 = 0
    var fallbackTurns = 0
    var fallbackModels: [String: ModelUsage] = [:]
    var didFallback = false

    merged.byDay = profileReport.byDay.map { profileDay in
        guard let localDay = localByDay[profileDay.day],
              profileDay.usage.total < localDay.usage.total,
              localDay.usage.total > 0 else {
            return profileDay
        }

        didFallback = true
        replacedProfileTotal += profileDay.usage.total
        localReplacementUsage.add(localDay.usage)
        fallbackTurns += localDay.turns
        for model in localDay.modelBreakdown {
            var existing = fallbackModels[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            existing.usage.add(model.usage)
            existing.turns += model.turns
            existing.events += model.events
            existing.sessions += model.sessions
            fallbackModels[model.name] = existing
        }
        return DayUsage(
            day: profileDay.day,
            usage: localDay.usage,
            turns: localDay.turns,
            sessions: localDay.sessions,
            events: localDay.events,
            modelBreakdown: localDay.modelBreakdown
        )
    }

    guard didFallback else { return profileReport }

    merged.usage.total = max(0, merged.usage.total - replacedProfileTotal)
    merged.usage.add(localReplacementUsage)
    merged.turns += fallbackTurns
    if !fallbackModels.isEmpty {
        var modelsByName: [String: ModelUsage] = [:]
        for model in merged.modelBreakdown {
            modelsByName[model.name] = model
        }
        for model in fallbackModels.values {
            var existing = modelsByName[model.name] ?? ModelUsage(name: model.name, usage: Usage(), events: 0, sessions: 0)
            existing.usage.add(model.usage)
            existing.turns += model.turns
            existing.events += model.events
            existing.sessions += model.sessions
            modelsByName[model.name] = existing
        }
        merged.modelBreakdown = modelsByName.values.sorted { $0.usage.total > $1.usage.total }
    }
    return merged
}

func codexProfileReport(window: WindowOption, accountUsage: AccountUsageSnapshot, localCodexReport: TokenReport?) -> TokenReport {
    let report: TokenReport
    if window == .day {
        let todayReport = accountUsage.report(days: 1)
        if todayReport.usage.total == 0, localCodexReport?.usage.total ?? 0 > 0 {
            report = todayReport
        } else {
            report = accountUsage.report(window: window)
        }
    } else {
        report = accountUsage.report(window: window)
    }
    return profileReportWithLocalFallback(report, localReport: localCodexReport)
}

func profileBackedReport(
    window: WindowOption,
    quota: QuotaViewOption,
    accountUsage: AccountUsageSnapshot?,
    localReport: TokenReport?,
    localCodexReport: TokenReport?,
    localClaudeReport: TokenReport?
) -> TokenReport? {
    guard quota.usesCodexProfileAPI,
          let accountUsage,
          accountUsage.hasData else {
        return nil
    }

    let codexLocalReport = quota == .codex ? localReport : localCodexReport
    let codexProfile = codexProfileReport(window: window, accountUsage: accountUsage, localCodexReport: codexLocalReport)
    guard quota == .all else {
        return codexProfile
    }

    if let localClaudeReport {
        return mergedTokenReport([codexProfile, localClaudeReport])
    }

    if let localReport, let localCodexReport {
        var combined = codexProfile
        combined.usage.total += max(0, localReport.usage.total - localCodexReport.usage.total)
        combined.scannedAt = max(codexProfile.scannedAt, localReport.scannedAt)
        return combined
    }

    return codexProfile
}

struct DashboardState {
    var report = TokenReport()
    var codexReport: TokenReport?
    var claudeReport: TokenReport?
    var apiReport: TokenReport?
    var profileReport: TokenReport?
    var accountUsage: AccountUsageSnapshot?
    var costReferenceReport: TokenReport?
    var liveLimits: [LiveRateLimit] = []
    var resetCredits: RateLimitResetCreditsSnapshot?
    var serviceStatus: CodexServiceStatusSnapshot?
    var claudeServiceStatus: CodexServiceStatusSnapshot?
    var selectedWindow: WindowOption = .week
    var selectedQuota: QuotaViewOption = .all
    var nextRefreshAt = Date()
    var isLoading = false
    var error: String?
}

struct PlanCostEstimate {
    let monthlyCost: Double
    let weeklyBudget: Double
    let weeklyQuotaTotal: Double
    let todayValue: Double
    let selectedDayValue: Double
    let weeklyUsedValue: Double
    let weeklyUnusedValue: Double
    let totalSpentValue: Double
    let totalWastedValue: Double
    let selectedDayQuotaPercent: Double
}

struct MonthlySpendRow {
    let month: String
    let usedValue: Double
    let usedPercentOfPlan: Double
}

struct CostPeriodRow {
    let label: String
    let title: String
    let subtitle: String?
    let usedValue: Double
    let remainingValue: Double
    let budgetValue: Double
    let apiEquivalentUSD: Double?
    let apiEquivalentCoveragePercent: Double
    let hasData: Bool
    let isFuture: Bool
    let isShortCycle: Bool
    let cycleIndex: Int

    var usedPercent: Double {
        guard budgetValue > 0 else { return 0 }
        return min(999, max(0, usedValue / budgetValue * 100))
    }
}

struct CostEstimator {
    private static let historicalFullWeekPeakShare = 0.45

    let report: TokenReport
    let monthlyCost: Double
    let weeklyBudget: Double
    let weeklyReferenceTotal: Double
    let weekly: RateWindow?
    let limitID: String?
    let weeklyBuckets: [Date: Int64]
    let weeklyActiveDays: [Date: Int]
    let recentWeekTotal: Int64
    let startDay: String

    init?(report: TokenReport, limit: LiveRateLimit?, quotaReferenceReport: TokenReport? = nil, monthlyCost: Double = AppSettings.monthlyPlanCost, paymentStartDay: String? = AppSettings.paymentStartDay) {
        guard monthlyCost > 0 else { return nil }
        let startDay = effectivePaymentStartDay(in: report, paymentStartDay: paymentStartDay)
        let weekly = limit?.secondary
        let weeklyBuckets = Self.weeklyUsageBuckets(days: report.byDay, startDay: startDay)
        let weeklyActiveDays = Self.weeklyActiveDayCounts(days: report.byDay, startDay: startDay)
        let recentWeekTotal = Array(report.byDay.suffix(7)).reduce(Int64(0)) { $0 + $1.usage.total }
        guard weeklyBuckets.values.contains(where: { $0 > 0 }),
              let weeklyReferenceTotal = Self.weeklyReferenceTotal(days: report.byDay, startDay: startDay, weekly: weekly, quotaReferenceTotal: quotaReferenceReport?.usage.total),
              weeklyReferenceTotal > 0 else {
            return nil
        }
        self.report = report
        self.monthlyCost = monthlyCost
        self.weeklyBudget = monthlyCost * 12 / 52
        self.weeklyReferenceTotal = weeklyReferenceTotal
        self.weekly = weekly
        self.limitID = limit?.id
        self.weeklyBuckets = weeklyBuckets
        self.weeklyActiveDays = weeklyActiveDays
        self.recentWeekTotal = recentWeekTotal
        self.startDay = startDay
    }

    static func weeklyUsageBuckets(days: [DayUsage], startDay: String? = nil) -> [Date: Int64] {
        let calendar = appCalendar()
        let parser = dayFormatter()
        var buckets: [Date: Int64] = [:]
        for day in days where startDay.map({ day.day >= $0 }) ?? true && day.usage.total > 0 {
            guard let date = parser.date(from: day.day),
                  let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            buckets[start, default: 0] += day.usage.total
        }
        return buckets
    }

    static func weeklyActiveDayCounts(days: [DayUsage], startDay: String? = nil) -> [Date: Int] {
        let calendar = appCalendar()
        let parser = dayFormatter()
        var buckets: [Date: Int] = [:]
        for day in days where startDay.map({ day.day >= $0 }) ?? true && day.usage.total > 0 {
            guard let date = parser.date(from: day.day),
                  let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            buckets[start, default: 0] += 1
        }
        return buckets
    }

    static func weeklyReferenceTotal(days: [DayUsage], startDay: String? = nil, weekly: RateWindow?, quotaReferenceTotal: Int64? = nil) -> Double? {
        let buckets = weeklyUsageBuckets(days: days, startDay: startDay)
        guard let peakHistoricalTotal = buckets.values.max(), peakHistoricalTotal > 0 else {
            return nil
        }

        let quotaReferenceTotal = quotaReferenceTotal ?? 0
        if quotaReferenceTotal > 0,
           let weekly,
           weekly.usedPercent > 0 {
            let liveCalibratedTotal = Double(quotaReferenceTotal) / max(weekly.usedPercent / 100, 0.0001)
            return max(Double(peakHistoricalTotal), liveCalibratedTotal)
        }

        let calendar = appCalendar()
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let currentWeekTotal = buckets[currentWeekStart] ?? 0
        if buckets.count <= 1,
           currentWeekTotal > 0,
           let weekly,
           weekly.usedPercent > 0 {
            return Double(currentWeekTotal) / max(weekly.usedPercent / 100, 0.0001)
        }

        guard let weekly,
              weekly.usedPercent >= 10,
              currentWeekTotal > 0 else {
            return Double(peakHistoricalTotal)
        }
        let liveCalibratedTotal = Double(currentWeekTotal) / max(weekly.usedPercent / 100, 0.0001)
        return max(Double(peakHistoricalTotal), liveCalibratedTotal)
    }

    func value(for usage: Usage) -> Double {
        value(forTotal: usage.total)
    }

    func value(forDay day: DayUsage) -> Double {
        tokenValue(forDayKey: day.day, usage: day.usage)
    }

    func tokenValue(forDayKey dayKey: String, usage: Usage) -> Double {
        guard usage.total > 0,
              let date = dayFormatter().date(from: dayKey),
              let weekStart = appCalendar().dateInterval(of: .weekOfYear, for: date)?.start else {
            return value(for: usage)
        }
        let weekTotal = weeklyBuckets[weekStart] ?? 0
        guard weekTotal > 0 else {
            return value(for: usage)
        }
        let weekValue = tokenEstimatedWeeklyValue(forWeekStart: weekStart, total: weekTotal)
        return weekValue * Double(usage.total) / Double(weekTotal)
    }

    func value(forTotal total: Int64) -> Double {
        weeklyBudget * Double(total) / weeklyReferenceTotal
    }

    func quotaPercent(for usage: Usage) -> Double {
        quotaPercent(forTotal: usage.total)
    }

    func quotaPercent(forTotal total: Int64) -> Double {
        Double(total) / weeklyReferenceTotal * 100
    }

    func weeklyUsedValue() -> Double {
        let total = weeklyBuckets[currentWeekStart] ?? recentWeekTotal
        return currentWeeklyUsedValue(total: total)
    }

    func weeklyUnusedValue() -> Double {
        max(0, weeklyBudget - weeklyUsedValue())
    }

    func weeklyUsedValue(forWeekStart start: Date, total: Int64) -> Double {
        if start == currentWeekStart {
            return currentWeeklyUsedValue(total: total)
        }
        return localWeeklyUsedValue(forWeekStart: start, total: total)
    }

    func weeklyUnusedValue(forWeekStart start: Date, total: Int64) -> Double {
        max(0, weeklyBudget - weeklyUsedValue(forWeekStart: start, total: total))
    }

    func tokenEstimatedWeeklyValue(forWeekStart start: Date, total: Int64) -> Double {
        localWeeklyUsedValue(forWeekStart: start, total: total)
    }

    func monthlyUsedValues() -> [String: Double] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = "yyyy-MM"

        var values: [String: Double] = [:]
        var starts = Set(weeklyBuckets.keys)
        if weeklyUsedValue() > 0 {
            starts.insert(currentWeekStart)
        }

        for start in starts {
            let total = weeklyBuckets[start] ?? 0
            let usedValue = weeklyUsedValue(forWeekStart: start, total: total)
            guard usedValue > 0 else { continue }
            values[formatter.string(from: start), default: 0] += usedValue
        }
        return values
    }

    func totalSpentValue() -> Double {
        var starts = Set(weeklyBuckets.keys)
        if weeklyUsedValue() > 0 {
            starts.insert(currentWeekStart)
        }
        return starts.reduce(0.0) { partial, start in
            partial + weeklyUsedValue(forWeekStart: start, total: weeklyBuckets[start] ?? 0)
        }
    }

    private var currentWeekStart: Date {
        let calendar = appCalendar()
        return calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
    }

    private func currentWeeklyUsedValue(total: Int64) -> Double {
        guard let weekly else {
            return localWeeklyUsedValue(forWeekStart: currentWeekStart, total: total)
        }
        let liveValue = weeklyBudget * max(0, weekly.usedPercent) / 100
        return min(weeklyBudget, liveValue)
    }

    private func localWeeklyUsedValue(forWeekStart start: Date, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        let localValue: Double
        if isHistoricalFullWeek(start: start, total: total) {
            localValue = weeklyBudget
        } else {
            localValue = min(weeklyBudget, value(forTotal: total))
        }
        if start < currentWeekStart,
           let limitID,
           let recordedPercent = CostHistoryStore.shared.maxUsedPercent(limitID: limitID, weekStart: start),
           recordedPercent > 0 {
            let recordedValue = weeklyBudget * min(100, recordedPercent) / 100
            return max(localValue, recordedValue)
        }
        return localValue
    }

    private func isHistoricalFullWeek(start: Date, total: Int64) -> Bool {
        guard start < currentWeekStart,
              total > 0,
              (weeklyActiveDays[start] ?? 0) >= 7,
              let peak = weeklyBuckets.values.max(),
              peak > 0 else {
            return false
        }
        return Double(total) >= Double(peak) * Self.historicalFullWeekPeakShare
    }

}
