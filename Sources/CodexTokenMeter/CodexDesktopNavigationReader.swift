import Foundation

enum CodexDesktopComposerContext: Equatable {
    case projectless
    case projectSelected
    case unknown
}

/// Reads only Sentry UI-click selectors emitted by Codex Desktop. The persisted
/// `selected-project` value is intentionally not enough: Codex leaves the last
/// project there after the user returns to the projectless New chat screen.
/// Prompt text, input breadcrumbs, and console payloads are never retained.
struct CodexDesktopNavigationReader {
    private struct Envelope: Decodable {
        struct Scope: Decodable {
            let breadcrumbs: [Breadcrumb]
        }

        struct Breadcrumb: Decodable {
            let category: String?
            let message: String?
        }

        let scope: Scope
    }

    let scopeURL: URL

    func currentComposerContext() -> CodexDesktopComposerContext {
        guard let data = try? Data(contentsOf: scopeURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return .unknown
        }
        return Self.composerContext(
            from: envelope.scope.breadcrumbs.map { ($0.category, $0.message) }
        )
    }

    static func composerContext(
        from breadcrumbs: [(category: String?, message: String?)]
    ) -> CodexDesktopComposerContext {
        var context = CodexDesktopComposerContext.unknown
        var projectPickerWasOpened = false

        for breadcrumb in breadcrumbs {
            guard breadcrumb.category == "ui.click",
                  let message = breadcrumb.message else {
                continue
            }
            if isProjectlessNewChat(message) {
                context = .projectless
                projectPickerWasOpened = false
                continue
            }
            if isProjectPickerTrigger(message) {
                projectPickerWasOpened = true
                continue
            }
            if projectPickerWasOpened {
                // The next click after opening the project picker is its
                // selection. Codex then updates selected-project with the ID.
                context = .projectSelected
                projectPickerWasOpened = false
            }
        }
        return context
    }

    private static func isProjectlessNewChat(_ message: String) -> Bool {
        message.contains("aria-label=\"New chat\"")
    }

    private static func isProjectPickerTrigger(_ message: String) -> Bool {
        message.contains("aria-label=\"Choose project\"")
            || message.contains("aria-label=\"Change project:")
            || message.contains("data-composer-navigation-target=\"workspace-project\"")
    }
}
