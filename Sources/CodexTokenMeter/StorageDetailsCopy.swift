import Foundation

struct StorageCategoryCopy {
    let name: String
    let purpose: String
    let impact: String
    let advice: String
}
struct StorageCopy {
    let sidebarTitle: String
    let headerTitle: String
    let headerSubtitle: String
    let totalCard: String
    let bytesSuffix: String
    let shareFormat: String
    let fileCountCard: String
    let fileCountHint: String
    let recentCard: String
    let filesFormat: String
    let sourceTitle: String
    let totalFormat: String
    let projectsTitle: String
    let colProject: String
    let colApp: String
    let colSize: String
    let colTokens: String
    let colTurns: String
    let colAdvice: String
    let adviceKeep: String
    let adviceReview: String
    let growthTitle: String
    let otherSeries: String
    let riskTitle: String
    let riskSafe: String
    let riskReview: String
    let riskAvoid: String
    let filterAll: String
    let sortBySize: String
    let sortByRecent: String
    let sortByName: String
    let searchPlaceholder: String
    let caveat: String
    let openInFinder: String
    let exportReport: String
    let refreshButton: String
    let revealInFinder: String
    let copyPath: String
    let scanningLabel: String
    let scannedAtFormat: String
    let totalLabel: String
    let noProjectsHint: String
    let emptyCategoriesHint: String
    let categories: (StorageCategoryID) -> StorageCategoryCopy

    func riskLabel(_ risk: StorageRisk) -> String {
        switch risk {
        case .safeToClear: return riskSafe
        case .reviewFirst: return riskReview
        case .doNotClean: return riskAvoid
        }
    }
}

func chineseStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
    switch id {
    case .codexSessions:
        return StorageCategoryCopy(
            name: "会话日志",
            purpose: "包含 Codex 正在使用的会话日志源数据（sessions 与 archived_sessions），用于计算 Token、会话、模型和项目级别的统计。",
            impact: "删除后将丢失对应时间段的历史记录，影响日历、趋势、模型分布、会话排行和项目洞察等所有历史统计，无法从服务端恢复。",
            advice: "仅建议清理非常旧的 archived 会话日志，并先确认不再需要历史统计。可按日期或会话文件逐步清理。"
        )
    case .codexWorktrees:
        return StorageCategoryCopy(
            name: "工作区",
            purpose: "Codex 创建或使用的 Git 工作区副本，可能包含尚未合并的代码改动。",
            impact: "直接删除可能丢失未提交或未合并的代码改动。",
            advice: "建议通过 Codex 或 Git 工作流确认没有未合并改动后再清理，不要直接整目录删除。"
        )
    case .codexBackups:
        return StorageCategoryCopy(
            name: "备份恢复",
            purpose: "备份、恢复或修复过程留下的数据（backup、recovery、log-backups 等目录）。",
            impact: "删除后无法再从这些备份中恢复对应数据。",
            advice: "先确认来源和时间。如果确定是一次性修复残留，可在 Finder 中人工确认后再删除。"
        )
    case .codexDatabase:
        return StorageCategoryCopy(
            name: "数据库",
            purpose: "Codex 内部数据库和运行状态（SQLite / WAL 文件）。",
            impact: "删除可能损坏 Codex 的内部状态，导致功能异常。",
            advice: "不建议在此清理。如果异常增长，请通过 Codex 官方途径处理。"
        )
    case .codexImages:
        return StorageCategoryCopy(
            name: "生成图片",
            purpose: "Codex 在本地生成的图片资产。",
            impact: "删除后图片无法找回，可能是你仍需要的产物。",
            advice: "先在 Finder 中浏览，确认不再需要后再删除。"
        )
    case .codexPlugins:
        return StorageCategoryCopy(
            name: "插件依赖",
            purpose: "插件与运行依赖文件。",
            impact: "删除可能破坏插件功能，需要重新安装。",
            advice: "不建议手动清理，请通过插件管理卸载。"
        )
    case .codexOther:
        return StorageCategoryCopy(
            name: "Codex 其他",
            purpose: "Codex 主目录下的其他配置与运行文件（如 auth、config、日志等）。",
            impact: "删除可能导致 Codex 需要重新登录或重新配置。",
            advice: "不建议清理。"
        )
    case .claudeProjects:
        return StorageCategoryCopy(
            name: "Claude 项目",
            purpose: "Claude Code 会话日志（projects 目录），是 Claude token 统计的源数据。",
            impact: "删除会丢失 Claude 历史统计和会话记录，无法从服务端恢复。",
            advice: "仅建议清理很旧且确认不再需要的项目日志。"
        )
    case .claudeOther:
        return StorageCategoryCopy(
            name: "Claude 其他",
            purpose: "Claude Code 的配置、插件、缓存等其他本地数据。",
            impact: "删除可能影响 Claude Code 的设置和扩展功能。",
            advice: "不建议在此清理。"
        )
    }
}

func traditionalChineseStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
    switch id {
    case .codexSessions:
        return StorageCategoryCopy(
            name: "會話日誌",
            purpose: "包含 Codex 正在使用的會話日誌源資料（sessions 與 archived_sessions），用於計算 Token、會話、模型和專案層級的統計。",
            impact: "刪除後將遺失對應時間段的歷史記錄，影響日曆、趨勢、模型分佈、會話排行和專案洞察等所有歷史統計，無法從伺服器端還原。",
            advice: "僅建議清理非常舊的 archived 會話日誌，並先確認不再需要歷史統計。可按日期或會話檔案逐步清理。"
        )
    case .codexWorktrees:
        return StorageCategoryCopy(
            name: "工作區",
            purpose: "Codex 建立或使用的 Git 工作區副本，可能包含尚未合併的程式碼變更。",
            impact: "直接刪除可能遺失未提交或未合併的程式碼變更。",
            advice: "建議透過 Codex 或 Git 工作流程確認沒有未合併變更後再清理，不要直接刪除整個目錄。"
        )
    case .codexBackups:
        return StorageCategoryCopy(
            name: "備份還原",
            purpose: "備份、還原或修復過程留下的資料（backup、recovery、log-backups 等目錄）。",
            impact: "刪除後無法再從這些備份中還原對應資料。",
            advice: "先確認來源和時間。如果確定是一次性修復殘留，可在 Finder 中人工確認後再刪除。"
        )
    case .codexDatabase:
        return StorageCategoryCopy(
            name: "資料庫",
            purpose: "Codex 內部資料庫和執行狀態（SQLite / WAL 檔案）。",
            impact: "刪除可能損壞 Codex 的內部狀態，導致功能異常。",
            advice: "不建議在此清理。如果異常增長，請透過 Codex 官方途徑處理。"
        )
    case .codexImages:
        return StorageCategoryCopy(
            name: "生成圖片",
            purpose: "Codex 在本地生成的圖片資產。",
            impact: "刪除後圖片無法找回，可能是你仍需要的產物。",
            advice: "先在 Finder 中瀏覽，確認不再需要後再刪除。"
        )
    case .codexPlugins:
        return StorageCategoryCopy(
            name: "外掛相依",
            purpose: "外掛與執行相依檔案。",
            impact: "刪除可能破壞外掛功能，需要重新安裝。",
            advice: "不建議手動清理，請透過外掛管理移除。"
        )
    case .codexOther:
        return StorageCategoryCopy(
            name: "Codex 其他",
            purpose: "Codex 主目錄下的其他設定與執行檔案（如 auth、config、日誌等）。",
            impact: "刪除可能導致 Codex 需要重新登入或重新設定。",
            advice: "不建議清理。"
        )
    case .claudeProjects:
        return StorageCategoryCopy(
            name: "Claude 專案",
            purpose: "Claude Code 會話日誌（projects 目錄），是 Claude token 統計的源資料。",
            impact: "刪除會遺失 Claude 歷史統計和會話記錄，無法從伺服器端還原。",
            advice: "僅建議清理很舊且確認不再需要的專案日誌。"
        )
    case .claudeOther:
        return StorageCategoryCopy(
            name: "Claude 其他",
            purpose: "Claude Code 的設定、外掛、快取等其他本地資料。",
            impact: "刪除可能影響 Claude Code 的設定和擴充功能。",
            advice: "不建議在此清理。"
        )
    }
}

func japaneseStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
    switch id {
    case .codexSessions:
        return StorageCategoryCopy(
            name: "セッションログ",
            purpose: "Codex が使用中の会話ログの元データ（sessions と archived_sessions）。token・セッション・モデル・プロジェクト統計の計算に使われます。",
            impact: "削除すると該当期間の履歴が失われ、カレンダー・トレンド・モデル分布などすべての履歴統計に影響します。サーバーからは復元できません。",
            advice: "非常に古い archived ログのみ、履歴統計が不要と確認してから整理してください。"
        )
    case .codexWorktrees:
        return StorageCategoryCopy(
            name: "ワークツリー",
            purpose: "Codex が作成・使用する Git ワークツリーのコピー。未マージの変更が含まれる可能性があります。",
            impact: "直接削除すると未コミット・未マージの変更が失われる可能性があります。",
            advice: "Codex または Git のワークフローで未マージ変更がないことを確認してから整理してください。"
        )
    case .codexBackups:
        return StorageCategoryCopy(
            name: "バックアップ",
            purpose: "バックアップ・リカバリ・修復処理が残したデータ（backup、recovery、log-backups など）。",
            impact: "削除するとこれらのバックアップから復元できなくなります。",
            advice: "由来と日時を確認し、一時的な残骸と確信できる場合のみ Finder で確認して削除してください。"
        )
    case .codexDatabase:
        return StorageCategoryCopy(
            name: "データベース",
            purpose: "Codex 内部のデータベースと実行状態（SQLite / WAL ファイル）。",
            impact: "削除すると Codex の内部状態が壊れ、動作不良の原因になります。",
            advice: "ここでは削除しないでください。異常に増加する場合は Codex 公式の手段で対処してください。"
        )
    case .codexImages:
        return StorageCategoryCopy(
            name: "生成画像",
            purpose: "Codex がローカルに生成した画像アセット。",
            impact: "削除すると画像は復元できません。まだ必要な成果物かもしれません。",
            advice: "Finder で内容を確認し、不要と確認してから削除してください。"
        )
    case .codexPlugins:
        return StorageCategoryCopy(
            name: "プラグイン",
            purpose: "プラグインと実行時依存ファイル。",
            impact: "削除するとプラグインが壊れ、再インストールが必要になります。",
            advice: "手動での削除は非推奨です。プラグイン管理からアンインストールしてください。"
        )
    case .codexOther:
        return StorageCategoryCopy(
            name: "Codex その他",
            purpose: "Codex ホーム配下のその他の設定・実行ファイル（auth、config、ログなど）。",
            impact: "削除すると再ログインや再設定が必要になる可能性があります。",
            advice: "削除は推奨しません。"
        )
    case .claudeProjects:
        return StorageCategoryCopy(
            name: "Claude プロジェクト",
            purpose: "Claude Code の会話ログ（projects ディレクトリ）。Claude token 統計の元データです。",
            impact: "削除すると Claude の履歴統計と会話記録が失われます。サーバーからは復元できません。",
            advice: "非常に古く、不要と確認できたログのみ整理してください。"
        )
    case .claudeOther:
        return StorageCategoryCopy(
            name: "Claude その他",
            purpose: "Claude Code の設定・プラグイン・キャッシュなどのローカルデータ。",
            impact: "削除すると Claude Code の設定や拡張機能に影響する可能性があります。",
            advice: "ここでは削除しないでください。"
        )
    }
}

func englishStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
    switch id {
    case .codexSessions:
        return StorageCategoryCopy(
            name: "Session logs",
            purpose: "Source conversation logs used by Codex (sessions and archived_sessions). They power token, session, model, and project statistics.",
            impact: "Deleting removes history for that period and breaks calendar, trends, model breakdowns, and project insights. It cannot be restored from the server.",
            advice: "Only clear very old archived session logs after confirming you no longer need the historical stats. Clean up gradually by date or file."
        )
    case .codexWorktrees:
        return StorageCategoryCopy(
            name: "Worktrees",
            purpose: "Git worktree copies created or used by Codex. They may contain unmerged code changes.",
            impact: "Deleting directly may lose uncommitted or unmerged changes.",
            advice: "Verify there are no unmerged changes via Codex or Git before cleaning. Do not delete whole directories blindly."
        )
    case .codexBackups:
        return StorageCategoryCopy(
            name: "Backups & recovery",
            purpose: "Data left by backup, recovery, or repair runs (backup, recovery, log-backups directories).",
            impact: "After deletion the data can no longer be restored from these backups.",
            advice: "Confirm the origin and date first. If it is a one-off repair leftover, review it in Finder before deleting."
        )
    case .codexDatabase:
        return StorageCategoryCopy(
            name: "Databases",
            purpose: "Codex internal databases and runtime state (SQLite / WAL files).",
            impact: "Deleting can corrupt Codex internal state and break functionality.",
            advice: "Do not clean here. If it grows abnormally, resolve through official Codex channels."
        )
    case .codexImages:
        return StorageCategoryCopy(
            name: "Generated images",
            purpose: "Image assets generated locally by Codex.",
            impact: "Deleted images cannot be recovered and may be assets you still need.",
            advice: "Browse them in Finder and confirm they are no longer needed before deleting."
        )
    case .codexPlugins:
        return StorageCategoryCopy(
            name: "Plugins & deps",
            purpose: "Plugins and runtime dependency files.",
            impact: "Deleting may break plugins and require reinstalling.",
            advice: "Not recommended to clean manually; uninstall through plugin management."
        )
    case .codexOther:
        return StorageCategoryCopy(
            name: "Codex other",
            purpose: "Other config and runtime files under the Codex home (auth, config, logs, etc.).",
            impact: "Deleting may force Codex to re-login or be reconfigured.",
            advice: "Cleaning is not recommended."
        )
    case .claudeProjects:
        return StorageCategoryCopy(
            name: "Claude projects",
            purpose: "Claude Code session logs (projects directory). They are the source data for Claude token statistics.",
            impact: "Deleting loses Claude history stats and conversation records. It cannot be restored from the server.",
            advice: "Only clear very old project logs after confirming they are no longer needed."
        )
    case .claudeOther:
        return StorageCategoryCopy(
            name: "Claude other",
            purpose: "Claude Code config, plugins, cache, and other local data.",
            impact: "Deleting may affect Claude Code settings and extensions.",
            advice: "Do not clean here."
        )
    }
}

