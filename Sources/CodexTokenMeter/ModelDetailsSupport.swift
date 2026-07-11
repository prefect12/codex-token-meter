import Cocoa

enum ModelListSortOption: Int, CaseIterable {
    case tokens
    case apiCost
    case name

    var title: String {
        switch self {
        case .tokens: return t(.modelSortTokens)
        case .apiCost: return t(.modelSortCost)
        case .name: return t(.modelSortName)
        }
    }
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

    static func make(report: TokenReport, query: String, sort: ModelListSortOption) -> ModelListPresentation {
        let allModels = report.modelBreakdown
        let knownModels = allModels.filter { !isUnknownModelName($0.name) }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var visibleModels = normalizedQuery.isEmpty
            ? knownModels
            : knownModels.filter { $0.name.localizedCaseInsensitiveContains(normalizedQuery) }

        visibleModels.sort { lhs, rhs in
            switch sort {
            case .tokens:
                if lhs.usage.total != rhs.usage.total { return lhs.usage.total > rhs.usage.total }
            case .apiCost:
                let left = APICostEstimator.estimate(usage: lhs.usage, modelName: lhs.name).usdValue
                let right = APICostEstimator.estimate(usage: rhs.usage, modelName: rhs.name).usdValue
                if left != right { return left > right }
            case .name:
                let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
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

private func isUnknownModelName(_ rawName: String) -> Bool {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return name == "unknown" || name == "unknown model" || name == "(unknown)"
}

final class ModelDetailsControls: NSObject, NSSearchFieldDelegate {
    let sortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let searchField = NSSearchField()
    private(set) var query = ""
    private(set) var sort: ModelListSortOption = .tokens
    var onChange: (() -> Void)?

    func install(in view: NSView, inputSurfaceColor: NSColor) {
        sortPopup.controlSize = .small
        sortPopup.font = .systemFont(ofSize: 11, weight: .semibold)
        sortPopup.isBordered = false
        sortPopup.isHidden = true
        sortPopup.wantsLayer = true
        sortPopup.layer?.cornerRadius = 7
        sortPopup.layer?.backgroundColor = inputSurfaceColor.cgColor
        sortPopup.appearance = NSAppearance(named: .darkAqua)
        sortPopup.target = self
        sortPopup.action = #selector(sortChanged)
        view.addSubview(sortPopup)

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
        sortPopup.isHidden = !visible
        searchField.isHidden = !visible
        guard visible else { return }

        let searchWidth = min(CGFloat(210), max(CGFloat(150), content.width * 0.18))
        searchField.frame = NSRect(x: content.maxX - searchWidth - 16, y: tableY + 8, width: searchWidth, height: 26)
        let sortWidth: CGFloat = 142
        sortPopup.frame = NSRect(x: searchField.frame.minX - 10 - sortWidth, y: tableY + 7, width: sortWidth, height: 28)

        let titles = ModelListSortOption.allCases.map(\.title)
        if sortPopup.itemArray.map(\.title) != titles {
            sortPopup.removeAllItems()
            sortPopup.addItems(withTitles: titles)
        }
        sortPopup.selectItem(at: sort.rawValue)
        searchField.placeholderString = t(.modelSearchPlaceholder)
        searchField.setAccessibilityLabel(t(.modelSearchPlaceholder))
        sortPopup.setAccessibilityLabel(t(.modelSortTokens))
    }

    func configure(query: String?, sort rawSort: String?) {
        if let query {
            self.query = query
            searchField.stringValue = query
        }
        if let rawSort,
           let option = ModelListSortOption.allCases.first(where: { String(describing: $0) == rawSort }) {
            sort = option
        }
        onChange?()
    }

    @objc private func sortChanged() {
        guard let option = ModelListSortOption(rawValue: sortPopup.indexOfSelectedItem) else { return }
        sort = option
        onChange?()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === searchField else { return }
        query = field.stringValue
        onChange?()
    }
}
