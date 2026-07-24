import Foundation

enum ThreadRunStatus {
    case running
    case stale
    case waiting
    case unread
}

enum CodexThreadKind: String {
    case root
    case subtask
    case automation
}

enum TaskPlanStepStatus: String {
    case pending
    case inProgress = "in_progress"
    case completed
}

struct TaskPlanStep {
    let text: String
    let status: TaskPlanStepStatus
}

struct TaskPlan {
    let explanation: String?
    let steps: [TaskPlanStep]

    var completedCount: Int {
        steps.filter { $0.status == .completed }.count
    }

    var activeIndex: Int? {
        steps.firstIndex { $0.status == .inProgress }
    }

    var displayedStepNumber: Int {
        activeIndex.map { $0 + 1 } ?? min(completedCount + 1, max(steps.count, 1))
    }

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return min(1, max(0, Double(displayedStepNumber) / Double(steps.count)))
    }

    var currentStepText: String? {
        if let activeIndex {
            return steps[activeIndex].text
        }
        return steps.first(where: { $0.status == .pending })?.text
            ?? steps.last?.text
    }
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
    let codexUpdatedAt: Date?
    let tokensUsed: Int?
    let tokenBreakdown: TokenBreakdown
    let model: String?
    let threadKind: CodexThreadKind
    let parentThreadID: String?
    let agentNickname: String?
    let agentPath: String?
    let plan: TaskPlan?

    var isSubtask: Bool {
        threadKind == .subtask
    }

    var isInternalApprovalSubtask: Bool {
        guard isSubtask,
              agentNickname == nil,
              agentPath == nil,
              let preview else {
            return false
        }
        if let data = preview.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["outcome"] is String {
            return true
        }
        // App-server previews may be truncated before Task Bar receives them.
        return preview.hasPrefix("{") && preview.contains(#""outcome":"#)
    }
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
