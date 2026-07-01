import Foundation

enum ThreadRunStatus {
    case running
    case stale
    case waiting
    case unread
}

struct CodexThreadItem {
    let id: String
    let title: String
    let preview: String?
    let cwd: String?
    let lastActivity: Date
    let startedAt: Date?
    let externalReadAt: Date?
    let status: ThreadRunStatus
    let turns: Int
    let compressionCount: Int?
    let source: String
    let isExplicitUnread: Bool
    let tokensUsed: Int?
    let tokenBreakdown: TokenBreakdown
    let model: String?
}

struct TokenBreakdown {
    var input: Int = 0
    var cachedInput: Int = 0
    var output: Int = 0
    var reasoningOutput: Int = 0
    var total: Int = 0
    var hasDetailedCounters = false

    var hasAny: Bool {
        input > 0 || cachedInput > 0 || output > 0 || reasoningOutput > 0 || total > 0
    }

    var displayTotal: Int? {
        if total > 0 { return total }
        let inferred = input + output
        return inferred > 0 ? inferred : nil
    }

    static func totalOnly(_ value: Int?) -> TokenBreakdown {
        guard let value, value > 0 else { return TokenBreakdown() }
        return TokenBreakdown(total: value)
    }

    static func delta(from previous: TokenBreakdown, to current: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: max(0, current.input - previous.input),
            cachedInput: max(0, current.cachedInput - previous.cachedInput),
            output: max(0, current.output - previous.output),
            reasoningOutput: max(0, current.reasoningOutput - previous.reasoningOutput),
            total: max(0, current.total - previous.total),
            hasDetailedCounters: current.hasDetailedCounters
        )
    }

    mutating func add(_ other: TokenBreakdown) {
        input += other.input
        cachedInput += other.cachedInput
        output += other.output
        reasoningOutput += other.reasoningOutput
        total += other.total
        hasDetailedCounters = hasDetailedCounters || other.hasDetailedCounters
    }

    func resolved(with fallback: TokenBreakdown) -> TokenBreakdown {
        guard hasAny || hasDetailedCounters else { return fallback }
        guard total == 0, fallback.total > 0 else { return self }
        var result = self
        result.total = fallback.total
        return result
    }
}