extension AppLanguage {
    var storageCopy: StorageCopy {
        switch self {
        case .chinese:
            return StorageCopy(
                sidebarTitle: "空间",
                headerTitle: "空间详情",
                headerSubtitle: "按来源、项目和类型追踪本地占用",
                totalCard: "总和",
                bytesSuffix: "字节",
                shareFormat: "占 %@",
                fileCountCard: "文件数",
                fileCountHint: "包含所有来源",
                recentCard: "最近 14 天新增",
                filesFormat: "%@ 个文件",
                sourceTitle: "来源分布（按占用大小）",
                totalFormat: "总计 %@",
                projectsTitle: "最大项目（按占用）",
                colProject: "项目",
                colApp: "应用",
                colSize: "占用",
                colTokens: "Token",
                colTurns: "轮次",
                colAdvice: "建议",
                adviceKeep: "保留",
                adviceReview: "谨慎清理",
                growthTitle: "近 14 天增长（按实际磁盘占用）",
                otherSeries: "其他",
                riskTitle: "风险构成",
                riskSafe: "可安全清理",
                riskReview: "需确认",
                riskAvoid: "不建议清理",
                filterAll: "全部分类",
                sortBySize: "按占用大小",
                sortByRecent: "按最近活跃",
                sortByName: "按名称",
                searchPlaceholder: "筛选路径或项目",
                caveat: "大小为实际磁盘占用，统计口径可能与应用用量不同。",
                openInFinder: "在访达中打开",
                exportReport: "导出报告…",
                refreshButton: "刷新",
                revealInFinder: "在 Finder 中显示",
                copyPath: "复制路径",
                scanningLabel: "正在扫描本地占用…",
                scannedAtFormat: "扫描于 %@",
                totalLabel: "合计",
                noProjectsHint: "暂无可归因的项目数据。",
                emptyCategoriesHint: "未找到本地数据目录。",
                categories: chineseStorageCategoryCopy
            )
        case .traditionalChinese:
            return StorageCopy(
                sidebarTitle: "空間",
                headerTitle: "空間詳情",
                headerSubtitle: "按來源、專案和類型追蹤本地佔用",
                totalCard: "總和",
                bytesSuffix: "位元組",
                shareFormat: "佔 %@",
                fileCountCard: "檔案數",
                fileCountHint: "包含所有來源",
                recentCard: "最近 14 天新增",
                filesFormat: "%@ 個檔案",
                sourceTitle: "來源分佈（按佔用大小）",
                totalFormat: "總計 %@",
                projectsTitle: "最大專案（按佔用）",
                colProject: "專案",
                colApp: "應用",
                colSize: "佔用",
                colTokens: "Token",
                colTurns: "輪次",
                colAdvice: "建議",
                adviceKeep: "保留",
                adviceReview: "謹慎清理",
                growthTitle: "近 14 天增長（按實際磁碟佔用）",
                otherSeries: "其他",
                riskTitle: "風險構成",
                riskSafe: "可安全清理",
                riskReview: "需確認",
                riskAvoid: "不建議清理",
                filterAll: "全部分類",
                sortBySize: "按佔用大小",
                sortByRecent: "按最近活躍",
                sortByName: "按名稱",
                searchPlaceholder: "篩選路徑或專案",
                caveat: "大小為實際磁碟佔用，統計口徑可能與應用用量不同。",
                openInFinder: "在 Finder 中開啟",
                exportReport: "匯出報告…",
                refreshButton: "重新整理",
                revealInFinder: "在 Finder 中顯示",
                copyPath: "複製路徑",
                scanningLabel: "正在掃描本地佔用…",
                scannedAtFormat: "掃描於 %@",
                totalLabel: "合計",
                noProjectsHint: "暫無可歸因的專案資料。",
                emptyCategoriesHint: "未找到本地資料目錄。",
                categories: traditionalChineseStorageCategoryCopy
            )
        case .japanese:
            return StorageCopy(
                sidebarTitle: "ストレージ",
                headerTitle: "ストレージ詳細",
                headerSubtitle: "ソース・プロジェクト・種類別のローカル使用量",
                totalCard: "合計",
                bytesSuffix: "バイト",
                shareFormat: "%@ を占有",
                fileCountCard: "ファイル数",
                fileCountHint: "すべてのソースを含む",
                recentCard: "直近 14 日の増加",
                filesFormat: "%@ ファイル",
                sourceTitle: "ソース分布（使用量順）",
                totalFormat: "合計 %@",
                projectsTitle: "上位プロジェクト（使用量順）",
                colProject: "プロジェクト",
                colApp: "アプリ",
                colSize: "使用量",
                colTokens: "Token",
                colTurns: "ターン",
                colAdvice: "推奨",
                adviceKeep: "保持",
                adviceReview: "要確認",
                growthTitle: "直近 14 日の増加（実ディスク使用量）",
                otherSeries: "その他",
                riskTitle: "リスク構成",
                riskSafe: "安全に削除可",
                riskReview: "要確認",
                riskAvoid: "削除非推奨",
                filterAll: "すべての分類",
                sortBySize: "使用量順",
                sortByRecent: "最近の活動順",
                sortByName: "名前順",
                searchPlaceholder: "パスやプロジェクトを検索",
                caveat: "サイズは実ディスク使用量です。アプリの使用量とは基準が異なる場合があります。",
                openInFinder: "Finder で開く",
                exportReport: "レポートを書き出す…",
                refreshButton: "再スキャン",
                revealInFinder: "Finder に表示",
                copyPath: "パスをコピー",
                scanningLabel: "ローカル使用量をスキャン中…",
                scannedAtFormat: "スキャン: %@",
                totalLabel: "合計",
                noProjectsHint: "プロジェクトデータがありません。",
                emptyCategoriesHint: "ローカルデータが見つかりません。",
                categories: japaneseStorageCategoryCopy
            )
        default:
            return StorageCopy(
                sidebarTitle: "Storage",
                headerTitle: "Storage Details",
                headerSubtitle: "Track local usage by source, project, and type",
                totalCard: "Total",
                bytesSuffix: "bytes",
                shareFormat: "%@ of total",
                fileCountCard: "Files",
                fileCountHint: "All sources included",
                recentCard: "Added in last 14 days",
                filesFormat: "%@ files",
                sourceTitle: "Sources by size",
                totalFormat: "Total %@",
                projectsTitle: "Top projects by size",
                colProject: "Project",
                colApp: "App",
                colSize: "Size",
                colTokens: "Tokens",
                colTurns: "Turns",
                colAdvice: "Advice",
                adviceKeep: "Keep",
                adviceReview: "Review",
                growthTitle: "Growth in last 14 days (disk usage)",
                otherSeries: "Other",
                riskTitle: "Risk breakdown",
                riskSafe: "Safe to clear",
                riskReview: "Review first",
                riskAvoid: "Do not clean",
                filterAll: "All categories",
                sortBySize: "By size",
                sortByRecent: "By recent activity",
                sortByName: "By name",
                searchPlaceholder: "Filter path or project",
                caveat: "Sizes are actual disk usage and may differ from in-app usage metrics.",
                openInFinder: "Open in Finder",
                exportReport: "Export report…",
                refreshButton: "Rescan",
                revealInFinder: "Reveal in Finder",
                copyPath: "Copy path",
                scanningLabel: "Scanning local usage…",
                scannedAtFormat: "Scanned at %@",
                totalLabel: "Total",
                noProjectsHint: "No attributable project data yet.",
                emptyCategoriesHint: "No local data directories found.",
                categories: englishStorageCategoryCopy
            )
        }
    }
}
