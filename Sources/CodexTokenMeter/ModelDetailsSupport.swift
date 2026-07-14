import Cocoa

enum ModelListSortOption: String, CaseIterable, Hashable {
    case name
    case share
    case total
    case input
    case output
    case sessions
    case events
    case apiCost
}

enum ModelListSortDirection: String, Hashable {
    case ascending
    case descending
}

struct ModelListPresentation {
    let models: [ModelUsage]
    let knownModelCount: Int
    let hiddenUnknownCount: Int
    let knownTokens: Int64
    let allModelTokens: Int64
    let pricedTokens: Int64
    let unpricedModelCount: Int

    var identificationCoveragePercent: Double {
        guard allModelTokens > 0 else { return 0 }
        return Double(knownTokens) / Double(allModelTokens) * 100
    }

    var pricingCoveragePercent: Double {
        guard knownTokens > 0 else { return 0 }
        return Double(pricedTokens) / Double(knownTokens) * 100
    }

    var tableHeight: CGFloat {
        max(CGFloat(132), CGFloat(112 + models.count * 20))
    }

    static func make(
        report: TokenReport,
        query: String,
        sort: ModelListSortOption,
        direction: ModelListSortDirection
    ) -> ModelListPresentation {
        let allModels = report.modelBreakdown
        let knownModels = allModels.filter { !isUnknownModelName($0.name) }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var visibleModels = normalizedQuery.isEmpty
            ? knownModels
            : knownModels.filter { $0.name.localizedCaseInsensitiveContains(normalizedQuery) }

        visibleModels.sort { lhs, rhs in
            let comparison: ComparisonResult
            switch sort {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .share, .total:
                comparison = compare(lhs.usage.total, rhs.usage.total)
            case .input:
                comparison = compare(lhs.usage.input, rhs.usage.input)
            case .output:
                comparison = compare(lhs.usage.output, rhs.usage.output)
            case .sessions:
                comparison = compare(lhs.sessions, rhs.sessions)
            case .events:
                comparison = compare(lhs.events, rhs.events)
            case .apiCost:
                let left = APICostEstimator.estimate(usage: lhs.usage, modelName: lhs.name).usdValue
                let right = APICostEstimator.estimate(usage: rhs.usage, modelName: rhs.name).usdValue
                comparison = compare(left, right)
            }
            if comparison != .orderedSame {
                return direction == .ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let knownTokens = knownModels.reduce(Int64(0)) { $0 + $1.usage.total }
        let allModelTokens = allModels.reduce(Int64(0)) { $0 + $1.usage.total }
        var pricedTokens: Int64 = 0
        var unpricedModelCount = 0
        for model in knownModels {
            let estimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            pricedTokens += estimate.pricedTokens
            if model.usage.total > 0 && !estimate.hasPricedUsage {
                unpricedModelCount += 1
            }
        }

        return ModelListPresentation(
            models: visibleModels,
            knownModelCount: knownModels.count,
            hiddenUnknownCount: allModels.count - knownModels.count,
            knownTokens: knownTokens,
            allModelTokens: allModelTokens,
            pricedTokens: pricedTokens,
            unpricedModelCount: unpricedModelCount
        )
    }
}

private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
    if lhs < rhs { return .orderedAscending }
    if lhs > rhs { return .orderedDescending }
    return .orderedSame
}

private func isUnknownModelName(_ rawName: String) -> Bool {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return name == "unknown" || name == "unknown model" || name == "(unknown)"
}

final class ModelDetailsControls: NSObject, NSSearchFieldDelegate {
    let searchField = NSSearchField()
    private(set) var query = ""
    private(set) var sort: ModelListSortOption = .total
    private(set) var direction: ModelListSortDirection = .descending
    var onChange: (() -> Void)?

    func install(in view: NSView, inputSurfaceColor: NSColor) {
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 11)
        searchField.isHidden = true
        searchField.appearance = NSAppearance(named: .darkAqua)
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        view.addSubview(searchField)
    }

    func layout(content: NSRect, tableY: CGFloat, visible: Bool) {
        searchField.isHidden = !visible
        guard visible else { return }

        let searchWidth = min(CGFloat(210), max(CGFloat(150), content.width * 0.18))
        searchField.frame = NSRect(x: content.maxX - searchWidth - 16, y: tableY + 8, width: searchWidth, height: 26)
        searchField.placeholderString = t(.modelSearchPlaceholder)
        searchField.setAccessibilityLabel(t(.modelSearchPlaceholder))
    }

    func configure(query: String?, sort rawSort: String?) {
        if let query {
            self.query = query
            searchField.stringValue = query
        }
        if let rawSort {
            let parts = rawSort.split(separator: "-", maxSplits: 1).map(String.init)
            let legacyOption = rawSort == "tokens" ? ModelListSortOption.total : nil
            if let option = legacyOption ?? ModelListSortOption(rawValue: parts[0]) {
                sort = option
                if parts.count == 2 {
                    direction = parts[1] == "asc" ? .ascending : .descending
                } else {
                    direction = option == .name ? .ascending : .descending
                }
            }
        }
        onChange?()
    }

    func toggleSort(_ option: ModelListSortOption) {
        if sort == option {
            direction = direction == .ascending ? .descending : .ascending
        } else {
            sort = option
            direction = .ascending
        }
        onChange?()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        query = field.stringValue
        onChange?()
    }
}
