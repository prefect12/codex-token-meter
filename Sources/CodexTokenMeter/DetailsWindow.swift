import Cocoa
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Details Window

struct DetailsSnapshot: Codable {
    var all: TokenReport
    var codex: TokenReport
    var claude: TokenReport
    var repoInsights: RepoInsightsReport
    var repoInsightReports: [Int: RepoInsightsReport] = [:]
    var codexRepoInsights: RepoInsightsReport = RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
    var codexRepoInsightReports: [Int: RepoInsightsReport] = [:]
    var claudeRepoInsights: RepoInsightsReport = RepoInsightsReport(rows: [], scannedAt: Date(), windowDays: 90)
    var claudeRepoInsightReports: [Int: RepoInsightsReport] = [:]
    var liveLimits: [LiveRateLimit]
    var serviceStatus: CodexServiceStatusSnapshot?
    var costReferenceReport: TokenReport?
    var accountUsage: AccountUsageSnapshot? = nil
    var resetCredits: RateLimitResetCreditsSnapshot? = nil
}

struct DetailsLoadingProgress {
    var fraction: Double
    var messageKey: L10nKey

    static let starting = DetailsLoadingProgress(fraction: 0.08, messageKey: .loadingUsageDetails)

    var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }
}

private struct InsightRecommendationText {
    let title: String
    let body: String
}

private struct InsightCopy {
    let sidebarTitle: String
    let sidebarSubtitle: String
    let headerTitle: String
    let project: String
    let conversations: String
    let compressions: String
    let average: String
    let status: String
    let emptyTitle: String
    let emptyDescription: String
    let daySuffix: String
    let daySuffixNeedsSpace: Bool
    let projectsTitle: String
    let allVisible: String
    let chatsMetric: String
    let turnsMetric: String
    let compactionsMetric: String
    let avgCompactionsMetric: String
    let maxTurnsMetric: String
    let lengthDistributionTitle: String
    let shortBucket: String
    let mediumBucket: String
    let longBucket: String
    let extraLongBucket: String
    let compactionDistributionTitle: String
    let zeroCompactions: String
    let oneCompaction: String
    let twoCompactions: String
    let threePlusCompactions: String
    let compactedSuffix: String
    let recommendationsTitle: String
    let heatmapTitle: String
    let normalLegend: String
    let highLegend: String
    let veryHighLegend: String
    let noActivityLegend: String
    let frequentCompressionRisk: String
    let longRunningRisk: String
    let wellSplitRisk: String
    let healthyRisk: String
    let recommendations: (RepoInsightRisk) -> [InsightRecommendationText]

    func windowLabel(days: Int) -> String {
        daySuffixNeedsSpace ? "\(days) \(daySuffix)" : "\(days)\(daySuffix)"
    }

    func projectCount(_ count: Int) -> String {
        "\(count) \(projectsTitle.lowercased())"
    }

    func visibleRange(start: Int, end: Int) -> String {
        AppLanguage.current.insightVisibleRange(start: start, end: end)
    }

    func compactedPercent(_ percent: Int) -> String {
        "\(percent)% \(compactedSuffix)"
    }

    func riskLabel(_ risk: RepoInsightRisk) -> String {
        switch risk {
        case .frequentCompression: return frequentCompressionRisk
        case .longRunning: return longRunningRisk
        case .wellSplit: return wellSplitRisk
        case .healthy: return healthyRisk
        }
    }
}

private extension AppLanguage {
    var insightCopy: InsightCopy {
        switch self {
        case .chinese:
            return InsightCopy(
                sidebarTitle: "洞察",
                sidebarSubtitle: "按项目和文件夹定位长线程",
                headerTitle: "Repo 对话体检",
                project: "项目",
                conversations: "对话",
                compressions: "压缩",
                average: "平均",
                status: "状态",
                emptyTitle: "暂无对话体检数据",
                emptyDescription: "本页只读取本地 Codex rollout 日志中的 cwd、turn、context_compacted 和 token_count 聚合信号。",
                daySuffix: "天",
                daySuffixNeedsSpace: true,
                projectsTitle: "个项目",
                allVisible: "显示全部",
                chatsMetric: "对话",
                turnsMetric: "turns",
                compactionsMetric: "压缩",
                avgCompactionsMetric: "平均压缩/对话",
                maxTurnsMetric: "最长 turns",
                lengthDistributionTitle: "对话长度分布（按 turns）",
                shortBucket: "短 (<10)",
                mediumBucket: "中 (10-40)",
                longBucket: "长 (41-100)",
                extraLongBucket: "超长 (>100)",
                compactionDistributionTitle: "压缩分布（每个对话的压缩次数）",
                zeroCompactions: "0 次",
                oneCompaction: "1 次",
                twoCompactions: "2 次",
                threePlusCompactions: "3+ 次",
                compactedSuffix: "有压缩",
                recommendationsTitle: "建议策略",
                heatmapTitle: "活跃天数与压缩强度（最近 90 天）",
                normalLegend: "正常（≤0.3 次/对话）",
                highLegend: "较高（0.3-1）",
                veryHighLegend: "很高（>1）",
                noActivityLegend: "无活动",
                frequentCompressionRisk: "经常压缩",
                longRunningRisk: "偏长",
                wellSplitRisk: "切分较好",
                healthyRisk: "健康",
                recommendations: chineseInsightRecommendations
            )
        case .traditionalChinese:
            return InsightCopy(
                sidebarTitle: "洞察",
                sidebarSubtitle: "按專案和資料夾定位長執行緒",
                headerTitle: "Repo 對話體檢",
                project: "專案",
                conversations: "對話",
                compressions: "壓縮",
                average: "平均",
                status: "狀態",
                emptyTitle: "暫無對話體檢資料",
                emptyDescription: "本頁只讀取本機 Codex rollout 日誌中的 cwd、turn、context_compacted 和 token_count 聚合訊號。",
                daySuffix: "天",
                daySuffixNeedsSpace: true,
                projectsTitle: "個專案",
                allVisible: "顯示全部",
                chatsMetric: "對話",
                turnsMetric: "turns",
                compactionsMetric: "壓縮",
                avgCompactionsMetric: "平均壓縮/對話",
                maxTurnsMetric: "最長 turns",
                lengthDistributionTitle: "對話長度分布（按 turns）",
                shortBucket: "短 (<10)",
                mediumBucket: "中 (10-40)",
                longBucket: "長 (41-100)",
                extraLongBucket: "超長 (>100)",
                compactionDistributionTitle: "壓縮分布（每個對話的壓縮次數）",
                zeroCompactions: "0 次",
                oneCompaction: "1 次",
                twoCompactions: "2 次",
                threePlusCompactions: "3+ 次",
                compactedSuffix: "有壓縮",
                recommendationsTitle: "建議策略",
                heatmapTitle: "活躍天數與壓縮強度（最近 90 天）",
                normalLegend: "正常（≤0.3 次/對話）",
                highLegend: "較高（0.3-1）",
                veryHighLegend: "很高（>1）",
                noActivityLegend: "無活動",
                frequentCompressionRisk: "常壓縮",
                longRunningRisk: "偏長",
                wellSplitRisk: "切分良好",
                healthyRisk: "健康",
                recommendations: traditionalChineseInsightRecommendations
            )
        case .japanese:
            return InsightCopy(
                sidebarTitle: "洞察",
                sidebarSubtitle: "プロジェクト別に長いスレッドを特定",
                headerTitle: "Repo 会話診断",
                project: "Project",
                conversations: "会話",
                compressions: "圧縮",
                average: "平均",
                status: "状態",
                emptyTitle: "会話診断データはまだありません",
                emptyDescription: "このページはローカル Codex rollout ログの cwd、turn、context_compacted、token_count 集計だけを読み取ります。",
                daySuffix: "日",
                daySuffixNeedsSpace: false,
                projectsTitle: "件",
                allVisible: "すべて表示",
                chatsMetric: "会話",
                turnsMetric: "turns",
                compactionsMetric: "圧縮",
                avgCompactionsMetric: "平均圧縮/会話",
                maxTurnsMetric: "最大 turns",
                lengthDistributionTitle: "会話長分布（turns）",
                shortBucket: "短 (<10)",
                mediumBucket: "中 (10-40)",
                longBucket: "長 (41-100)",
                extraLongBucket: "超長 (>100)",
                compactionDistributionTitle: "会話ごとの圧縮回数",
                zeroCompactions: "0回",
                oneCompaction: "1回",
                twoCompactions: "2回",
                threePlusCompactions: "3回+",
                compactedSuffix: "圧縮あり",
                recommendationsTitle: "推奨",
                heatmapTitle: "活動日と圧縮強度（直近90日）",
                normalLegend: "通常（≤0.3/会話）",
                highLegend: "高め（0.3-1）",
                veryHighLegend: "非常に高い（>1）",
                noActivityLegend: "活動なし",
                frequentCompressionRisk: "高圧縮",
                longRunningRisk: "長め",
                wellSplitRisk: "分割良好",
                healthyRisk: "健全",
                recommendations: japaneseInsightRecommendations
            )
        case .korean:
            return InsightCopy(
                sidebarTitle: "인사이트",
                sidebarSubtitle: "프로젝트별 긴 스레드 찾기",
                headerTitle: "Repo 대화 진단",
                project: "프로젝트",
                conversations: "대화",
                compressions: "압축",
                average: "평균",
                status: "상태",
                emptyTitle: "대화 진단 데이터가 없습니다",
                emptyDescription: "이 페이지는 로컬 Codex rollout 로그의 cwd, turn, context_compacted, token_count 신호만 읽습니다.",
                daySuffix: "일",
                daySuffixNeedsSpace: false,
                projectsTitle: "프로젝트",
                allVisible: "전체 표시",
                chatsMetric: "대화",
                turnsMetric: "turns",
                compactionsMetric: "압축",
                avgCompactionsMetric: "대화당 평균 압축",
                maxTurnsMetric: "최대 turns",
                lengthDistributionTitle: "turns 기준 대화 길이 분포",
                shortBucket: "짧음 (<10)",
                mediumBucket: "중간 (10-40)",
                longBucket: "김 (41-100)",
                extraLongBucket: "매우 김 (>100)",
                compactionDistributionTitle: "대화별 압축 횟수",
                zeroCompactions: "0회",
                oneCompaction: "1회",
                twoCompactions: "2회",
                threePlusCompactions: "3회+",
                compactedSuffix: "압축됨",
                recommendationsTitle: "권장 사항",
                heatmapTitle: "활동일과 압축 강도, 최근 90일",
                normalLegend: "정상 (≤0.3/대화)",
                highLegend: "높음 (0.3-1)",
                veryHighLegend: "매우 높음 (>1)",
                noActivityLegend: "활동 없음",
                frequentCompressionRisk: "압축 높음",
                longRunningRisk: "긴 대화",
                wellSplitRisk: "분리 양호",
                healthyRisk: "정상",
                recommendations: koreanInsightRecommendations
            )
        case .german:
            return InsightCopy(
                sidebarTitle: "Insights",
                sidebarSubtitle: "Lange Repo-Threads und Komprimierung finden",
                headerTitle: "Repo-Gesprächscheck",
                project: "Projekt",
                conversations: "Chats",
                compressions: "Komp.",
                average: "Ø",
                status: "Status",
                emptyTitle: "Noch keine Gesprächsdaten",
                emptyDescription: "Diese Seite liest nur cwd-, turn-, context_compacted- und token_count-Signale aus lokalen Codex-rollout-Logs.",
                daySuffix: "T",
                daySuffixNeedsSpace: false,
                projectsTitle: "Projekte",
                allVisible: "Alle sichtbar",
                chatsMetric: "Chats",
                turnsMetric: "turns",
                compactionsMetric: "Komp.",
                avgCompactionsMetric: "Ø Komp./Chat",
                maxTurnsMetric: "Max turns",
                lengthDistributionTitle: "Gesprächslänge nach turns",
                shortBucket: "Kurz (<10)",
                mediumBucket: "Mittel (10-40)",
                longBucket: "Lang (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Komprimierungen pro Gespräch",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "komprimiert",
                recommendationsTitle: "Empfehlungen",
                heatmapTitle: "Aktive Tage und Komprimierung, letzte 90 Tage",
                normalLegend: "Normal (≤0.3/Chat)",
                highLegend: "Hoch (0.3-1)",
                veryHighLegend: "Sehr hoch (>1)",
                noActivityLegend: "Keine Aktivität",
                frequentCompressionRisk: "Hohe Komp.",
                longRunningRisk: "Lang",
                wellSplitRisk: "Gut geteilt",
                healthyRisk: "Gesund",
                recommendations: germanInsightRecommendations
            )
        case .spanish:
            return InsightCopy(
                sidebarTitle: "Ideas",
                sidebarSubtitle: "Detecta hilos largos por proyecto",
                headerTitle: "Revisión de conversaciones repo",
                project: "Proyecto",
                conversations: "Chats",
                compressions: "Comp.",
                average: "Prom.",
                status: "Estado",
                emptyTitle: "Sin datos de revisión aún",
                emptyDescription: "Esta página lee solo cwd, turn, context_compacted y token_count de los logs rollout locales de Codex.",
                daySuffix: "d",
                daySuffixNeedsSpace: false,
                projectsTitle: "proyectos",
                allVisible: "Todo visible",
                chatsMetric: "Chats",
                turnsMetric: "turns",
                compactionsMetric: "Comp.",
                avgCompactionsMetric: "Comp. prom./chat",
                maxTurnsMetric: "Máx. turns",
                lengthDistributionTitle: "Distribución de longitud por turns",
                shortBucket: "Corto (<10)",
                mediumBucket: "Medio (10-40)",
                longBucket: "Largo (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Compacciones por conversación",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "compactado",
                recommendationsTitle: "Recomendaciones",
                heatmapTitle: "Días activos e intensidad, últimos 90 días",
                normalLegend: "Normal (≤0.3/chat)",
                highLegend: "Alta (0.3-1)",
                veryHighLegend: "Muy alta (>1)",
                noActivityLegend: "Sin actividad",
                frequentCompressionRisk: "Comp. alta",
                longRunningRisk: "Largo",
                wellSplitRisk: "Bien dividido",
                healthyRisk: "Sano",
                recommendations: spanishInsightRecommendations
            )
        case .french:
            return InsightCopy(
                sidebarTitle: "Insights",
                sidebarSubtitle: "Repérer les longs fils par projet",
                headerTitle: "Audit des conversations repo",
                project: "Projet",
                conversations: "Chats",
                compressions: "Comp.",
                average: "Moy.",
                status: "État",
                emptyTitle: "Aucune donnée d'audit",
                emptyDescription: "Cette page lit seulement cwd, turn, context_compacted et token_count dans les logs rollout Codex locaux.",
                daySuffix: "j",
                daySuffixNeedsSpace: false,
                projectsTitle: "projets",
                allVisible: "Tout visible",
                chatsMetric: "Chats",
                turnsMetric: "turns",
                compactionsMetric: "Comp.",
                avgCompactionsMetric: "Comp. moy./chat",
                maxTurnsMetric: "Max turns",
                lengthDistributionTitle: "Longueur des conversations par turns",
                shortBucket: "Court (<10)",
                mediumBucket: "Moyen (10-40)",
                longBucket: "Long (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Compactions par conversation",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "compactés",
                recommendationsTitle: "Recommandations",
                heatmapTitle: "Jours actifs et compaction, 90 derniers jours",
                normalLegend: "Normal (≤0.3/chat)",
                highLegend: "Élevé (0.3-1)",
                veryHighLegend: "Très élevé (>1)",
                noActivityLegend: "Aucune activité",
                frequentCompressionRisk: "Comp. haute",
                longRunningRisk: "Long",
                wellSplitRisk: "Bien scindé",
                healthyRisk: "Sain",
                recommendations: frenchInsightRecommendations
            )
        case .italian:
            return InsightCopy(
                sidebarTitle: "Insight",
                sidebarSubtitle: "Trova thread lunghi per progetto",
                headerTitle: "Controllo conversazioni repo",
                project: "Progetto",
                conversations: "Chat",
                compressions: "Comp.",
                average: "Media",
                status: "Stato",
                emptyTitle: "Nessun dato di controllo",
                emptyDescription: "Questa pagina legge solo cwd, turn, context_compacted e token_count dai log rollout locali di Codex.",
                daySuffix: "g",
                daySuffixNeedsSpace: false,
                projectsTitle: "progetti",
                allVisible: "Tutto visibile",
                chatsMetric: "Chat",
                turnsMetric: "turns",
                compactionsMetric: "Comp.",
                avgCompactionsMetric: "Comp. media/chat",
                maxTurnsMetric: "Max turns",
                lengthDistributionTitle: "Distribuzione lunghezza per turns",
                shortBucket: "Breve (<10)",
                mediumBucket: "Media (10-40)",
                longBucket: "Lunga (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Compazioni per conversazione",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "compattate",
                recommendationsTitle: "Suggerimenti",
                heatmapTitle: "Giorni attivi e compattazione, ultimi 90 giorni",
                normalLegend: "Normale (≤0.3/chat)",
                highLegend: "Alta (0.3-1)",
                veryHighLegend: "Molto alta (>1)",
                noActivityLegend: "Nessuna attività",
                frequentCompressionRisk: "Comp. alta",
                longRunningRisk: "Lunga",
                wellSplitRisk: "Ben divisa",
                healthyRisk: "Sana",
                recommendations: italianInsightRecommendations
            )
        case .portugueseBrazil:
            return InsightCopy(
                sidebarTitle: "Insights",
                sidebarSubtitle: "Encontre threads longas por projeto",
                headerTitle: "Check de conversas do repo",
                project: "Projeto",
                conversations: "Chats",
                compressions: "Comp.",
                average: "Méd.",
                status: "Status",
                emptyTitle: "Sem dados de check",
                emptyDescription: "Esta página lê apenas cwd, turn, context_compacted e token_count dos logs rollout locais do Codex.",
                daySuffix: "d",
                daySuffixNeedsSpace: false,
                projectsTitle: "projetos",
                allVisible: "Tudo visível",
                chatsMetric: "Chats",
                turnsMetric: "turns",
                compactionsMetric: "Comp.",
                avgCompactionsMetric: "Comp. méd./chat",
                maxTurnsMetric: "Máx. turns",
                lengthDistributionTitle: "Distribuição de comprimento por turns",
                shortBucket: "Curta (<10)",
                mediumBucket: "Média (10-40)",
                longBucket: "Longa (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Compactações por conversa",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "compactado",
                recommendationsTitle: "Recomendações",
                heatmapTitle: "Dias ativos e compactação, últimos 90 dias",
                normalLegend: "Normal (≤0.3/chat)",
                highLegend: "Alta (0.3-1)",
                veryHighLegend: "Muito alta (>1)",
                noActivityLegend: "Sem atividade",
                frequentCompressionRisk: "Comp. alta",
                longRunningRisk: "Longa",
                wellSplitRisk: "Bem dividida",
                healthyRisk: "Saudável",
                recommendations: portugueseInsightRecommendations
            )
        case .russian:
            return InsightCopy(
                sidebarTitle: "Инсайты",
                sidebarSubtitle: "Длинные треды по проектам",
                headerTitle: "Проверка диалогов repo",
                project: "Проект",
                conversations: "Чаты",
                compressions: "Сж.",
                average: "Сред.",
                status: "Статус",
                emptyTitle: "Нет данных проверки",
                emptyDescription: "Страница читает только cwd, turn, context_compacted и token_count из локальных rollout-логов Codex.",
                daySuffix: "д",
                daySuffixNeedsSpace: false,
                projectsTitle: "проектов",
                allVisible: "Все видны",
                chatsMetric: "Чаты",
                turnsMetric: "turns",
                compactionsMetric: "Сжатия",
                avgCompactionsMetric: "Ср. сж./чат",
                maxTurnsMetric: "Макс. turns",
                lengthDistributionTitle: "Длина диалогов по turns",
                shortBucket: "Коротк. (<10)",
                mediumBucket: "Средн. (10-40)",
                longBucket: "Длинн. (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Сжатия на диалог",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "со сжатием",
                recommendationsTitle: "Рекомендации",
                heatmapTitle: "Активные дни и сжатие, последние 90 дней",
                normalLegend: "Норма (≤0.3/чат)",
                highLegend: "Высоко (0.3-1)",
                veryHighLegend: "Очень высоко (>1)",
                noActivityLegend: "Нет активности",
                frequentCompressionRisk: "Много сж.",
                longRunningRisk: "Длинный",
                wellSplitRisk: "Разделен",
                healthyRisk: "Норма",
                recommendations: russianInsightRecommendations
            )
        case .hindi:
            return InsightCopy(
                sidebarTitle: "इनसाइट",
                sidebarSubtitle: "प्रोजेक्ट के लंबे थ्रेड पहचानें",
                headerTitle: "Repo बातचीत जांच",
                project: "प्रोजेक्ट",
                conversations: "चैट",
                compressions: "कंप्र.",
                average: "औसत",
                status: "स्थिति",
                emptyTitle: "अभी कोई जांच डेटा नहीं",
                emptyDescription: "यह पेज स्थानीय Codex rollout लॉग से केवल cwd, turn, context_compacted और token_count संकेत पढ़ता है।",
                daySuffix: "दि",
                daySuffixNeedsSpace: false,
                projectsTitle: "प्रोजेक्ट",
                allVisible: "सब दिख रहा",
                chatsMetric: "चैट",
                turnsMetric: "turns",
                compactionsMetric: "कंप्र.",
                avgCompactionsMetric: "औसत कंप्र./चैट",
                maxTurnsMetric: "अधिकतम turns",
                lengthDistributionTitle: "turns के अनुसार बातचीत लंबाई",
                shortBucket: "छोटी (<10)",
                mediumBucket: "मध्यम (10-40)",
                longBucket: "लंबी (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "हर बातचीत में compaction",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "कंप्रेस्ड",
                recommendationsTitle: "सुझाव",
                heatmapTitle: "सक्रिय दिन और compaction, पिछले 90 दिन",
                normalLegend: "सामान्य (≤0.3/चैट)",
                highLegend: "ऊंचा (0.3-1)",
                veryHighLegend: "बहुत ऊंचा (>1)",
                noActivityLegend: "गतिविधि नहीं",
                frequentCompressionRisk: "कंप्र. अधिक",
                longRunningRisk: "लंबा",
                wellSplitRisk: "अच्छा विभाजन",
                healthyRisk: "ठीक",
                recommendations: hindiInsightRecommendations
            )
        case .indonesian:
            return InsightCopy(
                sidebarTitle: "Insight",
                sidebarSubtitle: "Temukan thread panjang per proyek",
                headerTitle: "Cek percakapan repo",
                project: "Proyek",
                conversations: "Chat",
                compressions: "Komp.",
                average: "Rata2",
                status: "Status",
                emptyTitle: "Belum ada data cek",
                emptyDescription: "Halaman ini hanya membaca cwd, turn, context_compacted, dan token_count dari log rollout Codex lokal.",
                daySuffix: "h",
                daySuffixNeedsSpace: false,
                projectsTitle: "proyek",
                allVisible: "Semua terlihat",
                chatsMetric: "Chat",
                turnsMetric: "turns",
                compactionsMetric: "Komp.",
                avgCompactionsMetric: "Komp. rata/chat",
                maxTurnsMetric: "Turns maks",
                lengthDistributionTitle: "Distribusi panjang percakapan",
                shortBucket: "Pendek (<10)",
                mediumBucket: "Sedang (10-40)",
                longBucket: "Panjang (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Compaction per percakapan",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "terkompaksi",
                recommendationsTitle: "Rekomendasi",
                heatmapTitle: "Hari aktif dan compaction, 90 hari terakhir",
                normalLegend: "Normal (≤0.3/chat)",
                highLegend: "Tinggi (0.3-1)",
                veryHighLegend: "Sangat tinggi (>1)",
                noActivityLegend: "Tidak aktif",
                frequentCompressionRisk: "Komp. tinggi",
                longRunningRisk: "Panjang",
                wellSplitRisk: "Terpisah baik",
                healthyRisk: "Sehat",
                recommendations: indonesianInsightRecommendations
            )
        case .polish:
            return InsightCopy(
                sidebarTitle: "Wgląd",
                sidebarSubtitle: "Długie wątki według projektu",
                headerTitle: "Kontrola rozmów repo",
                project: "Projekt",
                conversations: "Czaty",
                compressions: "Komp.",
                average: "Śr.",
                status: "Status",
                emptyTitle: "Brak danych kontroli",
                emptyDescription: "Ta strona czyta tylko cwd, turn, context_compacted i token_count z lokalnych logów rollout Codex.",
                daySuffix: "d",
                daySuffixNeedsSpace: false,
                projectsTitle: "projektów",
                allVisible: "Wszystko widoczne",
                chatsMetric: "Czaty",
                turnsMetric: "turns",
                compactionsMetric: "Komp.",
                avgCompactionsMetric: "Śr. komp./czat",
                maxTurnsMetric: "Maks. turns",
                lengthDistributionTitle: "Długość rozmów według turns",
                shortBucket: "Krótka (<10)",
                mediumBucket: "Średnia (10-40)",
                longBucket: "Długa (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Kompakcje na rozmowę",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "skompakt.",
                recommendationsTitle: "Rekomendacje",
                heatmapTitle: "Aktywne dni i kompakcja, ostatnie 90 dni",
                normalLegend: "Normalnie (≤0.3/czat)",
                highLegend: "Wysoko (0.3-1)",
                veryHighLegend: "Bardzo wysoko (>1)",
                noActivityLegend: "Brak aktywności",
                frequentCompressionRisk: "Dużo komp.",
                longRunningRisk: "Długi",
                wellSplitRisk: "Dobrze dziel.",
                healthyRisk: "Zdrowy",
                recommendations: polishInsightRecommendations
            )
        case .ukrainian:
            return InsightCopy(
                sidebarTitle: "Інсайти",
                sidebarSubtitle: "Довгі треди за проєктами",
                headerTitle: "Перевірка розмов repo",
                project: "Проєкт",
                conversations: "Чати",
                compressions: "Стис.",
                average: "Сер.",
                status: "Стан",
                emptyTitle: "Даних перевірки ще немає",
                emptyDescription: "Сторінка читає лише cwd, turn, context_compacted і token_count з локальних rollout-логів Codex.",
                daySuffix: "д",
                daySuffixNeedsSpace: false,
                projectsTitle: "проєктів",
                allVisible: "Усе видно",
                chatsMetric: "Чати",
                turnsMetric: "turns",
                compactionsMetric: "Стис.",
                avgCompactionsMetric: "Сер. стис./чат",
                maxTurnsMetric: "Макс. turns",
                lengthDistributionTitle: "Довжина розмов за turns",
                shortBucket: "Коротка (<10)",
                mediumBucket: "Середня (10-40)",
                longBucket: "Довга (41-100)",
                extraLongBucket: "XL (>100)",
                compactionDistributionTitle: "Стиснення на розмову",
                zeroCompactions: "0x",
                oneCompaction: "1x",
                twoCompactions: "2x",
                threePlusCompactions: "3+x",
                compactedSuffix: "зі стисненням",
                recommendationsTitle: "Рекомендації",
                heatmapTitle: "Активні дні та стиснення, останні 90 днів",
                normalLegend: "Норма (≤0.3/чат)",
                highLegend: "Високо (0.3-1)",
                veryHighLegend: "Дуже високо (>1)",
                noActivityLegend: "Немає активності",
                frequentCompressionRisk: "Багато стис.",
                longRunningRisk: "Довгий",
                wellSplitRisk: "Добре поділ.",
                healthyRisk: "Здоровий",
                recommendations: ukrainianInsightRecommendations
            )
        case .english:
            return englishInsightCopy
        }
    }

    private var englishInsightCopy: InsightCopy {
        InsightCopy(
            sidebarTitle: "Insights",
            sidebarSubtitle: "Find long-running repo threads and context compaction",
            headerTitle: "Repo Conversation Check",
            project: "Project",
            conversations: "Chats",
            compressions: "Comp.",
            average: "Avg",
            status: "Status",
            emptyTitle: "No conversation check data yet",
            emptyDescription: "This page reads only local Codex rollout cwd, turn, context_compacted, and token_count signals.",
            daySuffix: "d",
            daySuffixNeedsSpace: false,
            projectsTitle: "projects",
            allVisible: "All visible",
            chatsMetric: "Chats",
            turnsMetric: "turns",
            compactionsMetric: "Compactions",
            avgCompactionsMetric: "Avg comp./chat",
            maxTurnsMetric: "Max turns",
            lengthDistributionTitle: "Conversation length distribution by turns",
            shortBucket: "Short (<10)",
            mediumBucket: "Medium (10-40)",
            longBucket: "Long (41-100)",
            extraLongBucket: "XL (>100)",
            compactionDistributionTitle: "Compaction distribution per conversation",
            zeroCompactions: "0x",
            oneCompaction: "1x",
            twoCompactions: "2x",
            threePlusCompactions: "3+x",
            compactedSuffix: "compacted",
            recommendationsTitle: "Recommendations",
            heatmapTitle: "Active days and compaction intensity, last 90 days",
            normalLegend: "Normal (≤0.3/chat)",
            highLegend: "High (0.3-1)",
            veryHighLegend: "Very high (>1)",
            noActivityLegend: "No activity",
            frequentCompressionRisk: "High comp.",
            longRunningRisk: "Long",
            wellSplitRisk: "Split well",
            healthyRisk: "Healthy",
            recommendations: englishInsightRecommendations
        )
    }

    private func englishInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        switch risk {
        case .frequentCompression:
            return [
                InsightRecommendationText(title: "New thread per bug", body: "Start investigation in a clean thread to avoid stale context."),
                InsightRecommendationText(title: "Handoff after compaction", body: "Summarize the phase after compaction and continue in a new thread."),
                InsightRecommendationText(title: "Split validation", body: "Keep implementation separate from deploy and verification work.")
            ]
        case .longRunning:
            return [
                InsightRecommendationText(title: "Split by phase", body: "Use separate threads for planning, implementation, and verification."),
                InsightRecommendationText(title: "Review at 40 turns", body: "Summarize current findings before continuing long threads."),
                InsightRecommendationText(title: "Keep repo boundary", body: "Open a new thread when switching worktrees or modules.")
            ]
        case .wellSplit:
            return [
                InsightRecommendationText(title: "Keep cadence", body: "Conversation boundaries are already healthy."),
                InsightRecommendationText(title: "Plan complex work", body: "Continue opening focused threads for new features."),
                InsightRecommendationText(title: "Switch after compaction", body: "Move deeper follow-up work into a new thread after compaction.")
            ]
        case .healthy:
            return [
                InsightRecommendationText(title: "Healthy", body: "Compaction pressure is low."),
                InsightRecommendationText(title: "New feature thread", body: "Keep separating work by task boundary."),
                InsightRecommendationText(title: "Separate release checks", body: "Keep validation and release follow-up independent.")
            ]
        }
    }

    private func chineseInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        switch risk {
        case .frequentCompression:
            return [
                InsightRecommendationText(title: "新 bug 单独窗口", body: "从排查开始新线程，避免旧上下文干扰。"),
                InsightRecommendationText(title: "压缩后交接摘要", body: "每次发生压缩后，产出阶段总结并粘贴到新窗口。"),
                InsightRecommendationText(title: "部署复测另开窗口", body: "把实现与部署/验证拆分，保持验证上下文干净。")
            ]
        case .longRunning:
            return [
                InsightRecommendationText(title: "阶段拆分", body: "计划、实现、验证分别开窗口。"),
                InsightRecommendationText(title: "到 40 turns 复盘", body: "长线程继续前先整理当前结论。"),
                InsightRecommendationText(title: "保留 repo 边界", body: "worktree 或模块切换时使用新窗口。")
            ]
        case .wellSplit:
            return [
                InsightRecommendationText(title: "保持节奏", body: "当前对话切分较好。"),
                InsightRecommendationText(title: "复杂任务仍先计划", body: "新功能开始时继续单独开窗。"),
                InsightRecommendationText(title: "压缩即换窗", body: "一旦压缩，后续深入工作放到新窗口。")
            ]
        case .healthy:
            return [
                InsightRecommendationText(title: "健康", body: "压缩压力较低。"),
                InsightRecommendationText(title: "新功能单独窗口", body: "保持按任务边界分窗。"),
                InsightRecommendationText(title: "发布验证分离", body: "验证和发布环节继续独立处理。")
            ]
        }
    }

    private func traditionalChineseInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        switch risk {
        case .frequentCompression:
            return [
                InsightRecommendationText(title: "新 bug 單獨視窗", body: "從排查開始新執行緒，避免舊上下文干擾。"),
                InsightRecommendationText(title: "壓縮後交接摘要", body: "每次發生壓縮後，整理階段摘要並移到新視窗。"),
                InsightRecommendationText(title: "部署複測另開", body: "把實作與部署/驗證拆開，保持驗證上下文乾淨。")
            ]
        case .longRunning:
            return [
                InsightRecommendationText(title: "階段拆分", body: "規劃、實作、驗證分別開視窗。"),
                InsightRecommendationText(title: "40 turns 復盤", body: "長執行緒繼續前先整理目前結論。"),
                InsightRecommendationText(title: "保留 repo 邊界", body: "切換 worktree 或模組時使用新視窗。")
            ]
        case .wellSplit:
            return [
                InsightRecommendationText(title: "保持節奏", body: "目前對話切分良好。"),
                InsightRecommendationText(title: "複雜任務先規劃", body: "新功能開始時仍單獨開窗。"),
                InsightRecommendationText(title: "壓縮即換窗", body: "一旦壓縮，後續深入工作放到新視窗。")
            ]
        case .healthy:
            return [
                InsightRecommendationText(title: "健康", body: "壓縮壓力較低。"),
                InsightRecommendationText(title: "新功能單獨視窗", body: "保持按任務邊界分窗。"),
                InsightRecommendationText(title: "發布驗證分離", body: "驗證和發布環節繼續獨立處理。")
            ]
        }
    }

    private func japaneseInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        switch risk {
        case .frequentCompression:
            return [
                InsightRecommendationText(title: "バグごとに新規", body: "調査は新しいスレッドで開始し、古い文脈を避けます。"),
                InsightRecommendationText(title: "圧縮後に引き継ぎ", body: "圧縮後は段階要約を作り、新しいスレッドで続けます。"),
                InsightRecommendationText(title: "検証を分離", body: "実装、デプロイ、検証を別スレッドに分けます。")
            ]
        case .longRunning:
            return [
                InsightRecommendationText(title: "段階で分割", body: "計画、実装、検証を別スレッドにします。"),
                InsightRecommendationText(title: "40 turns で確認", body: "長いスレッドを続ける前に結論を要約します。"),
                InsightRecommendationText(title: "Repo 境界を維持", body: "worktree やモジュールを替える時は新規スレッドにします。")
            ]
        case .wellSplit:
            return [
                InsightRecommendationText(title: "ペース維持", body: "会話の境界はすでに健全です。"),
                InsightRecommendationText(title: "複雑な作業は計画", body: "新機能は引き続き専用スレッドで始めます。"),
                InsightRecommendationText(title: "圧縮後に移動", body: "深い続きは圧縮後に新しいスレッドへ移します。")
            ]
        case .healthy:
            return [
                InsightRecommendationText(title: "健全", body: "圧縮圧力は低い状態です。"),
                InsightRecommendationText(title: "新機能は別スレッド", body: "タスク境界ごとに作業を分け続けます。"),
                InsightRecommendationText(title: "リリース確認を分離", body: "検証とリリースのフォローアップは独立させます。")
            ]
        }
    }

    private func koreanInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("새 스레드", "압축 후 요약", "검증 분리", "단계 분리", "40 turns 검토", "Repo 경계", "흐름 유지", "복잡 작업 계획", "압축 후 이동", "정상", "새 기능 분리", "릴리스 확인 분리"))
    }

    private func germanInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Neuer Thread", "Übergabe nach Komp.", "Validierung trennen", "Nach Phase teilen", "Bei 40 turns prüfen", "Repo-Grenze halten", "Takt halten", "Komplexes planen", "Nach Komp. wechseln", "Gesund", "Feature-Thread", "Releasechecks trennen"))
    }

    private func spanishInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Nuevo hilo", "Resumen tras comp.", "Separar validación", "Separar por fase", "Revisar a 40 turns", "Mantener repo", "Mantener ritmo", "Planear lo complejo", "Cambiar tras comp.", "Sano", "Hilo por función", "Separar release"))
    }

    private func frenchInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Nouveau fil", "Résumé après comp.", "Séparer validation", "Séparer par phase", "Revoir à 40 turns", "Garder le repo", "Garder le rythme", "Planifier le complexe", "Changer après comp.", "Sain", "Fil par fonction", "Séparer release"))
    }

    private func italianInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Nuovo thread", "Riepilogo dopo comp.", "Separare verifica", "Dividi per fase", "Rivedi a 40 turns", "Mantieni repo", "Mantieni ritmo", "Pianifica il complesso", "Cambia dopo comp.", "Sana", "Thread per feature", "Separa release"))
    }

    private func portugueseInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Nova thread", "Resumo após comp.", "Separar validação", "Separar por fase", "Revisar em 40 turns", "Manter repo", "Manter ritmo", "Planejar complexo", "Trocar após comp.", "Saudável", "Thread por feature", "Separar release"))
    }

    private func russianInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Новый тред", "Итог после сжатия", "Отделить проверку", "Делить по фазам", "Проверка на 40 turns", "Держать repo", "Сохранить ритм", "План сложных задач", "После сжатия новый", "Норма", "Фича в отдельный тред", "Релиз отдельно"))
    }

    private func hindiInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("नया थ्रेड", "कंप्र. के बाद सार", "वैलिडेशन अलग", "चरण अलग करें", "40 turns पर समीक्षा", "Repo सीमा रखें", "लय बनाए रखें", "जटिल काम प्लान करें", "कंप्र. के बाद बदलें", "ठीक", "नई फीचर थ्रेड", "रिलीज जांच अलग"))
    }

    private func indonesianInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Thread baru", "Ringkas setelah komp.", "Pisah validasi", "Pisah per fase", "Tinjau di 40 turns", "Jaga batas repo", "Jaga ritme", "Rencanakan kerja kompleks", "Pindah setelah komp.", "Sehat", "Thread fitur baru", "Pisah cek rilis"))
    }

    private func polishInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Nowy wątek", "Podsumuj po komp.", "Oddziel walidację", "Dziel etapami", "Przegląd przy 40 turns", "Trzymaj repo", "Utrzymaj rytm", "Planuj złożone", "Zmień po komp.", "Zdrowy", "Wątek na funkcję", "Oddziel release"))
    }

    private func ukrainianInsightRecommendations(for risk: RepoInsightRisk) -> [InsightRecommendationText] {
        localizedInsightRecommendations(for: risk, labels: ("Новий тред", "Підсумок після стис.", "Окрема перевірка", "Ділити за фазами", "Огляд на 40 turns", "Тримати repo", "Тримати ритм", "Планувати складне", "Після стис. новий", "Здоровий", "Фіча окремо", "Реліз окремо"))
    }

    private func localizedInsightRecommendations(
        for risk: RepoInsightRisk,
        labels: (String, String, String, String, String, String, String, String, String, String, String, String)
    ) -> [InsightRecommendationText] {
        let bodies = localizedInsightRecommendationBodies
        switch risk {
        case .frequentCompression:
            return [
                InsightRecommendationText(title: labels.0, body: bodies.0),
                InsightRecommendationText(title: labels.1, body: bodies.1),
                InsightRecommendationText(title: labels.2, body: bodies.2)
            ]
        case .longRunning:
            return [
                InsightRecommendationText(title: labels.3, body: bodies.3),
                InsightRecommendationText(title: labels.4, body: bodies.4),
                InsightRecommendationText(title: labels.5, body: bodies.5)
            ]
        case .wellSplit:
            return [
                InsightRecommendationText(title: labels.6, body: bodies.6),
                InsightRecommendationText(title: labels.7, body: bodies.7),
                InsightRecommendationText(title: labels.8, body: bodies.8)
            ]
        case .healthy:
            return [
                InsightRecommendationText(title: labels.9, body: bodies.9),
                InsightRecommendationText(title: labels.10, body: bodies.10),
                InsightRecommendationText(title: labels.11, body: bodies.11)
            ]
        }
    }

    private var localizedInsightRecommendationBodies: (String, String, String, String, String, String, String, String, String, String, String, String) {
        switch self {
        case .korean:
            return (
                "오래된 문맥을 피하려면 새 스레드에서 조사를 시작하세요.",
                "압축 후 단계 요약을 만들고 새 스레드에서 이어가세요.",
                "구현과 배포/검증 작업을 분리하세요.",
                "계획, 구현, 검증을 별도 스레드로 나누세요.",
                "긴 스레드를 계속하기 전에 현재 결론을 요약하세요.",
                "worktree나 모듈을 바꿀 때는 새 스레드를 여세요.",
                "대화 경계가 이미 건강합니다.",
                "새 기능은 계속 집중된 스레드에서 시작하세요.",
                "압축 후 깊은 후속 작업은 새 스레드로 옮기세요.",
                "압축 압력이 낮습니다.",
                "작업 경계별로 계속 분리하세요.",
                "검증과 릴리스 후속 작업은 독립적으로 유지하세요."
            )
        case .german:
            return (
                "Beginne die Untersuchung in einem sauberen Thread, um alten Kontext zu vermeiden.",
                "Fasse die Phase nach der Komprimierung zusammen und fahre in einem neuen Thread fort.",
                "Trenne Implementierung von Deployment und Prüfung.",
                "Nutze separate Threads für Planung, Implementierung und Prüfung.",
                "Fasse den Stand zusammen, bevor lange Threads weiterlaufen.",
                "Öffne beim Wechsel von worktree oder Modul einen neuen Thread.",
                "Die Gesprächsgrenzen sind bereits gesund.",
                "Starte neue Features weiter in fokussierten Threads.",
                "Verschiebe tiefe Folgearbeit nach Komprimierung in einen neuen Thread.",
                "Der Komprimierungsdruck ist niedrig.",
                "Trenne Arbeit weiter nach Aufgaben boundary.",
                "Halte Prüfung und Release-Follow-up unabhängig."
            )
        case .spanish:
            return (
                "Empieza la investigación en un hilo limpio para evitar contexto viejo.",
                "Resume la fase tras la compacción y continúa en un hilo nuevo.",
                "Separa implementación de despliegue y verificación.",
                "Usa hilos separados para plan, implementación y verificación.",
                "Resume los hallazgos antes de seguir hilos largos.",
                "Abre un hilo nuevo al cambiar de worktree o módulo.",
                "Los límites de conversación ya son sanos.",
                "Sigue abriendo hilos enfocados para nuevas funciones.",
                "Mueve el trabajo profundo a un hilo nuevo tras la compacción.",
                "La presión de compacción es baja.",
                "Sigue separando el trabajo por límite de tarea.",
                "Mantén validación y seguimiento de release independientes."
            )
        case .french:
            return (
                "Démarre l'analyse dans un fil propre pour éviter l'ancien contexte.",
                "Résume la phase après compaction puis poursuis dans un nouveau fil.",
                "Sépare l'implémentation du déploiement et de la validation.",
                "Utilise des fils séparés pour plan, implémentation et validation.",
                "Résume les constats avant de continuer un long fil.",
                "Ouvre un nouveau fil quand tu changes de worktree ou de module.",
                "Les limites de conversation sont déjà saines.",
                "Continue à ouvrir des fils ciblés pour les nouvelles fonctions.",
                "Déplace le suivi profond dans un nouveau fil après compaction.",
                "La pression de compaction est faible.",
                "Continue à séparer le travail par limite de tâche.",
                "Garde validation et suivi de release indépendants."
            )
        case .italian:
            return (
                "Avvia l'analisi in un thread pulito per evitare contesto vecchio.",
                "Riassumi la fase dopo la compattazione e continua in un nuovo thread.",
                "Separa implementazione da deploy e verifica.",
                "Usa thread separati per pianificazione, implementazione e verifica.",
                "Riassumi lo stato prima di continuare thread lunghi.",
                "Apri un nuovo thread quando cambi worktree o modulo.",
                "I confini della conversazione sono già sani.",
                "Continua ad aprire thread focalizzati per nuove funzioni.",
                "Sposta il lavoro profondo in un nuovo thread dopo la compattazione.",
                "La pressione di compattazione è bassa.",
                "Continua a separare il lavoro per confine di task.",
                "Mantieni indipendenti verifica e follow-up di release."
            )
        case .portugueseBrazil:
            return (
                "Comece a investigação em uma thread limpa para evitar contexto antigo.",
                "Resuma a fase após a compactação e continue em uma nova thread.",
                "Separe implementação de deploy e validação.",
                "Use threads separadas para planejamento, implementação e validação.",
                "Resuma os achados antes de continuar threads longas.",
                "Abra uma nova thread ao trocar worktree ou módulo.",
                "Os limites das conversas já estão saudáveis.",
                "Continue abrindo threads focadas para novas features.",
                "Mova o aprofundamento para uma nova thread após compactação.",
                "A pressão de compactação é baixa.",
                "Continue separando o trabalho por limite de tarefa.",
                "Mantenha validação e follow-up de release independentes."
            )
        case .russian:
            return (
                "Начинайте расследование в чистом треде, чтобы избежать старого контекста.",
                "После сжатия подведите итог этапа и продолжайте в новом треде.",
                "Разделяйте реализацию, деплой и проверку.",
                "Используйте отдельные треды для плана, реализации и проверки.",
                "Перед продолжением длинного треда кратко зафиксируйте выводы.",
                "При смене worktree или модуля открывайте новый тред.",
                "Границы диалогов уже здоровые.",
                "Для новых функций продолжайте открывать сфокусированные треды.",
                "Глубокую доработку после сжатия переносите в новый тред.",
                "Давление сжатия низкое.",
                "Продолжайте разделять работу по границам задач.",
                "Держите проверку и релизные follow-up отдельно."
            )
        case .hindi:
            return (
                "पुराने संदर्भ से बचने के लिए जांच साफ थ्रेड में शुरू करें।",
                "कंप्रेशन के बाद चरण का सार लिखें और नए थ्रेड में जारी रखें।",
                "इम्प्लीमेंटेशन को deploy और verification से अलग रखें।",
                "योजना, इम्प्लीमेंटेशन और verification के लिए अलग थ्रेड रखें।",
                "लंबे थ्रेड जारी रखने से पहले वर्तमान निष्कर्षों का सार लिखें।",
                "worktree या module बदलते समय नया थ्रेड खोलें।",
                "बातचीत की सीमाएं पहले से स्वस्थ हैं।",
                "नई features के लिए focused थ्रेड खोलते रहें।",
                "कंप्रेशन के बाद गहरे follow-up को नए थ्रेड में ले जाएं।",
                "कंप्रेशन दबाव कम है।",
                "काम को task boundary के हिसाब से अलग रखें।",
                "validation और release follow-up को स्वतंत्र रखें।"
            )
        case .indonesian:
            return (
                "Mulai investigasi di thread bersih agar konteks lama tidak mengganggu.",
                "Buat ringkasan fase setelah compaction lalu lanjutkan di thread baru.",
                "Pisahkan implementasi dari deploy dan verifikasi.",
                "Gunakan thread terpisah untuk rencana, implementasi, dan verifikasi.",
                "Ringkas temuan sebelum melanjutkan thread panjang.",
                "Buka thread baru saat berganti worktree atau modul.",
                "Batas percakapan sudah sehat.",
                "Tetap buka thread fokus untuk fitur baru.",
                "Pindahkan kerja lanjutan yang dalam ke thread baru setelah compaction.",
                "Tekanan compaction rendah.",
                "Tetap pisahkan kerja menurut batas tugas.",
                "Pisahkan validasi dan tindak lanjut rilis."
            )
        case .polish:
            return (
                "Zacznij analizę w czystym wątku, aby uniknąć starego kontekstu.",
                "Po kompakcji podsumuj etap i kontynuuj w nowym wątku.",
                "Oddziel implementację od wdrożenia i weryfikacji.",
                "Używaj osobnych wątków do planu, implementacji i weryfikacji.",
                "Podsumuj ustalenia przed kontynuowaniem długich wątków.",
                "Otwórz nowy wątek przy zmianie worktree lub modułu.",
                "Granice rozmów są już zdrowe.",
                "Dla nowych funkcji nadal otwieraj skupione wątki.",
                "Głębsze follow-up przenieś po kompakcji do nowego wątku.",
                "Presja kompakcji jest niska.",
                "Nadal dziel pracę według granic zadań.",
                "Trzymaj walidację i follow-up release osobno."
            )
        case .ukrainian:
            return (
                "Починайте розслідування в чистому треді, щоб уникнути старого контексту.",
                "Після стиснення підсумуйте етап і продовжуйте в новому треді.",
                "Відокремлюйте реалізацію від деплою та перевірки.",
                "Використовуйте окремі треди для плану, реалізації та перевірки.",
                "Підсумуйте висновки перед продовженням довгих тредів.",
                "Відкривайте новий тред при зміні worktree або модуля.",
                "Межі розмов уже здорові.",
                "Для нових функцій і далі відкривайте сфокусовані треди.",
                "Глибший follow-up після стиснення переносіть у новий тред.",
                "Тиск стиснення низький.",
                "Продовжуйте ділити роботу за межами задач.",
                "Тримайте перевірку та release follow-up окремо."
            )
        case .english, .chinese, .traditionalChinese, .japanese:
            return (
                "Start investigation in a clean thread to avoid stale context.",
                "Summarize the phase after compaction and continue in a new thread.",
                "Keep implementation separate from deploy and verification work.",
                "Use separate threads for planning, implementation, and verification.",
                "Summarize current findings before continuing long threads.",
                "Open a new thread when switching worktrees or modules.",
                "Conversation boundaries are already healthy.",
                "Continue opening focused threads for new features.",
                "Move deeper follow-up work into a new thread after compaction.",
                "Compaction pressure is low.",
                "Keep separating work by task boundary.",
                "Keep validation and release follow-up independent."
            )
        }
    }

    func insightVisibleRange(start: Int, end: Int) -> String {
        switch self {
        case .chinese: return "显示 \(start)-\(end)"
        case .traditionalChinese: return "顯示 \(start)-\(end)"
        case .japanese: return "表示 \(start)-\(end)"
        case .korean: return "\(start)-\(end) 표시"
        case .german: return "\(start)-\(end) sichtbar"
        case .spanish: return "Mostrando \(start)-\(end)"
        case .french: return "\(start)-\(end) affichés"
        case .italian: return "Mostra \(start)-\(end)"
        case .portugueseBrazil: return "Mostrando \(start)-\(end)"
        case .russian: return "Показ \(start)-\(end)"
        case .hindi: return "\(start)-\(end) दिख रहे"
        case .indonesian: return "Tampil \(start)-\(end)"
        case .polish: return "Widoczne \(start)-\(end)"
        case .ukrainian: return "Показ \(start)-\(end)"
        case .english: return "Showing \(start)-\(end)"
        }
    }
}

private struct StorageCategoryCopy {
    let name: String
    let purpose: String
    let impact: String
    let advice: String
}

private struct StorageCopy {
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
    let rescanBannerFormat: String
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

private func chineseStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
    switch id {
    case .codexSessions:
        return StorageCategoryCopy(
            name: "会话日志",
            purpose: "包含 Codex 正在使用的对话日志源数据（sessions 与 archived_sessions），用于计算 token、会话、模型和项目级别的统计。",
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

private func traditionalChineseStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
    switch id {
    case .codexSessions:
        return StorageCategoryCopy(
            name: "會話日誌",
            purpose: "包含 Codex 正在使用的對話日誌源資料（sessions 與 archived_sessions），用於計算 token、會話、模型和專案層級的統計。",
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

private func japaneseStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
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

private func englishStorageCategoryCopy(_ id: StorageCategoryID) -> StorageCategoryCopy {
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

private extension AppLanguage {
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
                colTurns: "回合",
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
                rescanBannerFormat: "正在后台重新扫描… 当前显示 %@ 的结果",
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
                colTurns: "回合",
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
                rescanBannerFormat: "正在背景重新掃描… 目前顯示 %@ 的結果",
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
                rescanBannerFormat: "バックグラウンドで再スキャン中… %@ 時点の結果を表示",
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
                rescanBannerFormat: "Rescanning in background… showing results from %@",
                scannedAtFormat: "Scanned at %@",
                totalLabel: "Total",
                noProjectsHint: "No attributable project data yet.",
                emptyCategoriesHint: "No local data directories found.",
                categories: englishStorageCategoryCopy
            )
        }
    }
}

final class UsageDetailsWindowController: NSWindowController, NSWindowDelegate {
    let detailsView = UsageDetailsView(frame: NSRect(x: 0, y: 0, width: 900, height: 660))
    private let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 660))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = t(.detailsWindowTitle)
        window.contentMinSize = NSSize(width: 860, height: 640)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        detailsView.canDrawConcurrently = false
        scrollView.documentView = detailsView
        window.contentView = scrollView
        super.init(window: window)
        window.delegate = self
        detailsView.onPreferredHeightChanged = { [weak self] in
            self?.updateDocumentLayout()
        }
        updateDocumentLayout()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showLoading() {
        detailsView.isLoading = true
        detailsView.loadingProgress = .starting
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        updateDocumentLayout()
    }

    func showCached(snapshot: DetailsSnapshot) {
        detailsView.snapshot = snapshot
        detailsView.isLoading = false
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        updateDocumentLayout()
    }

    func showContent() {
        detailsView.isLoading = false
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        updateDocumentLayout()
    }

    func updateLoadingProgress(_ progress: DetailsLoadingProgress) {
        guard detailsView.isLoading else { return }
        detailsView.loadingProgress = progress
    }

    func update(snapshot: DetailsSnapshot) {
        detailsView.snapshot = snapshot
        detailsView.isLoading = false
        updateDocumentLayout()
    }

    func updateLiveLimits(_ limits: [LiveRateLimit], costReferenceReport: TokenReport?, serviceStatus: CodexServiceStatusSnapshot?) {
        guard var snapshot = detailsView.snapshot else { return }
        snapshot.liveLimits = limits
        snapshot.serviceStatus = serviceStatus ?? snapshot.serviceStatus
        if let costReferenceReport {
            snapshot.costReferenceReport = costReferenceReport
        }
        detailsView.snapshot = snapshot
        updateDocumentLayout()
    }

    func updateResetCredits(_ resetCredits: RateLimitResetCreditsSnapshot?) {
        guard var snapshot = detailsView.snapshot else { return }
        snapshot.resetCredits = resetCredits
        detailsView.snapshot = snapshot
        updateDocumentLayout()
    }

    func updateServiceStatus(_ serviceStatus: CodexServiceStatusSnapshot?) {
        guard var snapshot = detailsView.snapshot else { return }
        snapshot.serviceStatus = serviceStatus
        detailsView.snapshot = snapshot
        updateDocumentLayout()
    }

    func applyLanguage() {
        window?.title = t(.detailsWindowTitle)
        updateDocumentLayout()
        detailsView.needsDisplay = true
    }

    func windowDidResize(_ notification: Notification) {
        updateDocumentLayout()
    }

    private func updateDocumentLayout() {
        let visibleWidth = max(860, scrollView.contentSize.width)
        let visibleHeight = max(640, scrollView.contentSize.height)
        let targetHeight = max(visibleHeight, detailsView.preferredDocumentHeight(for: visibleWidth))
        detailsView.frame = NSRect(x: 0, y: 0, width: visibleWidth, height: targetHeight)
        detailsView.needsLayout = true
        detailsView.needsDisplay = true
    }
}

enum DetailsSection: CaseIterable {
    case overview
    case calendar
    case insights
    case costs
    case models
    case storage
    case settings
    case diagnostics
    case about

    static var visibleSections: [DetailsSection] {
        allCases.filter(\.isVisibleInDetailsNavigation)
    }

    var isVisibleInDetailsNavigation: Bool {
        // Quota cycles page is hidden until its design is finalized.
        self != .costs
    }

    var visibleFallback: DetailsSection {
        isVisibleInDetailsNavigation ? self : .overview
    }

    var title: String {
        switch self {
        case .overview: return t(.overview)
        case .insights: return AppLanguage.current.insightCopy.sidebarTitle
        case .models: return t(.models)
        case .calendar: return t(.calendar)
        case .costs: return t(.quotaCycles)
        case .storage: return AppLanguage.current.storageCopy.sidebarTitle
        case .settings: return t(.settings)
        case .diagnostics: return t(.diagnostics)
        case .about: return t(.about)
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return t(.overviewSubtitle)
        case .insights: return AppLanguage.current.insightCopy.sidebarSubtitle
        case .models: return t(.modelsSubtitle)
        case .calendar: return t(.calendarSubtitle)
        case .costs: return t(.quotaCyclesSubtitle)
        case .storage: return AppLanguage.current.storageCopy.headerSubtitle
        case .settings: return t(.settingsSubtitle)
        case .diagnostics: return t(.diagnosticsSubtitle)
        case .about: return t(.aboutSubtitle)
        }
    }

    var headerTitle: String {
        switch self {
        case .insights:
            return AppLanguage.current.insightCopy.headerTitle
        case .storage:
            return AppLanguage.current.storageCopy.headerTitle
        case .overview:
            return t(.usageDetails)
        default:
            return title
        }
    }

    var canRenderWithoutSnapshot: Bool {
        switch self {
        case .settings, .about, .storage:
            return true
        default:
            return false
        }
    }
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private func centeredRect(for bounds: NSRect) -> NSRect {
        let horizontalPadding: CGFloat = 12
        let measuredHeight = ceil(cellSize.height)
        let centeredY = bounds.minY + floor((bounds.height - measuredHeight) / 2)
        return NSRect(
            x: bounds.minX + horizontalPadding,
            y: max(bounds.minY, centeredY),
            width: max(0, bounds.width - horizontalPadding * 2),
            height: min(bounds.height, measuredHeight)
        )
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(for: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centeredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

final class UsageDetailsView: NSView, NSTextFieldDelegate, NSSearchFieldDelegate {
    private struct CostRingCache {
        let key: String
        let image: NSImage
    }

    private struct CostPageData {
        let key: String
        let estimate: PlanCostEstimate?
        let apiEstimate: APICostEstimate
        let weeklyRows: [CostPeriodRow]
        let monthlyRows: [MonthlySpendRow]
    }

    private struct ContributionWeekSummary {
        let key: String
        let startDay: String
        let endDay: String
        let usage: Usage
        let total: Int64
        let activeDays: Int
        let turns: Int
        let days: [DayUsage]
        let hitRect: NSRect
        let cellRects: [NSRect]
    }

    private struct ContributionDaySummary {
        let day: DayUsage
        let hitRect: NSRect
    }

    private enum CostOverviewInfo: Hashable {
        case usageRate
        case totalSpend
        case apiEquivalent
        case externalAPI
        case totalWaste

        var title: String {
            switch self {
            case .usageRate: return t(.usageRate)
            case .totalSpend: return t(.totalSpendValue)
            case .apiEquivalent: return t(.apiEquivalent)
            case .externalAPI: return t(.externalAPICost)
            case .totalWaste: return t(.totalWasteValue)
            }
        }

        var hint: String {
            switch self {
            case .usageRate: return t(.usageRateHint)
            case .totalSpend: return t(.totalSpendValueHint)
            case .apiEquivalent: return t(.apiEquivalentCostHint)
            case .externalAPI: return t(.externalAPICostCalculationHint)
            case .totalWaste: return t(.totalWasteValueHint)
            }
        }
    }

    private enum InsightSortColumn: CaseIterable {
        case project
        case conversations
        case compressions
        case average
        case status

        var title: String {
            let copy = AppLanguage.current.insightCopy
            switch self {
            case .project: return copy.project
            case .conversations: return copy.conversations
            case .compressions: return copy.compressions
            case .average: return copy.average
            case .status: return copy.status
            }
        }

        var defaultAscending: Bool {
            switch self {
            case .project, .status:
                return true
            case .conversations, .compressions, .average:
                return false
            }
        }
    }

    private enum InsightDetailMode: CaseIterable {
        case usageHabits
        case usageTime
    }

    private enum SettingsSubsection: CaseIterable {
        case appearance
        case data
        case quota
        case system

        var title: String {
            switch AppLanguage.current {
            case .chinese, .traditionalChinese:
                switch self {
                case .appearance: return "外观显示"
                case .data: return "数据来源"
                case .quota: return "额度提醒"
                case .system: return "系统"
                }
            case .japanese:
                switch self {
                case .appearance: return "表示"
                case .data: return "データソース"
                case .quota: return "制限と通知"
                case .system: return "システム"
                }
            default:
                switch self {
                case .appearance: return "Appearance"
                case .data: return "Data Sources"
                case .quota: return "Quota & Alerts"
                case .system: return "System"
                }
            }
        }

        var subtitle: String {
            switch AppLanguage.current {
            case .chinese, .traditionalChinese:
                switch self {
                case .appearance: return "语言、单位和状态栏"
                case .data: return "日志目录和 API 总量"
                case .quota: return "额度显示和提醒"
                case .system: return "启动行为"
                }
            case .japanese:
                switch self {
                case .appearance: return "言語、単位、メニューバー"
                case .data: return "ログルートと API 合計"
                case .quota: return "制限表示と通知"
                case .system: return "起動動作"
                }
            default:
                switch self {
                case .appearance: return "Language, units, and menu bar"
                case .data: return "Log roots and API totals"
                case .quota: return "Quota visuals and warnings"
                case .system: return "Startup behavior"
                }
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "slider.horizontal.3"
            case .data: return "externaldrive"
            case .quota: return "bell.badge"
            case .system: return "power"
            }
        }
    }

    private enum InsightStatusFilter: CaseIterable, Hashable {
        case all
        case frequentCompression
        case longRunning
        case good

        func matches(_ risk: RepoInsightRisk) -> Bool {
            switch self {
            case .all: return true
            case .frequentCompression: return risk == .frequentCompression
            case .longRunning: return risk == .longRunning
            case .good: return risk == .wellSplit || risk == .healthy
            }
        }
    }

    var snapshot: DetailsSnapshot? {
        didSet {
            if let snapshot {
                let report = calendarReport(for: snapshot)
                selectedDay = preferredSelectedDay(in: report, fallback: selectedDay)
                normalizeSelectedInsight(for: insightReport(for: snapshot))
            }
            updateResetCreditCountdownTimer()
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var isLoading = false { didSet { updateResetCreditCountdownTimer(); onPreferredHeightChanged?(); needsDisplay = true; needsLayout = true } }
    var loadingProgress = DetailsLoadingProgress.starting { didSet { needsDisplay = true } }
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onNumberUnitStyleChanged: ((NumberUnitStyle) -> Void)?
    var onStatusBarMetricChanged: ((StatusBarMetricSlot, StatusBarMetric?) -> Void)?
    var onQuotaDisplayStyleChanged: ((QuotaDisplayStyle) -> Void)?
    var onCodexHomeRingMetricChanged: ((HomeQuotaRingMetric) -> Void)?
    var onClaudeHomeRingMetricChanged: ((HomeQuotaRingMetric) -> Void)?
    var onPlanCostChanged: ((Double, QuotaViewOption) -> Void)?
    var onPaymentStartDayChanged: ((String, QuotaViewOption) -> Void)?
    var onPaymentCurrencyChanged: ((CurrencyCode, QuotaViewOption) -> Void)?
    var onDisplayCurrencyChanged: ((CurrencyCode, QuotaViewOption) -> Void)?
    var onChooseLogFolder: (() -> Void)?
    var onResetLogFolder: (() -> Void)?
    var onOpenLogFolder: (() -> Void)?
    var onChooseCodexAPISource: (() -> Void)?
    var onResetCodexAPISources: (() -> Void)?
    var onOpenCodexAPISource: (() -> Void)?
    var onShowHistoricalEmptyWeeksChanged: ((Bool) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onShowCodexStatusChanged: ((Bool) -> Void)?
    var onQuotaWarningsChanged: ((Bool) -> Void)?
    var onProfileAPITotalsChanged: ((Bool) -> Void)?
    var onClaudeActiveQuotaRefreshChanged: ((Bool) -> Void)?
    var onPreferredHeightChanged: (() -> Void)?
    private var selectedSection: DetailsSection = .overview {
        didSet {
            if selectedSection.canRenderWithoutSnapshot {
                isLoading = false
            }
            if selectedSection != .costs {
                hoveredCostHistoryIndex = nil
                hoveredCostOverviewInfo = nil
                hoveredQuotaCycleIndex = nil
            }
            if selectedSection != .calendar {
                isHoveringDayValueInfo = false
                isHoveringProfileAPIInfo = false
            }
            if selectedSection != .calendar {
                hoveredContributionWeekKey = nil
            }
            if selectedSection != .overview {
                hoveredContributionDay = nil
            }
            if selectedSection != .models {
                hoveredModelUsageRowIndex = nil
                modelUsageHoverRows.removeAll(keepingCapacity: true)
            }
            if selectedSection != .storage {
                hoveredStorageCellKey = nil
                hoveredStorageSourceID = nil
            }
            if selectedSection == .storage {
                requestStorageScanIfNeeded()
            }
            updateResetCreditCountdownTimer()
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    private var resetCreditCountdownTimer: Timer?
    private var hoveredResetCreditIndex: Int?
    private var isHoveringResetCreditHeader = false
    private var resetCreditHeaderHitArea: NSRect?
    private var resetCreditFetchedAtText: String?
    private var resetCreditHitAreas: [(rect: NSRect, index: Int)] = []
    private var resetCreditTooltipRows: [RateLimitResetCredit] = []
    private var sidebarItemRects: [DetailsSection: NSRect] = [:]
    private var insightRowRects: [String: NSRect] = [:]
    private var insightWindowRects: [Int: NSRect] = [:]
    private var insightDetailModeRects: [InsightDetailMode: NSRect] = [:]
    private var insightSortRects: [InsightSortColumn: NSRect] = [:]
    private var sourceOptionRects: [QuotaViewOption: NSRect] = [:]
    private var insightListViewportRect: NSRect?
    private let insightWindowOptions = [7, 30, 90]
    private var selectedInsightWindowDays = 90
    private var selectedDetailsSource: QuotaViewOption = .all {
        didSet {
            guard selectedDetailsSource != oldValue else { return }
            costPageDataCache = nil
            costRingCache = nil
            costYearOptionsCacheKey = nil
            if let snapshot {
                let report = calendarReport(for: snapshot)
                selectedDay = preferredSelectedDay(in: report, fallback: selectedDay)
                normalizeSelectedInsight(for: insightReport(for: snapshot))
            }
            onPreferredHeightChanged?()
            updateResetCreditCountdownTimer()
            needsDisplay = true
            needsLayout = true
        }
    }
    private var selectedInsightKey: String?
    private var selectedInsightSort: InsightSortColumn = .average
    private var selectedInsightStatusFilter: InsightStatusFilter = .all
    private var insightStatusFilterRects: [InsightStatusFilter: NSRect] = [:]
    private var insightListContentHeight: CGFloat = 0
    private var isInsightSortAscending = false
    private var selectedInsightDetailMode: InsightDetailMode = .usageHabits
    private var selectedSettingsSubsection: SettingsSubsection = .appearance {
        didSet {
            guard selectedSettingsSubsection != oldValue else { return }
            window?.makeFirstResponder(nil)
            layoutSettingsControls()
            needsDisplay = true
            needsLayout = true
        }
    }
    private var insightHourRects: [Int: NSRect] = [:]
    private var insightHourBarRects: [Int: NSRect] = [:]
    private var insightPeriodRects: [String: NSRect] = [:]
    private var hoveredInsightHour: Int?
    private var hoveredInsightPeriod: String?
    private var insightListScrollOffset: CGFloat = 0
    private var numberUnitOptionRects: [NumberUnitStyle: NSRect] = [:]
    private var quotaDisplayStyleRects: [QuotaDisplayStyle: NSRect] = [:]
    private var codexHomeRingMetricRects: [HomeQuotaRingMetric: NSRect] = [:]
    private var claudeHomeRingMetricRects: [HomeQuotaRingMetric: NSRect] = [:]
    private var settingsSubsectionRects: [SettingsSubsection: NSRect] = [:]
    private var chooseLogFolderRect: NSRect?
    private var resetLogFolderRect: NSRect?
    private var openLogFolderRect: NSRect?
    private var chooseCodexAPISourceRect: NSRect?
    private var resetCodexAPISourceRect: NSRect?
    private var openCodexAPISourceRect: NSRect?
    private var contributionDayRects: [String: NSRect] = [:]
    private var contributionDaySummaries: [String: ContributionDaySummary] = [:]
    private var hoveredContributionDay: String?
    private var contributionWeekSummaries: [String: ContributionWeekSummary] = [:]
    private var contributionWeekDotRects: [String: NSRect] = [:]
    private var hoveredContributionWeekKey: String?
    private var selectedWeekStartDay: String?
    private var costHistoryBarRects: [Int: NSRect] = [:]
    private var costHistoryRows: [CostPeriodRow] = []
    private var costOverviewInfoRects: [CostOverviewInfo: NSRect] = [:]
    private var dayValueInfoRect: NSRect?
    private var profileAPIInfoRect: NSRect?
    private var showHistoricalEmptyWeeksToggleRect: NSRect?
    private var selectedDay: String?
    private var hoveredCostHistoryIndex: Int?
    private var quotaCycleHitAreas: [(rect: NSRect, index: Int)] = []
    private var quotaCycleTooltipRows: [QuotaCycleRowModel] = []
    private var hoveredQuotaCycleIndex: Int?
    private var modelUsageHoverRows: [ModelUsageHoverRow] = []
    private var hoveredModelUsageRowIndex: Int?
    private var hoveredCostOverviewInfo: CostOverviewInfo?
    private var isHoveringDayValueInfo = false
    private var isHoveringProfileAPIInfo = false
    private var selectedCostYear = Calendar.current.component(.year, from: Date())
    private var costRingCache: CostRingCache?
    private var costPageDataCache: CostPageData?
    private var costYearOptionsCacheKey: String?
    private var costYearOptionsCache: [Int] = []
    private var costAmountEditingSource: QuotaViewOption?
    private var paymentStartDayEditingSource: QuotaViewOption?
    private let costAmountField: NSTextField = {
        let field = NSTextField()
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        return field
    }()
    private let paymentStartDayField: NSTextField = {
        let field = NSTextField()
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        return field
    }()
    private let paymentCurrencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let displayCurrencyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let costYearPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusPrimaryMetricPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusSecondaryMetricPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let storageFilterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let storageSortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let storageSearchField = NSSearchField()
    private let showHistoricalEmptyWeeksSwitch = NSSwitch(frame: .zero)
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let showCodexStatusSwitch = NSSwitch(frame: .zero)
    private let quotaWarningsSwitch = NSSwitch(frame: .zero)
    private let profileAPITotalsSwitch = NSSwitch(frame: .zero)
    private let claudeActiveQuotaRefreshSwitch = NSSwitch(frame: .zero)
    private var isUpdatingCostControls = false
    private var isUpdatingStatusMetricPopups = false
    private var detailsTrackingArea: NSTrackingArea?

    var storageSnapshot: StorageSnapshot? {
        didSet {
            if selectedStorageCategoryID == nil, let storageSnapshot {
                selectedStorageCategoryID = storageSnapshot.categories
                    .filter { $0.bytes > 0 }
                    .max { $0.bytes < $1.bytes }?
                    .id
            }
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var isStorageScanning = false {
        didSet {
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
        }
    }
    var onStorageScanRequested: (() -> Void)?

    private enum StorageSortOption: CaseIterable {
        case size
        case recent
        case name
    }

    private struct StorageGrowthCell {
        let key: String
        let rect: NSRect
        let title: String
        let rows: [(StorageCategoryID, Int64)]
        let total: Int64
    }

    private struct ModelUsageHoverRow {
        let rect: NSRect
        let title: String
        let subtitle: String?
        let usage: Usage
        let shareText: String?
        let sessions: Int?
        let events: Int?
        let apiCostText: String?
        let apiCostColor: NSColor
    }

    private var storageSortOption: StorageSortOption = .size
    private var storageFilterCategory: StorageCategoryID?
    private var storageSearchText = ""
    private var selectedStorageCategoryID: StorageCategoryID?
    private var hoveredStorageCellKey: String?
    private var hoveredStorageSourceID: StorageCategoryID?
    private var storageGrowthCells: [StorageGrowthCell] = []
    private var storageSourceRowRects: [StorageCategoryID: NSRect] = [:]
    private var storageSourceMenuRects: [StorageCategoryID: NSRect] = [:]
    private var storageOpenFinderRect: NSRect?
    private var storageExportRect: NSRect?
    private var storageRefreshRect: NSRect?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateResetCreditCountdownTimer()
    }

    deinit {
        resetCreditCountdownTimer?.invalidate()
    }

    private var shouldAnimateResetCreditCountdown: Bool {
        guard window != nil,
              !isLoading,
              selectedSection == .overview,
              selectedDetailsSource != .claude,
              let resetCredits = snapshot?.resetCredits,
              resetCredits.availableCount > 0,
              resetCredits.nextExpiringAvailableCredit?.expiresAt != nil else {
            return false
        }
        return true
    }

    private func updateResetCreditCountdownTimer() {
        if shouldAnimateResetCreditCountdown {
            guard resetCreditCountdownTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard self.shouldAnimateResetCreditCountdown else {
                    self.resetCreditCountdownTimer?.invalidate()
                    self.resetCreditCountdownTimer = nil
                    return
                }
                self.needsDisplay = true
            }
            resetCreditCountdownTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            resetCreditCountdownTimer?.invalidate()
            resetCreditCountdownTimer = nil
        }
    }

    private func requestStorageScanIfNeeded() {
        guard storageSnapshot == nil, !isStorageScanning else { return }
        isStorageScanning = true
        onStorageScanRequested?()
    }

    func showUsagePage() {
        selectedSection = .overview
    }

    func showInsightsPage(windowDays: Int = 90, insightMode: String? = nil) {
        if insightWindowOptions.contains(windowDays) {
            selectedInsightWindowDays = windowDays
        }
        if let insightMode {
            switch insightMode.lowercased() {
            case "time", "usage-time", "usage_time":
                selectedInsightDetailMode = .usageTime
            case "habits", "usage-habits", "usage_habits":
                selectedInsightDetailMode = .usageHabits
            default:
                break
            }
        }
        selectedSection = .insights
    }

    func showSection(_ section: DetailsSection, insightWindowDays: Int = 90, source: QuotaViewOption? = nil, insightMode: String? = nil) {
        if let source {
            selectedDetailsSource = source
        }
        let visibleSection = section.visibleFallback
        if visibleSection == .insights {
            showInsightsPage(windowDays: insightWindowDays, insightMode: insightMode)
        } else {
            selectedSection = visibleSection
        }
    }

    func showSettingsPage() {
        selectedSection = .settings
    }

    private let detailsSidebarWidth: CGFloat = 200
    private let settingsContentTopOffset: CGFloat = 78
    private let settingsPanelHeight: CGFloat = 548
    private let settingsBottomPadding: CGFloat = 56
    private let settingsSubnavWidth: CGFloat = 172

    private var showsDetailsSourceSelector: Bool {
        switch selectedSection {
        case .overview, .models, .calendar, .costs, .diagnostics, .storage:
            return true
        case .insights, .settings, .about:
            return false
        }
    }

    private func settingsPanelRect(in content: NSRect) -> NSRect {
        NSRect(
            x: content.minX,
            y: content.minY + settingsContentTopOffset,
            width: content.width,
            height: settingsPanelHeight
        )
    }

    private func settingsPageRect(in panel: NSRect) -> NSRect {
        NSRect(
            x: panel.minX + settingsSubnavWidth + 34,
            y: panel.minY + 4,
            width: max(0, panel.width - settingsSubnavWidth - 34),
            height: panel.height - 8
        )
    }

    private func sectionContent(for section: DetailsSection, in bounds: NSRect, sidebarWidth: CGFloat) -> NSRect {
        let full = NSRect(x: sidebarWidth + 28, y: 28, width: bounds.width - sidebarWidth - 56, height: bounds.height - 56)
        switch section {
        case .settings:
            return NSRect(x: full.minX, y: full.minY, width: min(full.width, 920), height: full.height)
        default:
            return full
        }
    }

    private var visibleCostControlFrames: [NSRect] {
        []
    }

    private var appBackgroundTop: NSColor {
        NSColor(calibratedRed: 0.055, green: 0.066, blue: 0.086, alpha: 1.0)
    }

    private var appBackgroundBottom: NSColor {
        NSColor(calibratedRed: 0.075, green: 0.090, blue: 0.118, alpha: 1.0)
    }

    private var sidebarBackgroundColor: NSColor {
        NSColor(calibratedRed: 0.046, green: 0.055, blue: 0.073, alpha: 1.0)
    }

    private var panelSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.126, green: 0.148, blue: 0.186, alpha: 0.98)
    }

    private var panelElevatedColor: NSColor {
        NSColor(calibratedRed: 0.154, green: 0.178, blue: 0.222, alpha: 0.98)
    }

    private var inputSurfaceColor: NSColor {
        NSColor(calibratedRed: 0.088, green: 0.105, blue: 0.138, alpha: 1.0)
    }

    private var borderColor: NSColor {
        NSColor.white.withAlphaComponent(0.075)
    }

    private var accentBlue: NSColor {
        NSColor(calibratedRed: 0.365, green: 0.548, blue: 1.0, alpha: 1.0)
    }

    private var accentTeal: NSColor {
        NSColor(calibratedRed: 0.279, green: 0.839, blue: 0.702, alpha: 1.0)
    }

    private var accentAmber: NSColor {
        NSColor(calibratedRed: 0.965, green: 0.724, blue: 0.357, alpha: 1.0)
    }

    private var accentRose: NSColor {
        NSColor(calibratedRed: 0.941, green: 0.478, blue: 0.553, alpha: 1.0)
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupControls()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupControls()
    }

    override func layout() {
        super.layout()
        layoutCostControls()
        layoutSettingsControls()
        layoutStorageControls()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let detailsTrackingArea {
            removeTrackingArea(detailsTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        detailsTrackingArea = trackingArea
    }

    private func setupControls() {
        costAmountField.isBordered = false
        costAmountField.drawsBackground = false
        costAmountField.focusRingType = .default
        costAmountField.isEditable = true
        costAmountField.isSelectable = true
        costAmountField.isEnabled = true
        costAmountField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        costAmountField.alignment = .center
        costAmountField.textColor = .white
        costAmountField.usesSingleLineMode = true
        costAmountField.lineBreakMode = .byTruncatingTail
        costAmountField.delegate = self
        costAmountField.isHidden = true
        addSubview(costAmountField)

        paymentStartDayField.isBordered = false
        paymentStartDayField.drawsBackground = false
        paymentStartDayField.focusRingType = .default
        paymentStartDayField.isEditable = true
        paymentStartDayField.isSelectable = true
        paymentStartDayField.isEnabled = true
        paymentStartDayField.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        paymentStartDayField.alignment = .center
        paymentStartDayField.textColor = .white
        paymentStartDayField.placeholderString = "YYYY-MM-DD"
        paymentStartDayField.usesSingleLineMode = true
        paymentStartDayField.lineBreakMode = .byTruncatingTail
        paymentStartDayField.delegate = self
        paymentStartDayField.isHidden = true
        addSubview(paymentStartDayField)

        showHistoricalEmptyWeeksSwitch.controlSize = .small
        showHistoricalEmptyWeeksSwitch.isHidden = true
        showHistoricalEmptyWeeksSwitch.target = self
        showHistoricalEmptyWeeksSwitch.action = #selector(showHistoricalEmptyWeeksChanged)
        addSubview(showHistoricalEmptyWeeksSwitch)

        launchAtLoginSwitch.controlSize = .small
        launchAtLoginSwitch.isHidden = true
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)
        addSubview(launchAtLoginSwitch)

        showCodexStatusSwitch.controlSize = .small
        showCodexStatusSwitch.isHidden = true
        showCodexStatusSwitch.target = self
        showCodexStatusSwitch.action = #selector(showCodexStatusChanged)
        addSubview(showCodexStatusSwitch)

        quotaWarningsSwitch.controlSize = .small
        quotaWarningsSwitch.isHidden = true
        quotaWarningsSwitch.target = self
        quotaWarningsSwitch.action = #selector(quotaWarningsChanged)
        addSubview(quotaWarningsSwitch)

        profileAPITotalsSwitch.controlSize = .small
        profileAPITotalsSwitch.isHidden = true
        profileAPITotalsSwitch.target = self
        profileAPITotalsSwitch.action = #selector(profileAPITotalsChanged)
        addSubview(profileAPITotalsSwitch)

        claudeActiveQuotaRefreshSwitch.controlSize = .small
        claudeActiveQuotaRefreshSwitch.isHidden = true
        claudeActiveQuotaRefreshSwitch.target = self
        claudeActiveQuotaRefreshSwitch.action = #selector(claudeActiveQuotaRefreshChanged)
        addSubview(claudeActiveQuotaRefreshSwitch)

        for popup in [paymentCurrencyPopup, displayCurrencyPopup, costYearPopup, languagePopup, statusPrimaryMetricPopup, statusSecondaryMetricPopup] {
            popup.controlSize = .regular
            popup.font = .systemFont(ofSize: 12, weight: .semibold)
            popup.isBordered = false
            popup.isHidden = true
            popup.wantsLayer = true
            popup.layer?.cornerRadius = 8
            popup.layer?.backgroundColor = inputSurfaceColor.cgColor
            popup.appearance = NSAppearance(named: .darkAqua)
            addSubview(popup)
        }
        paymentCurrencyPopup.removeAllItems()
        paymentCurrencyPopup.addItems(withTitles: CurrencyCode.allCases.map(\.displayTitle))
        displayCurrencyPopup.removeAllItems()
        displayCurrencyPopup.addItems(withTitles: CurrencyCode.allCases.map(\.displayTitle))
        costYearPopup.removeAllItems()
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        updateStatusMetricPopupsFromSettings()
        costAmountField.setAccessibilityLabel(t(.paymentMonthly))
        paymentStartDayField.setAccessibilityLabel(t(.paymentStartDate))
        paymentCurrencyPopup.setAccessibilityLabel(t(.paymentCurrency))
        displayCurrencyPopup.setAccessibilityLabel(t(.displayCurrency))
        costYearPopup.setAccessibilityLabel(t(.costHistory))
        languagePopup.setAccessibilityLabel(t(.interfaceLanguage))
        statusPrimaryMetricPopup.setAccessibilityLabel(t(.statusBarMetricOne))
        statusSecondaryMetricPopup.setAccessibilityLabel(t(.statusBarMetricTwo))
        showHistoricalEmptyWeeksSwitch.setAccessibilityLabel(t(.showPastEmptyWeeks))
        launchAtLoginSwitch.setAccessibilityLabel(t(.launchAtLogin))
        quotaWarningsSwitch.setAccessibilityLabel(t(.quotaWarnings))
        profileAPITotalsSwitch.setAccessibilityLabel(t(.profileAPITotals))
        claudeActiveQuotaRefreshSwitch.setAccessibilityLabel(t(.claudeActiveRefresh))
        paymentCurrencyPopup.target = self
        paymentCurrencyPopup.action = #selector(paymentCurrencyPopupChanged)
        displayCurrencyPopup.target = self
        displayCurrencyPopup.action = #selector(displayCurrencyPopupChanged)
        costYearPopup.target = self
        costYearPopup.action = #selector(costYearPopupChanged)
        languagePopup.target = self
        languagePopup.action = #selector(languagePopupChanged)
        statusPrimaryMetricPopup.target = self
        statusPrimaryMetricPopup.action = #selector(statusPrimaryMetricPopupChanged)
        statusSecondaryMetricPopup.target = self
        statusSecondaryMetricPopup.action = #selector(statusSecondaryMetricPopupChanged)

        for popup in [storageFilterPopup, storageSortPopup] {
            popup.controlSize = .small
            popup.font = .systemFont(ofSize: 11, weight: .semibold)
            popup.isBordered = false
            popup.isHidden = true
            popup.wantsLayer = true
            popup.layer?.cornerRadius = 7
            popup.layer?.backgroundColor = inputSurfaceColor.cgColor
            popup.appearance = NSAppearance(named: .darkAqua)
            addSubview(popup)
        }
        storageFilterPopup.target = self
        storageFilterPopup.action = #selector(storageFilterPopupChanged)
        storageSortPopup.target = self
        storageSortPopup.action = #selector(storageSortPopupChanged)
        storageSearchField.controlSize = .small
        storageSearchField.font = .systemFont(ofSize: 11)
        storageSearchField.isHidden = true
        storageSearchField.appearance = NSAppearance(named: .darkAqua)
        storageSearchField.delegate = self
        storageSearchField.sendsWholeSearchString = false
        storageSearchField.sendsSearchStringImmediately = true
        addSubview(storageSearchField)
    }

    private func layoutCostControls() {
        // The quota-cycle page replaced the legacy money page; its plan-cost
        // input controls stay hidden everywhere.
        costAmountField.isHidden = true
        paymentStartDayField.isHidden = true
        paymentCurrencyPopup.isHidden = true
        displayCurrencyPopup.isHidden = true
        costYearPopup.isHidden = true
        showHistoricalEmptyWeeksSwitch.isHidden = true
        showHistoricalEmptyWeeksToggleRect = nil
    }

    private func layoutSettingsControls() {
        let visible = selectedSection == .settings
        languagePopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        displayCurrencyPopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        statusPrimaryMetricPopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        statusSecondaryMetricPopup.isHidden = !(visible && selectedSettingsSubsection == .appearance)
        launchAtLoginSwitch.isHidden = !(visible && selectedSettingsSubsection == .system)
        showCodexStatusSwitch.isHidden = !(visible && selectedSettingsSubsection == .quota)
        quotaWarningsSwitch.isHidden = !(visible && selectedSettingsSubsection == .quota)
        profileAPITotalsSwitch.isHidden = !(visible && selectedSettingsSubsection == .data)
        claudeActiveQuotaRefreshSwitch.isHidden = !(visible && selectedSettingsSubsection == .data)
        guard visible else { return }

        let content = sectionContent(for: .settings, in: bounds, sidebarWidth: detailsSidebarWidth)
        let rect = settingsPanelRect(in: content)
        let pageRect = settingsPageRect(in: rect)
        let controlWidth = min(300, max(224, pageRect.width * 0.40))
        let controlX = pageRect.maxX - controlWidth
        let switchX = pageRect.maxX - 50
        languagePopup.frame = NSRect(x: controlX, y: pageRect.minY + 70, width: controlWidth, height: 36)
        displayCurrencyPopup.frame = NSRect(x: controlX, y: pageRect.minY + 146, width: controlWidth, height: 36)
        statusPrimaryMetricPopup.frame = NSRect(x: controlX, y: pageRect.minY + 300, width: controlWidth, height: 36)
        statusSecondaryMetricPopup.frame = NSRect(x: controlX, y: pageRect.minY + 370, width: controlWidth, height: 36)
        profileAPITotalsSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 320, width: 48, height: 24)
        claudeActiveQuotaRefreshSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 390, width: 48, height: 24)
        showCodexStatusSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 306, width: 48, height: 24)
        quotaWarningsSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 390, width: 48, height: 24)
        launchAtLoginSwitch.frame = NSRect(x: switchX, y: pageRect.minY + 76, width: 48, height: 24)
        updateLanguagePopupFromSettings()
        updateDisplayCurrencyPopupFromSettings()
        updateStatusMetricPopupsFromSettings()
        updateSettingsControlsFromSystem()
    }

    private func updateLanguagePopupFromSettings() {
        if languagePopup.itemArray.map(\.title) != AppLanguage.allCases.map(\.displayName) {
            languagePopup.removeAllItems()
            languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        }
        if let index = AppLanguage.allCases.firstIndex(of: AppLanguage.current) {
            languagePopup.selectItem(at: index)
        }
    }

    private func updateDisplayCurrencyPopupFromSettings() {
        let titles = CurrencyCode.allCases.map(\.displayTitle)
        if displayCurrencyPopup.itemArray.map(\.title) != titles {
            displayCurrencyPopup.removeAllItems()
            displayCurrencyPopup.addItems(withTitles: titles)
        }
        if let index = CurrencyCode.allCases.firstIndex(of: AppSettings.displayCurrency(for: .all)) {
            displayCurrencyPopup.selectItem(at: index)
        }
    }

    private func updateSettingsControlsFromSystem() {
        guard selectedSection == .settings else { return }
        launchAtLoginSwitch.state = LoginItemManager.isEnabled ? .on : .off
        showCodexStatusSwitch.state = AppSettings.showCodexStatusEnabled ? .on : .off
        quotaWarningsSwitch.state = AppSettings.quotaWarningsEnabled ? .on : .off
        profileAPITotalsSwitch.state = AppSettings.profileAPITotalsEnabled ? .on : .off
        claudeActiveQuotaRefreshSwitch.state = AppSettings.claudeActiveQuotaRefreshEnabled ? .on : .off
    }

    private func updateStatusMetricPopupsFromSettings() {
        isUpdatingStatusMetricPopups = true
        defer { isUpdatingStatusMetricPopups = false }

        let metricTitles = StatusBarMetric.allCases.map(\.title)
        if statusPrimaryMetricPopup.itemArray.map(\.title) != metricTitles {
            statusPrimaryMetricPopup.removeAllItems()
            statusPrimaryMetricPopup.addItems(withTitles: metricTitles)
        }
        if let primaryIndex = StatusBarMetric.allCases.firstIndex(of: AppSettings.statusBarPrimaryMetric) {
            statusPrimaryMetricPopup.selectItem(at: primaryIndex)
        }

        let secondaryTitles = [t(.statusMetricOff)] + metricTitles
        if statusSecondaryMetricPopup.itemArray.map(\.title) != secondaryTitles {
            statusSecondaryMetricPopup.removeAllItems()
            statusSecondaryMetricPopup.addItems(withTitles: secondaryTitles)
        }
        if let secondaryMetric = AppSettings.statusBarSecondaryMetric,
           let secondaryIndex = StatusBarMetric.allCases.firstIndex(of: secondaryMetric) {
            statusSecondaryMetricPopup.selectItem(at: secondaryIndex + 1)
        } else {
            statusSecondaryMetricPopup.selectItem(at: 0)
        }
    }

    private func updateCostControlsFromSettings() {
        guard selectedSection == .costs else { return }
        isUpdatingCostControls = true
        defer { isUpdatingCostControls = false }
        let costSource = selectedDetailsSource
        let isEditableSource = costSource != .all
        costAmountField.isEnabled = isEditableSource
        paymentStartDayField.isEnabled = isEditableSource
        paymentCurrencyPopup.isEnabled = isEditableSource
        displayCurrencyPopup.isEnabled = isEditableSource
        costAmountField.textColor = isEditableSource ? .white : NSColor.white.withAlphaComponent(0.58)
        paymentStartDayField.textColor = isEditableSource ? .white : NSColor.white.withAlphaComponent(0.58)
        if costAmountField.currentEditor() == nil {
            costAmountField.stringValue = paymentAmount(AppSettings.monthlyPlanCost(for: costSource), source: costSource)
        }
        let costReport = snapshot.map { sourceReport(for: $0) }
        if paymentStartDayField.currentEditor() == nil {
            paymentStartDayField.stringValue = isEditableSource
                ? effectivePaymentStartDay(in: costReport, paymentStartDay: AppSettings.paymentStartDay(for: costSource))
                : "--"
        }
        showHistoricalEmptyWeeksSwitch.state = AppSettings.showHistoricalEmptyWeeks ? .on : .off
        if let paymentIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.paymentCurrency(for: costSource)) {
            paymentCurrencyPopup.selectItem(at: paymentIndex)
        }
        if let displayIndex = CurrencyCode.allCases.firstIndex(of: AppSettings.displayCurrency(for: costSource)) {
            displayCurrencyPopup.selectItem(at: displayIndex)
        }
        let years = cachedAvailableCostYears(from: costReport, source: costSource)
        if !years.contains(selectedCostYear), let last = years.last {
            selectedCostYear = last
        }
        let titles = years.map(String.init)
        if costYearPopup.itemArray.map(\.title) != titles {
            costYearPopup.removeAllItems()
            costYearPopup.addItems(withTitles: titles)
        }
        if let yearIndex = years.firstIndex(of: selectedCostYear) {
            if costYearPopup.indexOfSelectedItem != yearIndex {
                costYearPopup.selectItem(at: yearIndex)
            }
        }
    }

    func preferredDocumentHeight(for width: CGFloat) -> CGFloat {
        let minHeight: CGFloat = selectedSection == .calendar ? 620 : 660
        let normalizedWidth = max(860, width)
        let contentWidth = normalizedWidth - detailsSidebarWidth - 56

        let targetHeight: CGFloat
        switch selectedSection {
        case .overview:
            // The Claude view hides the Codex reset-credits row (see drawOverview),
            // so it needs 104pt less height than the Codex/all view.
            targetHeight = selectedDetailsSource == .claude ? 746 : 850
        case .insights:
            let heatmapHeight: CGFloat = 148
            let topOffset: CGFloat = 78
            let bottomPadding: CGFloat = 44
            if contentWidth >= 940 {
                targetHeight = topOffset + 444 + 16 + heatmapHeight + bottomPadding
            } else {
                let listHeight: CGFloat = 444
                let detailHeight: CGFloat = 430
                targetHeight = topOffset + listHeight + 16 + detailHeight + 16 + heatmapHeight + bottomPadding
            }
        case .models:
            targetHeight = 660
        case .calendar:
            let gridHeight: CGFloat = normalizedWidth >= 1200 ? 246 : 232
            let detailHeight = selectedCalendarWeekSummary() != nil
                ? selectedWeekPanelPreferredHeight(contentWidth: contentWidth)
                : selectedDayPanelPreferredHeight(contentWidth: contentWidth)
            targetHeight = 174 + gridHeight + detailHeight
        case .costs:
            let topOffset: CGFloat = 78
            let sectionGap: CGFloat = 16
            let fiveHourPanelHeight: CGFloat = 176
            let bottomPadding: CGFloat = 44
            if let snapshot {
                let model = quotaCyclePageModel(for: snapshot)
                if model.moneySummary != nil {
                    targetHeight = topOffset + 96 + sectionGap + 172 + sectionGap + 330 + sectionGap + fiveHourPanelHeight + bottomPadding
                } else {
                    let weeklyPanelHeight = weeklyHistoryPanelHeight(rowCount: model.weeklyRows.count, contentWidth: contentWidth)
                    targetHeight = topOffset + 150 + sectionGap + weeklyPanelHeight + sectionGap + fiveHourPanelHeight + bottomPadding
                }
            } else {
                targetHeight = topOffset + 150 + sectionGap + 96 + sectionGap + fiveHourPanelHeight + bottomPadding
            }
        case .diagnostics:
            targetHeight = 714
        case .storage:
            if storageSnapshot != nil {
                let content = NSRect(x: 0, y: 28, width: contentWidth, height: 0)
                targetHeight = storagePageLayout(content: content).totalHeight
            } else {
                targetHeight = 660
            }
        case .settings:
            targetHeight = settingsContentTopOffset + settingsPanelHeight + settingsBottomPadding
        case .about:
            targetHeight = 580
        }
        return max(minHeight, targetHeight)
    }

    private func selectedDayPanelPreferredHeight(contentWidth: CGFloat) -> CGFloat {
        guard let snapshot else { return 248 }
        let report = calendarReport(for: snapshot)
        let day = selectedCalendarDay(in: report)
        if usesProfileAPIReport(for: snapshot), !profileSelectedDayUsesLocalFallback(snapshot: snapshot, report: report) {
            let localDay = day.flatMap { profileDay in snapshot.codex.byDay.first { $0.day == profileDay.day } }
            let apiEstimate = day.map { profileAPIDayEstimate(profileDay: $0, localDay: localDay) }
            let metricsCount = 3 + (apiEstimate?.hasPricedUsage == true ? 1 : 0)
            let startX = min(CGFloat(420), max(CGFloat(292), contentWidth * 0.50))
            let gap: CGFloat = 12
            let availableMetricWidth = max(0, contentWidth - startX - 18)
            let columns = metricsCount > 3 && availableMetricWidth >= 500 ? 4 : min(3, metricsCount)
            let metricRows = Int(ceil(Double(metricsCount) / Double(max(columns, 1))))
            let metricH: CGFloat = 74
            let metricsBottom = CGFloat(42) + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * gap
            let visibleModelRows = max(1, min(localDay?.modelBreakdown.count ?? 0, 5))
            let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
            let modelY = max(CGFloat(134), metricsBottom + 18)
            return max(284, modelY + minimumModelHeight + 18)
        }
        guard let day else { return 160 }

        let limit = sourceCostLimit(for: snapshot)
        let cost = planCostEstimate(
            report: report,
            selectedDay: day,
            limit: limit,
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        )
        let apiEstimate = APICostEstimator.estimate(day: day)
        let metricsCount = 4 + (cost == nil ? 0 : 1) + (apiEstimate.hasPricedUsage ? 1 : 0)
        let startX: CGFloat = 310
        let horizontalPadding: CGFloat = 36
        let availableMetricWidth = max(180, contentWidth - startX - horizontalPadding)
        let columns: Int
        if metricsCount > 4 {
            columns = availableMetricWidth >= 360 ? 3 : 2
        } else {
            columns = availableMetricWidth >= 460 ? 4 : 2
        }
        let metricH: CGFloat
        switch columns {
        case 4:
            metricH = 72
        case 3:
            metricH = 62
        default:
            metricH = 56
        }
        let metricRows = Int(ceil(Double(metricsCount) / Double(columns)))
        let metricsBottom = 24 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * 10
        let visibleModelRows = max(1, min(day.modelBreakdown.count, 5))
        let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
        let leftColumnBottom: CGFloat = daySourceSplit(snapshot: snapshot, day: day) != nil ? daySourceSplitPanelExtent : 112
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        let contentHeight = modelY + minimumModelHeight + 18
        return max(248, contentHeight)
    }

    private func selectedWeekPanelPreferredHeight(contentWidth: CGFloat) -> CGFloat {
        guard let snapshot, let summary = selectedCalendarWeekSummary() else { return 248 }
        let planValue = contributionWeekPlanValue(summary)
        let apiEstimate = contributionWeekAPIEstimate(summary)
        let metricsCount = 4 + (planValue == nil ? 0 : 1) + (apiEstimate.hasPricedUsage ? 1 : 0)
        let startX: CGFloat = 310
        let horizontalPadding: CGFloat = 36
        let availableMetricWidth = max(180, contentWidth - startX - horizontalPadding)
        let columns: Int
        if metricsCount > 4 {
            columns = availableMetricWidth >= 360 ? 3 : 2
        } else {
            columns = availableMetricWidth >= 460 ? 4 : 2
        }
        let metricH: CGFloat
        switch columns {
        case 4:
            metricH = 72
        case 3:
            metricH = 62
        default:
            metricH = 56
        }
        let metricRows = Int(ceil(Double(metricsCount) / Double(columns)))
        let metricsBottom = 24 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * 10
        let visibleModelRows = max(1, min(weekModelBreakdown(summary).count, 5))
        let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
        let leftColumnBottom: CGFloat = weekSourceSplit(snapshot: snapshot, summary: summary) != nil ? daySourceSplitPanelExtent : 112
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        return max(248, modelY + minimumModelHeight + 18)
    }

    private func sourceReport(for snapshot: DetailsSnapshot, source: QuotaViewOption? = nil) -> TokenReport {
        switch source ?? selectedDetailsSource {
        case .all:
            return snapshot.all
        case .codex:
            return snapshot.codex
        case .claude:
            return snapshot.claude
        }
    }

    private func sourceCostLimit(for snapshot: DetailsSnapshot) -> LiveRateLimit? {
        guard selectedDetailsSource != .claude else { return nil }
        return costEstimateLimit(from: snapshot.liveLimits)
    }

    private func sourceCostReferenceReport(for snapshot: DetailsSnapshot) -> TokenReport? {
        guard selectedDetailsSource != .claude else { return nil }
        return snapshot.costReferenceReport
    }

    private func usesProfileAPIReport(for snapshot: DetailsSnapshot) -> Bool {
        selectedDetailsSource == .codex
            && selectedSection != .calendar
            && AppSettings.profileAPITotalsEnabled
            && snapshot.accountUsage?.hasData == true
    }

    private func calendarReport(for snapshot: DetailsSnapshot) -> TokenReport {
        guard let report = rawProfileCalendarReport(for: snapshot) else {
            return sourceReport(for: snapshot)
        }
        return profileReportWithLocalFallback(report, localReport: snapshot.codex)
    }

    private func rawProfileCalendarReport(for snapshot: DetailsSnapshot) -> TokenReport? {
        guard usesProfileAPIReport(for: snapshot),
              let accountUsage = snapshot.accountUsage else {
            return nil
        }
        return accountUsage.report(days: 365)
    }

    private func selectedCalendarDay(in report: TokenReport) -> DayUsage? {
        selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
            ?? report.byDay.last(where: { $0.usage.total > 0 })
            ?? report.byDay.last
    }

    private func profileSelectedDayUsesLocalFallback(snapshot: DetailsSnapshot, report: TokenReport) -> Bool {
        guard usesProfileAPIReport(for: snapshot),
              let day = selectedCalendarDay(in: report),
              let localDay = snapshot.codex.byDay.first(where: { $0.day == day.day }),
              localDay.usage.total > 0 else {
            return false
        }
        let rawProfileTotal = rawProfileCalendarReport(for: snapshot)?
            .byDay
            .first { $0.day == day.day }?
            .usage
            .total ?? 0
        return rawProfileTotal == 0 && day.usage.total == localDay.usage.total
    }

    private func profileLifetimeTotal(for snapshot: DetailsSnapshot) -> Int64? {
        guard usesProfileAPIReport(for: snapshot),
              let value = snapshot.accountUsage?.summary.lifetimeTokens,
              value > 0 else {
            return nil
        }
        return value
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if selectedSection == .costs {
            updateCostHistoryHover(at: point)
            updateCostOverviewInfoHover(at: point)
            updateQuotaCycleHover(at: point)
        } else {
            if hoveredCostHistoryIndex != nil {
                hoveredCostHistoryIndex = nil
                needsDisplay = true
            }
            if hoveredQuotaCycleIndex != nil {
                hoveredQuotaCycleIndex = nil
                needsDisplay = true
            }
            if hoveredCostOverviewInfo != nil {
                hoveredCostOverviewInfo = nil
                needsDisplay = true
            }
        }
        updateDayValueInfoHover(at: point)
        updateProfileAPIInfoHover(at: point)
        updateContributionDayHover(at: point)
        updateContributionWeekHover(at: point)
        updateResetCreditHover(at: point)
        updateInsightUsageTimeHover(at: point)
        updateModelUsageRowHover(at: point)
        updateStorageGrowthHover(at: point)
    }

    private func updateStorageGrowthHover(at point: CGPoint) {
        guard selectedSection == .storage else {
            if hoveredStorageCellKey != nil || hoveredStorageSourceID != nil {
                hoveredStorageCellKey = nil
                hoveredStorageSourceID = nil
                needsDisplay = true
            }
            return
        }
        let match = storageGrowthCells.first { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }
        if hoveredStorageCellKey != match?.key {
            hoveredStorageCellKey = match?.key
            needsDisplay = true
        }
        let sourceMatch = storageSourceRowRects.first { entry in
            var zone = entry.value
            zone.size.width = max(0, zone.width - 130)
            return zone.contains(point)
        }?.key
        if hoveredStorageSourceID != sourceMatch {
            hoveredStorageSourceID = sourceMatch
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredCostHistoryIndex = nil
        hoveredCostOverviewInfo = nil
        hoveredContributionDay = nil
        hoveredContributionWeekKey = nil
        hoveredInsightHour = nil
        hoveredInsightPeriod = nil
        hoveredResetCreditIndex = nil
        isHoveringResetCreditHeader = false
        hoveredModelUsageRowIndex = nil
        hoveredStorageCellKey = nil
        hoveredStorageSourceID = nil
        isHoveringDayValueInfo = false
        isHoveringProfileAPIInfo = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        var shouldRedraw = false
        if hoveredCostHistoryIndex != nil {
            hoveredCostHistoryIndex = nil
            shouldRedraw = true
        }
        if hoveredCostOverviewInfo != nil {
            hoveredCostOverviewInfo = nil
            shouldRedraw = true
        }
        if hoveredContributionDay != nil {
            hoveredContributionDay = nil
            shouldRedraw = true
        }
        if hoveredContributionWeekKey != nil {
            hoveredContributionWeekKey = nil
            shouldRedraw = true
        }
        if hoveredInsightHour != nil {
            hoveredInsightHour = nil
            shouldRedraw = true
        }
        if hoveredInsightPeriod != nil {
            hoveredInsightPeriod = nil
            shouldRedraw = true
        }
        if hoveredResetCreditIndex != nil {
            hoveredResetCreditIndex = nil
            shouldRedraw = true
        }
        if isHoveringResetCreditHeader {
            isHoveringResetCreditHeader = false
            shouldRedraw = true
        }
        if hoveredModelUsageRowIndex != nil {
            hoveredModelUsageRowIndex = nil
            shouldRedraw = true
        }
        if hoveredStorageCellKey != nil {
            hoveredStorageCellKey = nil
            shouldRedraw = true
        }
        if hoveredStorageSourceID != nil {
            hoveredStorageSourceID = nil
            shouldRedraw = true
        }
        if isHoveringDayValueInfo {
            isHoveringDayValueInfo = false
            shouldRedraw = true
        }
        if isHoveringProfileAPIInfo {
            isHoveringProfileAPIInfo = false
            shouldRedraw = true
        }
        if shouldRedraw {
            needsDisplay = true
        }
        if scrollInsightListIfNeeded(with: event) {
            return
        }
        super.scrollWheel(with: event)
    }

    private func scrollInsightListIfNeeded(with event: NSEvent) -> Bool {
        guard selectedSection == .insights,
              let viewport = insightListViewportRect,
              viewport.contains(convert(event.locationInWindow, from: nil)) else {
            return false
        }

        let maxOffset = max(0, insightListContentHeight - viewport.height)
        guard maxOffset > 0 else { return false }

        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        insightListScrollOffset = min(max(0, insightListScrollOffset - delta), maxOffset)
        needsDisplay = true
        return true
    }

    private func updateContributionDayHover(at point: CGPoint) {
        guard selectedSection == .overview else {
            if hoveredContributionDay != nil {
                hoveredContributionDay = nil
                needsDisplay = true
            }
            return
        }
        let match = contributionDaySummaries.first {
            $0.value.hitRect.insetBy(dx: -3, dy: -3).contains(point)
        }
        let newDay = match?.key
        if hoveredContributionDay != newDay {
            hoveredContributionDay = newDay
            needsDisplay = true
        }
    }

    private func updateContributionWeekHover(at point: CGPoint) {
        guard selectedSection == .calendar else {
            if hoveredContributionWeekKey != nil {
                hoveredContributionWeekKey = nil
                needsDisplay = true
            }
            return
        }
        let match = contributionWeekDotRects.first {
            $0.value.insetBy(dx: -3, dy: -3).contains(point)
        }
        let newKey = match?.key
        if hoveredContributionWeekKey != newKey {
            hoveredContributionWeekKey = newKey
            needsDisplay = true
        }
    }

    private func updateResetCreditHover(at point: CGPoint) {
        guard selectedSection == .overview else {
            if hoveredResetCreditIndex != nil || isHoveringResetCreditHeader {
                hoveredResetCreditIndex = nil
                isHoveringResetCreditHeader = false
                needsDisplay = true
            }
            return
        }
        let match = resetCreditHitAreas.first { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }
        let newIndex = match?.index
        let newHeaderHover = resetCreditHeaderHitArea?.contains(point) == true
        if hoveredResetCreditIndex != newIndex || isHoveringResetCreditHeader != newHeaderHover {
            hoveredResetCreditIndex = newIndex
            isHoveringResetCreditHeader = newHeaderHover
            needsDisplay = true
        }
    }

    private func updateModelUsageRowHover(at point: CGPoint) {
        guard selectedSection == .models else {
            if hoveredModelUsageRowIndex != nil {
                hoveredModelUsageRowIndex = nil
                needsDisplay = true
            }
            return
        }
        let newIndex = modelUsageHoverRows.firstIndex { $0.rect.insetBy(dx: -3, dy: -2).contains(point) }
        if hoveredModelUsageRowIndex != newIndex {
            hoveredModelUsageRowIndex = newIndex
            needsDisplay = true
        }
    }

    private func updateCostHistoryHover(at point: CGPoint) {
        let match = costHistoryBarRects.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }
        let newIndex = match?.key
        if hoveredCostHistoryIndex != newIndex {
            hoveredCostHistoryIndex = newIndex
            needsDisplay = true
        }
    }

    private func updateCostOverviewInfoHover(at point: CGPoint) {
        let match = costOverviewInfoRects.first { $0.value.insetBy(dx: -4, dy: -4).contains(point) }
        let newInfo = match?.key
        if hoveredCostOverviewInfo != newInfo {
            hoveredCostOverviewInfo = newInfo
            needsDisplay = true
        }
    }

    private func updateInsightUsageTimeHover(at point: CGPoint) {
        guard selectedSection == .insights, selectedInsightDetailMode == .usageTime else {
            if hoveredInsightHour != nil || hoveredInsightPeriod != nil {
                hoveredInsightHour = nil
                hoveredInsightPeriod = nil
                needsDisplay = true
            }
            return
        }
        let newHour = insightHourRects.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key
        let newPeriod = newHour == nil ? insightPeriodRects.first { $0.value.insetBy(dx: -3, dy: -3).contains(point) }?.key : nil
        if hoveredInsightHour != newHour || hoveredInsightPeriod != newPeriod {
            hoveredInsightHour = newHour
            hoveredInsightPeriod = newPeriod
            needsDisplay = true
        }
    }

    private func updateDayValueInfoHover(at point: CGPoint) {
        let hovering = selectedSection == .calendar && (dayValueInfoRect?.contains(point) == true)
        if hovering != isHoveringDayValueInfo {
            isHoveringDayValueInfo = hovering
            needsDisplay = true
        }
    }

    private func updateProfileAPIInfoHover(at point: CGPoint) {
        let hovering = selectedSection == .calendar && (profileAPIInfoRect?.insetBy(dx: -4, dy: -4).contains(point) == true)
        if hovering != isHoveringProfileAPIInfo {
            isHoveringProfileAPIInfo = hovering
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (section, rect) in sidebarItemRects where rect.contains(point) {
            selectedSection = section
            if section == .calendar, let snapshot {
                let report = calendarReport(for: snapshot)
                selectedDay = preferredSelectedDay(in: report, fallback: selectedDay)
            }
            if section == .insights, let snapshot {
                normalizeSelectedInsight(for: insightReport(for: snapshot))
            }
            return
        }
        for (source, rect) in sourceOptionRects where rect.contains(point) {
            window?.makeFirstResponder(nil)
            selectedDetailsSource = source
            return
        }
        if selectedSection == .insights {
            for (filter, rect) in insightStatusFilterRects where rect.contains(point) {
                selectedInsightStatusFilter = filter
                insightListScrollOffset = 0
                needsDisplay = true
                return
            }
            for (days, rect) in insightWindowRects where rect.contains(point) {
                selectedInsightWindowDays = days
                if let snapshot {
                    normalizeSelectedInsight(for: insightReport(for: snapshot))
                }
                needsDisplay = true
                return
            }
            for (mode, rect) in insightDetailModeRects where rect.contains(point) {
                selectedInsightDetailMode = mode
                needsDisplay = true
                return
            }
            for (column, rect) in insightSortRects where rect.insetBy(dx: -4, dy: -4).contains(point) {
                if selectedInsightSort == column {
                    isInsightSortAscending.toggle()
                } else {
                    selectedInsightSort = column
                    isInsightSortAscending = column.defaultAscending
                }
                insightListScrollOffset = 0
                if let snapshot {
                    normalizeSelectedInsight(for: insightReport(for: snapshot))
                }
                needsDisplay = true
                return
            }
            for (key, rect) in insightRowRects where rect.contains(point) {
                selectedInsightKey = key
                needsDisplay = true
                return
            }
        }
        if selectedSection == .storage {
            if handleStorageMouseDown(at: point) {
                return
            }
        }
        if selectedSection == .settings {
            for (subsection, rect) in settingsSubsectionRects where rect.contains(point) {
                selectedSettingsSubsection = subsection
                return
            }
            for (style, rect) in numberUnitOptionRects where rect.contains(point) {
                onNumberUnitStyleChanged?(style)
                return
            }
            for (style, rect) in quotaDisplayStyleRects where rect.contains(point) {
                onQuotaDisplayStyleChanged?(style)
                return
            }
            for (metric, rect) in codexHomeRingMetricRects where rect.contains(point) {
                onCodexHomeRingMetricChanged?(metric)
                return
            }
            for (metric, rect) in claudeHomeRingMetricRects where rect.contains(point) {
                onClaudeHomeRingMetricChanged?(metric)
                return
            }
            if chooseLogFolderRect?.contains(point) == true {
                onChooseLogFolder?()
                return
            }
            if resetLogFolderRect?.contains(point) == true {
                onResetLogFolder?()
                return
            }
            if openLogFolderRect?.contains(point) == true {
                onOpenLogFolder?()
                return
            }
            if chooseCodexAPISourceRect?.contains(point) == true {
                onChooseCodexAPISource?()
                return
            }
            if resetCodexAPISourceRect?.contains(point) == true {
                onResetCodexAPISources?()
                return
            }
            if openCodexAPISourceRect?.contains(point) == true {
                onOpenCodexAPISource?()
                return
            }
        }
        if selectedSection == .costs,
           showHistoricalEmptyWeeksToggleRect?.insetBy(dx: -8, dy: -6).contains(point) == true {
            onShowHistoricalEmptyWeeksChanged?(!AppSettings.showHistoricalEmptyWeeks)
            hoveredCostHistoryIndex = nil
            needsDisplay = true
            needsLayout = true
            return
        }
        for (weekStart, rect) in contributionWeekDotRects where rect.insetBy(dx: -3, dy: -3).contains(point) {
            selectedWeekStartDay = selectedWeekStartDay == weekStart ? nil : weekStart
            onPreferredHeightChanged?()
            needsDisplay = true
            needsLayout = true
            return
        }
        for (day, rect) in contributionDayRects where rect.insetBy(dx: -2, dy: -2).contains(point) {
            selectedDay = day
            selectedWeekStartDay = nil
            AppSettings.selectedCalendarDay = day
            selectedSection = .calendar
            return
        }
        super.mouseDown(with: event)
    }

    /// Debug hook for --render-details=--select-week snapshots.
    func selectCalendarWeek(startDay: String) {
        selectedWeekStartDay = startDay
        needsDisplay = true
    }

    private func preferredSelectedDay(in report: TokenReport, fallback: String?) -> String? {
        if let global = AppSettings.selectedCalendarDay,
           report.byDay.contains(where: { $0.day == global }) {
            return global
        }
        if let fallback,
           report.byDay.contains(where: { $0.day == fallback }) {
            return fallback
        }
        return report.byDay.last(where: { $0.usage.total > 0 })?.day ?? report.byDay.last?.day
    }

    @objc private func paymentCurrencyPopupChanged() {
        guard !isUpdatingCostControls,
              selectedDetailsSource != .all,
              paymentCurrencyPopup.indexOfSelectedItem >= 0 else { return }
        let currency = CurrencyCode.allCases[paymentCurrencyPopup.indexOfSelectedItem]
        onPaymentCurrencyChanged?(currency, selectedDetailsSource)
        needsDisplay = true
        needsLayout = true
    }

    @objc private func displayCurrencyPopupChanged() {
        guard displayCurrencyPopup.indexOfSelectedItem >= 0 else { return }
        let currency = CurrencyCode.allCases[displayCurrencyPopup.indexOfSelectedItem]
        if selectedSection == .settings && selectedSettingsSubsection == .appearance {
            onDisplayCurrencyChanged?(currency, .all)
            needsDisplay = true
            return
        }
        guard !isUpdatingCostControls,
              selectedDetailsSource != .all else { return }
        onDisplayCurrencyChanged?(currency, selectedDetailsSource)
        needsDisplay = true
    }

    @objc private func costYearPopupChanged() {
        guard !isUpdatingCostControls,
              costYearPopup.indexOfSelectedItem >= 0,
              let title = costYearPopup.selectedItem?.title,
              let year = Int(title) else { return }
        selectedCostYear = year
        hoveredCostHistoryIndex = nil
        needsDisplay = true
    }

    @objc private func languagePopupChanged() {
        guard languagePopup.indexOfSelectedItem >= 0 else { return }
        let language = AppLanguage.allCases[languagePopup.indexOfSelectedItem]
        onLanguageChanged?(language)
        needsDisplay = true
        needsLayout = true
    }

    @objc private func statusPrimaryMetricPopupChanged() {
        guard !isUpdatingStatusMetricPopups,
              statusPrimaryMetricPopup.indexOfSelectedItem >= 0,
              StatusBarMetric.allCases.indices.contains(statusPrimaryMetricPopup.indexOfSelectedItem) else { return }
        let metric = StatusBarMetric.allCases[statusPrimaryMetricPopup.indexOfSelectedItem]
        onStatusBarMetricChanged?(.first, metric)
        needsDisplay = true
    }

    @objc private func statusSecondaryMetricPopupChanged() {
        guard !isUpdatingStatusMetricPopups,
              statusSecondaryMetricPopup.indexOfSelectedItem >= 0 else { return }
        let index = statusSecondaryMetricPopup.indexOfSelectedItem
        guard index > 0 else {
            onStatusBarMetricChanged?(.second, nil)
            needsDisplay = true
            return
        }
        let metricIndex = index - 1
        guard StatusBarMetric.allCases.indices.contains(metricIndex) else { return }
        onStatusBarMetricChanged?(.second, StatusBarMetric.allCases[metricIndex])
        needsDisplay = true
    }

    @objc private func showHistoricalEmptyWeeksChanged() {
        guard !isUpdatingCostControls else { return }
        onShowHistoricalEmptyWeeksChanged?(showHistoricalEmptyWeeksSwitch.state == .on)
        hoveredCostHistoryIndex = nil
        needsDisplay = true
        needsLayout = true
    }

    @objc private func launchAtLoginChanged() {
        onLaunchAtLoginChanged?(launchAtLoginSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
    }

    @objc private func showCodexStatusChanged() {
        onShowCodexStatusChanged?(showCodexStatusSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
        needsLayout = true
    }

    @objc private func quotaWarningsChanged() {
        onQuotaWarningsChanged?(quotaWarningsSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
    }

    @objc private func profileAPITotalsChanged() {
        onProfileAPITotalsChanged?(profileAPITotalsSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
        needsLayout = true
    }

    @objc private func claudeActiveQuotaRefreshChanged() {
        onClaudeActiveQuotaRefreshChanged?(claudeActiveQuotaRefreshSwitch.state == .on)
        updateSettingsControlsFromSystem()
        needsDisplay = true
        needsLayout = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === costAmountField {
            let editSource = costAmountEditingSource ?? selectedDetailsSource
            costAmountEditingSource = nil
            guard editSource != .all else {
                updateCostControlsFromSettings()
                return
            }
            let sanitized = String(costAmountField.stringValue.filter { "0123456789.".contains($0) })
            guard let value = Double(sanitized), value >= 0 else {
                updateCostControlsFromSettings()
                return
            }
            onPlanCostChanged?(value, editSource)
            costAmountField.stringValue = paymentAmount(AppSettings.monthlyPlanCost(for: selectedDetailsSource), source: selectedDetailsSource)
            needsDisplay = true
            needsLayout = true
            return
        }
        if field === paymentStartDayField {
            let editSource = paymentStartDayEditingSource ?? selectedDetailsSource
            paymentStartDayEditingSource = nil
            guard editSource != .all else {
                updateCostControlsFromSettings()
                return
            }
            let value = paymentStartDayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard dayFormatter().date(from: value) != nil else {
                updateCostControlsFromSettings()
                return
            }
            onPaymentStartDayChanged?(value, editSource)
            if editSource != selectedDetailsSource {
                updateCostControlsFromSettings()
            }
            needsDisplay = true
            needsLayout = true
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === costAmountField {
            costAmountEditingSource = selectedDetailsSource
        } else if field === paymentStartDayField {
            paymentStartDayEditingSource = selectedDetailsSource
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: appBackgroundTop, ending: appBackgroundBottom)?.draw(in: bounds, angle: -90)

        let sidebarWidth = detailsSidebarWidth
        sidebarBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height).fill()
        borderColor.setStroke()
        NSBezierPath(rect: NSRect(x: sidebarWidth, y: 0, width: 1, height: bounds.height)).stroke()

        drawSidebar(width: sidebarWidth)

        let content = sectionContent(for: selectedSection, in: bounds, sidebarWidth: sidebarWidth)
        contributionDayRects.removeAll()
        contributionDaySummaries.removeAll()
        contributionWeekSummaries.removeAll()
        contributionWeekDotRects.removeAll()
        resetCreditHeaderHitArea = nil
        resetCreditFetchedAtText = nil
        resetCreditHitAreas.removeAll()
        resetCreditTooltipRows.removeAll()
        costHistoryBarRects.removeAll()
        costHistoryRows.removeAll()
        quotaCycleHitAreas.removeAll()
        costOverviewInfoRects.removeAll()
        dayValueInfoRect = nil
        profileAPIInfoRect = nil
        insightRowRects.removeAll()
        insightWindowRects.removeAll()
        insightDetailModeRects.removeAll()
        insightHourRects.removeAll()
        insightHourBarRects.removeAll()
        insightPeriodRects.removeAll()
        insightSortRects.removeAll()
        insightStatusFilterRects.removeAll()
        insightListViewportRect = nil
        numberUnitOptionRects.removeAll()
        quotaDisplayStyleRects.removeAll()
        settingsSubsectionRects.removeAll()
        sourceOptionRects.removeAll()
        chooseLogFolderRect = nil
        resetLogFolderRect = nil
        openLogFolderRect = nil
        chooseCodexAPISourceRect = nil
        resetCodexAPISourceRect = nil
        openCodexAPISourceRect = nil
        storageGrowthCells.removeAll()
        storageSourceRowRects.removeAll()
        storageSourceMenuRects.removeAll()
        storageOpenFinderRect = nil
        storageExportRect = nil
        storageRefreshRect = nil

        let sourceSelectorWidth: CGFloat = showsDetailsSourceSelector ? min(286, max(246, content.width * 0.31)) : 0
        let headerTextWidth = showsDetailsSourceSelector ? max(260, content.width - sourceSelectorWidth - 18) : content.width
        drawText(currentDetailsHeaderTitle, rect: NSRect(x: content.minX, y: content.minY, width: headerTextWidth, height: 34), font: .systemFont(ofSize: 26, weight: .bold), color: .white)
        drawText(currentDetailsHeaderSubtitle, rect: NSRect(x: content.minX, y: content.minY + 36, width: headerTextWidth, height: 20), font: .systemFont(ofSize: 13, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))
        if showsDetailsSourceSelector {
            drawDetailsSourceSelector(content: content, width: sourceSelectorWidth)
        }

        if selectedSection == .storage {
            drawStoragePage(content: content)
            drawStorageGrowthTooltip(container: content)
            drawStorageSourceTooltip(container: content)
            return
        }

        guard let snapshot else {
            if selectedSection == .settings {
                drawSettingsPage(content: content)
            } else if selectedSection == .about {
                drawAboutPage(content: content)
            } else if isLoading {
                drawLoadingState(content: content)
            } else {
                drawText(t(.noDataLoaded), rect: NSRect(x: content.minX, y: content.minY + 92, width: content.width, height: 24), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
            }
            return
        }

        switch selectedSection {
        case .overview:
            drawOverview(snapshot: snapshot, content: content)
        case .insights:
            drawInsightsPage(snapshot: snapshot, content: content)
        case .models:
            drawModelsPage(snapshot: snapshot, content: content)
        case .calendar:
            drawCalendarPage(snapshot: snapshot, content: content)
        case .costs:
            drawQuotaCyclesPage(snapshot: snapshot, content: content)
        case .settings:
            drawSettingsPage(content: content)
        case .diagnostics:
            drawDiagnosticsPage(snapshot: snapshot, content: content)
        case .storage:
            break
        case .about:
            drawAboutPage(content: content)
        }

        if selectedSection == .calendar {
            drawDayValueInfoTooltip()
            drawProfileAPIInfoTooltip()
        } else if selectedSection == .overview {
            drawResetCreditTooltip(container: content)
        } else if selectedSection == .insights {
            drawInsightUsageTimeTooltip()
        } else if selectedSection == .costs {
            drawQuotaCycleTooltip(container: content)
        } else if selectedSection == .models {
            drawModelUsageRowTooltip(container: content)
        }
    }

    private func drawDetailsSourceSelector(content: NSRect, width: CGFloat) {
        let usesPlatformOnlySources = selectedSection == .diagnostics || selectedSection == .costs
        let options: [QuotaViewOption] = usesPlatformOnlySources ? [.codex, .claude] : [.all, .codex, .claude]
        let height: CGFloat = 30
        let gap: CGFloat = 8
        let rect = NSRect(x: content.maxX - width, y: content.minY + 6, width: width, height: height)
        let optionWidth = (rect.width - gap * CGFloat(options.count - 1)) / CGFloat(options.count)
        let selectedOption = usesPlatformOnlySources && selectedDetailsSource == .all ? QuotaViewOption.codex : selectedDetailsSource
        for (index, option) in options.enumerated() {
            let optionRect = NSRect(
                x: rect.minX + CGFloat(index) * (optionWidth + gap),
                y: rect.minY,
                width: optionWidth,
                height: height
            )
            sourceOptionRects[option] = optionRect
            drawSelectablePill(detailsSourceTitle(option), rect: optionRect, selected: option == selectedOption)
        }
    }

    private var currentDetailsHeaderTitle: String {
        if selectedSection == .insights, selectedInsightDetailMode == .usageTime {
            return localizedInsightUsageTimePageTitle
        }
        return selectedSection.headerTitle
    }

    private var currentDetailsHeaderSubtitle: String {
        if selectedSection == .insights, selectedInsightDetailMode == .usageTime {
            return localizedInsightUsageTimePageSubtitle
        }
        return selectedSection.subtitle
    }

    private func detailsSourceTitle(_ option: QuotaViewOption) -> String {
        switch option {
        case .all:
            switch AppLanguage.current {
            case .chinese:
                return "总和"
            case .traditionalChinese:
                return "總和"
            case .japanese:
                return "合計"
            default:
                return "Total"
            }
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }

    private func drawLoadingState(content: NSRect) {
        let progress = loadingProgress.clampedFraction
        let message = t(loadingProgress.messageKey)
        let percentText = "\(Int((progress * 100).rounded()))%"
        let y = content.minY + 92
        let progressWidth = min(content.width, 420)
        let labelRect = NSRect(x: content.minX, y: y, width: progressWidth - 56, height: 24)
        let percentRect = NSRect(x: content.minX + progressWidth - 50, y: y, width: 50, height: 24)
        drawText(message, rect: labelRect, font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.68))
        drawText(percentText, rect: percentRect, font: .monospacedDigitSystemFont(ofSize: 13, weight: .bold), color: accentTeal.withAlphaComponent(0.86))

        let track = NSRect(x: content.minX, y: y + 34, width: progressWidth, height: 10)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: track, xRadius: 5, yRadius: 5).fill()

        let fillWidth = max(progress > 0 ? 8 : 0, track.width * CGFloat(progress))
        let fillRect = NSRect(x: track.minX, y: track.minY, width: min(track.width, fillWidth), height: track.height)
        accentBlue.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 5, yRadius: 5).fill()

        drawText(t(.loadingUsageDetailsHint), rect: NSRect(x: content.minX, y: y + 58, width: content.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
    }

    private func drawSidebar(width: CGFloat) {
        sidebarItemRects.removeAll()
        drawText("AI Token Meter", rect: NSRect(x: 28, y: 28, width: width - 56, height: 28), font: .systemFont(ofSize: 20, weight: .bold), color: .white)
        drawText(t(.combinedUsage), rect: NSRect(x: 28, y: 58, width: width - 56, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
        for (index, section) in DetailsSection.visibleSections.enumerated() {
            let y = CGFloat(118 + index * 58)
            let rect = NSRect(x: 18, y: y, width: width - 36, height: 42)
            sidebarItemRects[section] = rect
            if section == selectedSection {
                accentBlue.withAlphaComponent(0.82).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            }
            let textColor = section == selectedSection ? NSColor.white : NSColor.white.withAlphaComponent(0.82)
            let iconRect = NSRect(x: rect.minX + 14, y: rect.minY + 12, width: 18, height: 18)
            drawSymbolIcon(sidebarSymbolName(section), in: iconRect, color: textColor.withAlphaComponent(section == selectedSection ? 1.0 : 0.72))
            drawText(section.title, rect: NSRect(x: rect.minX + 42, y: rect.minY + 10, width: rect.width - 56, height: 22), font: .systemFont(ofSize: 15, weight: .semibold), color: textColor)
        }
    }

    private func sidebarSymbolName(_ section: DetailsSection) -> String {
        switch section {
        case .overview: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .insights: return "waveform.path.ecg"
        case .costs: return "clock.arrow.circlepath"
        case .models: return "cpu"
        case .storage: return "internaldrive"
        case .settings: return "gearshape"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }

    private func drawSymbolIcon(_ name: String, in rect: NSRect, color: NSColor, pointSize: CGFloat = 13) {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)) else { return }
        let tinted = NSImage(size: base.size)
        tinted.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let target = NSRect(
            x: rect.midX - base.size.width / 2,
            y: rect.midY - base.size.height / 2,
            width: base.size.width,
            height: base.size.height
        )
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    }

    private func drawOverview(snapshot: DetailsSnapshot, content: NSRect) {
        // Reset credits are a Codex-only concept, so hide the row in the Claude view
        // and pull the panels below it up to fill the gap.
        let showResetCredits = selectedDetailsSource != .claude
        let cardsY = content.minY + 78
        let resetY = cardsY + 98
        let quotaY = showResetCredits ? resetY + 104 : resetY
        let modelsY = quotaY + 136
        let gridY = modelsY + 146
        let gridReport = calendarReport(for: snapshot)
        let gridTitle = usesProfileAPIReport(for: snapshot)
            ? "\(t(.pastYear)) · \(t(.profileAPISource))"
            : t(.pastYear)
        drawMetricCards(snapshot: snapshot, content: content)
        if showResetCredits {
            drawResetCreditCountdownRow(snapshot: snapshot, content: content, y: resetY, height: 88)
        }
        drawQuotaRows(snapshot: snapshot, content: content, y: quotaY, height: 120)
        drawModelRows(snapshot: snapshot, content: content, y: modelsY, height: 130, maxRows: 4)
        let gridHeight = contributionGridPreferredHeight(report: gridReport, width: content.width, compact: true)
        let gridRect = NSRect(x: content.minX, y: gridY, width: content.width, height: min(gridHeight, max(168, content.maxY - gridY)))
        drawContributionGrid(report: gridReport, rect: gridRect, title: gridTitle, compact: true)
    }

    private func drawMetricCards(snapshot: DetailsSnapshot, content: NSRect) {
        let gap: CGFloat = 12
        let report = sourceReport(for: snapshot)
        let apiEstimate = APICostEstimator.estimate(report: report)
        let displayCurrency = AppSettings.displayCurrency(for: selectedDetailsSource)
        let apiMoney = compactMoney(convertCurrency(apiEstimate.usdValue, from: .usd, to: displayCurrency), currency: displayCurrency)
        let cards: [(title: String, value: String, subtitle: String?, color: NSColor)]
        switch selectedDetailsSource {
        case .all:
            cards = [
                (detailsSourceTitle(.all), compactDashboardTotal(snapshot.all.usage.total), nil, .systemGreen),
                (t(.codex), compactDashboardTotal(snapshot.codex.usage.total), nil, .systemCyan),
                (t(.claude), compactDashboardTotal(snapshot.claude.usage.total), nil, .systemOrange),
                (t(.cache), String(format: "%.0f%%", report.usage.cachePercent), nil, .systemTeal),
                (t(.apiEquivalent), apiMoney, nil, accentTeal)
            ]
        case .codex:
            cards = [
                (t(.codex), compactDashboardTotal(report.usage.total), nil, .systemCyan),
                (t(.input), compactDashboardMetric(report.usage.input), nil, .systemGreen),
                (t(.output), compactDashboardMetric(report.usage.output), nil, .systemOrange),
                (t(.cache), String(format: "%.0f%%", report.usage.cachePercent), nil, .systemTeal),
                (t(.apiEquivalent), apiMoney, nil, accentTeal)
            ]
        case .claude:
            cards = [
                (t(.claude), compactDashboardTotal(report.usage.total), nil, .systemOrange),
                (t(.input), compactDashboardMetric(report.usage.input), nil, .systemGreen),
                (t(.output), compactDashboardMetric(report.usage.output), nil, .systemCyan),
                (t(.cache), String(format: "%.0f%%", report.usage.cachePercent), nil, .systemTeal),
                (t(.apiEquivalent), apiMoney, nil, accentTeal)
            ]
        }
        let cardW = (content.width - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        let valueFontSize: CGFloat = cardW < 136 ? 18 : (cardW < 176 ? 21 : 24)
        let titleFontSize: CGFloat = cardW < 136 ? 11 : 12
        for (index, card) in cards.enumerated() {
            let rect = NSRect(x: content.minX + CGFloat(index) * (cardW + gap), y: content.minY + 78, width: cardW, height: 82)
            drawPanel(rect)
            drawText(card.title, rect: NSRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 18), font: .systemFont(ofSize: titleFontSize, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
            let valueY = card.subtitle == nil ? rect.minY + 34 : rect.minY + 31
            let valueRect = NSRect(x: rect.minX + 14, y: valueY, width: rect.width - 28, height: 28)
            let valueFont = metricCardValueFont(text: card.value, maxWidth: valueRect.width, preferredSize: valueFontSize)
            drawText(card.value, rect: valueRect, font: valueFont, color: card.color)
            if let subtitle = card.subtitle {
                drawText(subtitle, rect: NSRect(x: rect.minX + 14, y: rect.minY + 60, width: rect.width - 28, height: 15), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
            }
        }
    }

    private func metricCardValueFont(text: String, maxWidth: CGFloat, preferredSize: CGFloat) -> NSFont {
        var size = preferredSize
        while size > 14 {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
            if measuredTextWidth(text, font: font) <= maxWidth {
                return font
            }
            size -= 1
        }
        return .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    private func drawResetCreditCountdownRow(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)

        let title = "\(t(.codex)) \(t(.resetCredits))"
        guard let resetCredits = snapshot.resetCredits else {
            drawText(title, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 240, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
            drawText(t(.resetCreditExpiryUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 42, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let count = max(0, resetCredits.availableCount)
        let countText = String(format: t(.resetCreditCountFormat), count)
        let titleText = "\(title) · \(countText)"
        let titleRect = NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 280, height: 20)
        resetCreditHeaderHitArea = titleRect.insetBy(dx: -8, dy: -5)
        resetCreditFetchedAtText = String(format: t(.resetCreditFetchedAtFormat), Self.resetCreditFullFormatter.string(from: resetCredits.readAt))
        if isHoveringResetCreditHeader, let headerHitArea = resetCreditHeaderHitArea {
            NSColor.white.withAlphaComponent(0.18).setStroke()
            let focus = NSBezierPath(roundedRect: headerHitArea, xRadius: 7, yRadius: 7)
            focus.lineWidth = 1
            focus.stroke()
        }
        drawText(titleText, rect: titleRect, font: .systemFont(ofSize: 15, weight: .bold), color: .white)

        guard count > 0 else {
            drawText(t(.resetCreditNoCredits), rect: NSRect(x: rect.minX + 16, y: rect.minY + 42, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let credits = Array(resetCredits.availableCredits
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
            .prefix(3))
        guard !credits.isEmpty else {
            drawText(t(.resetCreditExpiryUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 42, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let gap: CGFloat = 18
        let columnY = rect.minY + 36
        let columnH: CGFloat = 42
        let columnW = (rect.width - 32 - gap * 2) / 3
        for index in 0..<3 {
            let column = NSRect(x: rect.minX + 16 + CGFloat(index) * (columnW + gap), y: columnY, width: columnW, height: columnH)
            if index > 0 {
                NSColor.white.withAlphaComponent(0.08).setStroke()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: column.minX - gap / 2, y: column.minY + 2))
                path.line(to: NSPoint(x: column.minX - gap / 2, y: column.maxY - 2))
                path.stroke()
            }

            guard index < credits.count, let expiresAt = credits[index].expiresAt else {
                drawText("#\(index + 1)", rect: NSRect(x: column.minX, y: column.minY, width: column.width, height: 15), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.38))
                drawText("--", rect: NSRect(x: column.minX, y: column.minY + 18, width: column.width, height: 22), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: NSColor.white.withAlphaComponent(0.35))
                continue
            }

            resetCreditTooltipRows.append(credits[index])
            resetCreditHitAreas.append((rect: column, index: resetCreditTooltipRows.count - 1))
            if hoveredResetCreditIndex == resetCreditTooltipRows.count - 1 {
                NSColor.white.withAlphaComponent(0.28).setStroke()
                let focus = NSBezierPath(roundedRect: column.insetBy(dx: -8, dy: -5), xRadius: 7, yRadius: 7)
                focus.lineWidth = 1
                focus.stroke()
            }

            var meta = "#\(index + 1) · \(t(.resetCreditExpiresAt)) \(Self.resetCreditExpiryFormatter.string(from: expiresAt))"
            if credits[index].expirationIsEstimated {
                meta += " · \(t(.resetCreditEstimated))"
            }
            let countdown = resetCreditCountdown(to: expiresAt)
            let countdownFont = metricCardValueFont(text: countdown, maxWidth: column.width, preferredSize: 20)
            drawText(meta, rect: NSRect(x: column.minX, y: column.minY, width: column.width, height: 15), font: .systemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))
            drawText(countdown, rect: NSRect(x: column.minX, y: column.minY + 18, width: column.width, height: 24), font: countdownFont, color: resetCreditUrgencyColor(to: expiresAt))
        }
    }

    private func resetCreditCountdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return String(format: "%d天 %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
        case .japanese:
            return String(format: "%d日 %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
        default:
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
        }
    }

    private func resetCreditUrgencyColor(to date: Date, now: Date = Date()) -> NSColor {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 3 * 86_400 {
            return accentRose
        }
        if seconds <= 14 * 86_400 {
            return accentAmber
        }
        return accentBlue
    }

    private func drawResetCreditTooltip(container: NSRect) {
        if isHoveringResetCreditHeader,
           let hit = resetCreditHeaderHitArea,
           let fetchedAtText = resetCreditFetchedAtText {
            drawResetCreditHeaderTooltip(hit: hit, text: fetchedAtText, container: container)
            return
        }
        guard let index = hoveredResetCreditIndex,
              index >= 0, index < resetCreditTooltipRows.count,
              let hit = resetCreditHitAreas.first(where: { $0.index == index }) else {
            return
        }
        let credit = resetCreditTooltipRows[index]
        let grantedText = credit.grantedAt.map { Self.resetCreditFullFormatter.string(from: $0) } ?? "--"
        let expiresText = credit.expiresAt.map { Self.resetCreditFullFormatter.string(from: $0) } ?? "--"
        let remainingText = credit.expiresAt.map { resetCreditCountdown(to: $0) } ?? "--"
        let rows: [(String, String, NSColor)] = [
            (t(.resetCreditGrantedAt), grantedText, NSColor.white.withAlphaComponent(0.88)),
            (t(.resetCreditExpiresAt), expiresText, credit.expiresAt.map { resetCreditUrgencyColor(to: $0) } ?? accentAmber),
            (t(.remaining), remainingText, credit.expiresAt.map { resetCreditUrgencyColor(to: $0) } ?? accentAmber)
        ]

        let width: CGFloat = 278
        let height: CGFloat = 84
        var origin = CGPoint(x: hit.rect.midX - width / 2, y: hit.rect.minY - height - 10)
        if origin.y < container.minY + 10 {
            origin.y = hit.rect.maxY + 10
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        drawText("\(t(.resetCredits)) #\(index + 1)", rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        for (rowIndex, row) in rows.enumerated() {
            let y = tooltipRect.minY + 30 + CGFloat(rowIndex) * 16
            drawText(row.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 56, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))
            drawRight(row.1, rect: NSRect(x: tooltipRect.minX + 70, y: y - 1, width: tooltipRect.width - 80, height: 15), color: row.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    private func drawResetCreditHeaderTooltip(hit: NSRect, text: String, container: NSRect) {
        let width: CGFloat = 254
        let height: CGFloat = 42
        var origin = CGPoint(x: hit.minX, y: hit.maxY + 8)
        if origin.y + height > container.maxY - 10 {
            origin.y = hit.minY - height - 8
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        drawText(text, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 13, width: tooltipRect.width - 20, height: 16), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.9))
    }

    private func drawQuotaRows(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.quotaViews), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let rows: [(String, String, TokenReport)]
        switch selectedDetailsSource {
        case .all:
            rows = [
                (t(.all), t(.allDescription), snapshot.all),
                (t(.codex), t(.codexDescription), snapshot.codex),
                (t(.claude), t(.claudeDescription), snapshot.claude)
            ]
        case .codex:
            rows = [
                (t(.codex), t(.codexDescription), snapshot.codex)
            ]
        case .claude:
            rows = [
                (t(.claude), t(.claudeDescription), snapshot.claude)
            ]
        }
        let outputW: CGFloat = 92
        let inputW: CGFloat = 104
        let totalW: CGFloat = 104
        let gap: CGFloat = 14
        let outputX = rect.maxX - 16 - outputW
        let inputX = outputX - gap - inputW
        let totalX = inputX - gap - totalW
        let descriptionX = rect.minX + 104
        let descriptionW = max(92, totalX - descriptionX - 18)
        let headerY = rect.minY + 34
        drawRight(t(.total), rect: NSRect(x: totalX, y: headerY, width: totalW, height: 14), color: NSColor.white.withAlphaComponent(0.38), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.input), rect: NSRect(x: inputX, y: headerY, width: inputW, height: 14), color: NSColor.white.withAlphaComponent(0.38), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.output), rect: NSRect(x: outputX, y: headerY, width: outputW, height: 14), color: NSColor.white.withAlphaComponent(0.38), font: .systemFont(ofSize: 10, weight: .bold))
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 52 + CGFloat(index) * 22
            let rowRect = NSRect(x: rect.minX + 10, y: y - 2, width: rect.width - 20, height: 21)
            let rowIndex = modelUsageHoverRows.count
            modelUsageHoverRows.append(ModelUsageHoverRow(
                rect: rowRect,
                title: row.0,
                subtitle: row.1,
                usage: row.2.usage,
                shareText: nil,
                sessions: row.2.sessions,
                events: row.2.events,
                apiCostText: nil,
                apiCostColor: accentTeal
            ))
            if hoveredModelUsageRowIndex == rowIndex {
                NSColor.white.withAlphaComponent(0.055).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 5, yRadius: 5).fill()
            }
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: y, width: 90, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(row.1, rect: NSRect(x: descriptionX, y: y, width: descriptionW, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
            drawRight(compactDashboardMetric(row.2.usage.total), rect: NSRect(x: totalX, y: y, width: totalW, height: 18), color: .white)
            drawRight(compactDashboardMetric(row.2.usage.input), rect: NSRect(x: inputX, y: y, width: inputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
            drawRight(compactDashboardMetric(row.2.usage.output), rect: NSRect(x: outputX, y: y, width: outputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
        }
    }

    private func drawModelRows(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat, maxRows: Int) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.models), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let models = Array(sourceReport(for: snapshot).modelBreakdown.prefix(maxRows))
        if models.isEmpty {
            drawText(t(.noModelLabelsFound), rect: NSRect(x: rect.minX + 16, y: rect.minY + 48, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        for (index, model) in models.enumerated() {
            let y = rect.minY + 40 + CGFloat(index) * 20
            drawText(model.name, rect: NSRect(x: rect.minX + 16, y: y, width: rect.width - 320, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
            drawRight(compact(model.usage.total), rect: NSRect(x: rect.maxX - 300, y: y, width: 90, height: 18), color: .white)
            drawRight("\(model.sessions) \(t(.sessions).lowercased())", rect: NSRect(x: rect.maxX - 204, y: y, width: 90, height: 18), color: NSColor.white.withAlphaComponent(0.52))
            drawRight("\(model.events) \(t(.events).lowercased())", rect: NSRect(x: rect.maxX - 108, y: y, width: 92, height: 18), color: NSColor.white.withAlphaComponent(0.52))
        }
    }

    private func drawModelsTable(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat, maxRows: Int) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.models), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let breakdown = sourceReport(for: snapshot).modelBreakdown
        let models = Array(breakdown.prefix(maxRows))
        if models.isEmpty {
            drawText(t(.noModelLabelsFound), rect: NSRect(x: rect.minX + 16, y: rect.minY + 48, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let totalTokens = breakdown.reduce(Int64(0)) { $0 + $1.usage.total }
        drawModelShareBar(models: models, totalTokens: totalTokens, rect: NSRect(x: rect.minX + 16, y: rect.minY + 46, width: rect.width - 32, height: 8))

        let showsActivity = rect.width >= 920
        let gap: CGFloat = 10
        let moneyW: CGFloat = 104
        let eventsW: CGFloat = 76
        let sessionsW: CGFloat = 68
        let outputW: CGFloat = 84
        let inputW: CGFloat = 88
        let totalW: CGFloat = 88
        let shareW: CGFloat = 48
        let moneyX = rect.maxX - 16 - moneyW
        let eventsX = moneyX - gap - eventsW
        let sessionsX = eventsX - gap - sessionsW
        let outputX = (showsActivity ? sessionsX : moneyX) - gap - outputW
        let inputX = outputX - gap - inputW
        let totalX = inputX - gap - totalW
        let shareX = totalX - gap - shareW
        let nameX = rect.minX + 32
        let nameW = max(96, shareX - nameX - 12)

        let headerY = rect.minY + 64
        let headerColor = NSColor.white.withAlphaComponent(0.38)
        let headerFont = NSFont.systemFont(ofSize: 10, weight: .bold)
        drawRight("%", rect: NSRect(x: shareX, y: headerY, width: shareW, height: 14), color: headerColor, font: headerFont)
        drawRight(t(.total), rect: NSRect(x: totalX, y: headerY, width: totalW, height: 14), color: headerColor, font: headerFont)
        drawRight(t(.input), rect: NSRect(x: inputX, y: headerY, width: inputW, height: 14), color: headerColor, font: headerFont)
        drawRight(t(.output), rect: NSRect(x: outputX, y: headerY, width: outputW, height: 14), color: headerColor, font: headerFont)
        if showsActivity {
            drawRight(t(.sessions), rect: NSRect(x: sessionsX, y: headerY, width: sessionsW, height: 14), color: headerColor, font: headerFont)
            drawRight(t(.events), rect: NSRect(x: eventsX, y: headerY, width: eventsW, height: 14), color: headerColor, font: headerFont)
        }
        drawRight(t(.apiEquivalent), rect: NSRect(x: moneyX, y: headerY, width: moneyW, height: 14), color: headerColor, font: headerFont)

        let displayCurrency = AppSettings.displayCurrency(for: selectedDetailsSource)
        for (index, model) in models.enumerated() {
            let y = rect.minY + 82 + CGFloat(index) * 20
            let color = modelShareColor(index)
            let share = totalTokens > 0 ? Double(model.usage.total) / Double(totalTokens) * 100 : 0
            let shareText = share > 0 && share < 0.1 ? "<0.1%" : String(format: "%.1f%%", share)
            let estimate = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            let moneyText = estimate.hasPricedUsage
                ? compactMoney(convertCurrency(estimate.usdValue, from: .usd, to: displayCurrency), currency: displayCurrency)
                : "—"
            let rowRect = NSRect(x: rect.minX + 10, y: y - 2, width: rect.width - 20, height: 19)
            let rowIndex = modelUsageHoverRows.count
            modelUsageHoverRows.append(ModelUsageHoverRow(
                rect: rowRect,
                title: model.name,
                subtitle: nil,
                usage: model.usage,
                shareText: shareText,
                sessions: model.sessions,
                events: model.events,
                apiCostText: estimate.hasPricedUsage ? displayAPIMoney(estimate.usdValue, source: selectedDetailsSource) : nil,
                apiCostColor: estimate.hasPricedUsage ? accentTeal : NSColor.white.withAlphaComponent(0.38)
            ))
            if hoveredModelUsageRowIndex == rowIndex {
                NSColor.white.withAlphaComponent(0.055).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 5, yRadius: 5).fill()
            }
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 16, y: y + 5, width: 8, height: 8)).fill()
            drawText(model.name, rect: NSRect(x: nameX, y: y, width: nameW, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
            drawRight(shareText, rect: NSRect(x: shareX, y: y, width: shareW, height: 18), color: NSColor.white.withAlphaComponent(0.62), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
            drawRight(compact(model.usage.total), rect: NSRect(x: totalX, y: y, width: totalW, height: 18), color: .white)
            drawRight(compact(model.usage.input), rect: NSRect(x: inputX, y: y, width: inputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
            drawRight(compact(model.usage.output), rect: NSRect(x: outputX, y: y, width: outputW, height: 18), color: NSColor.white.withAlphaComponent(0.58))
            if showsActivity {
                drawRight("\(model.sessions)", rect: NSRect(x: sessionsX, y: y, width: sessionsW, height: 18), color: NSColor.white.withAlphaComponent(0.52))
                drawRight("\(model.events)", rect: NSRect(x: eventsX, y: y, width: eventsW, height: 18), color: NSColor.white.withAlphaComponent(0.52))
            }
            drawRight(moneyText, rect: NSRect(x: moneyX, y: y, width: moneyW, height: 18), color: estimate.hasPricedUsage ? accentTeal.withAlphaComponent(0.92) : NSColor.white.withAlphaComponent(0.34), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }
    }

    private func exactTokenText(_ value: Int64) -> String {
        format(value)
    }

    private func drawModelUsageRowTooltip(container: NSRect) {
        guard let hoveredModelUsageRowIndex,
              modelUsageHoverRows.indices.contains(hoveredModelUsageRowIndex) else {
            return
        }
        let row = modelUsageHoverRows[hoveredModelUsageRowIndex]
        var lines: [(String, String, NSColor)] = [
            (t(.total), exactTokenText(row.usage.total), NSColor.white.withAlphaComponent(0.9)),
            (t(.input), exactTokenText(row.usage.input), NSColor.white.withAlphaComponent(0.78)),
            (t(.output), exactTokenText(row.usage.output), NSColor.white.withAlphaComponent(0.78))
        ]
        if let shareText = row.shareText {
            lines.append(("%", shareText, NSColor.white.withAlphaComponent(0.74)))
        }
        if let sessions = row.sessions {
            lines.append((t(.sessions), "\(sessions)", NSColor.white.withAlphaComponent(0.72)))
        }
        if let events = row.events {
            lines.append((t(.events), "\(events)", NSColor.white.withAlphaComponent(0.72)))
        }
        if let apiCostText = row.apiCostText {
            lines.append((t(.apiEquivalent), apiCostText, row.apiCostColor))
        }

        let width: CGFloat = 274
        let headerHeight: CGFloat = row.subtitle == nil ? 31 : 49
        let height = headerHeight + CGFloat(lines.count) * 16 + 10
        let gap: CGFloat = 10
        var origin = CGPoint(x: row.rect.midX - width / 2, y: row.rect.maxY + gap)
        if origin.y + height > container.maxY - 10 {
            origin.y = row.rect.minY - height - gap
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        drawTruncatedText(row.title, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        if let subtitle = row.subtitle {
            drawTruncatedText(subtitle, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 27, width: tooltipRect.width - 20, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        }
        let firstLineY = tooltipRect.minY + headerHeight
        for (index, line) in lines.enumerated() {
            let y = firstLineY + CGFloat(index) * 16
            drawText(line.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 92, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))
            drawRight(line.1, rect: NSRect(x: tooltipRect.minX + 104, y: y - 1, width: tooltipRect.width - 114, height: 15), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    private var modelShareColors: [NSColor] {
        [
            accentBlue,
            accentTeal,
            accentAmber,
            accentRose,
            NSColor(calibratedRed: 0.702, green: 0.533, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.478, green: 0.867, blue: 0.443, alpha: 1.0),
            NSColor(calibratedRed: 1.0, green: 0.537, blue: 0.396, alpha: 1.0),
            NSColor(calibratedRed: 0.408, green: 0.780, blue: 0.949, alpha: 1.0),
            NSColor(calibratedRed: 0.910, green: 0.796, blue: 0.478, alpha: 1.0),
            NSColor(calibratedRed: 0.769, green: 0.545, blue: 0.729, alpha: 1.0)
        ]
    }

    private func modelShareColor(_ index: Int) -> NSColor {
        modelShareColors[index % modelShareColors.count]
    }

    private func drawModelShareBar(models: [ModelUsage], totalTokens: Int64, rect: NSRect) {
        guard totalTokens > 0 else { return }
        inputSurfaceColor.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        var x = rect.minX
        for (index, model) in models.enumerated() {
            let width = rect.width * CGFloat(Double(model.usage.total) / Double(totalTokens))
            modelShareColor(index).withAlphaComponent(0.92).setFill()
            NSRect(x: x, y: rect.minY, width: width, height: rect.height).fill()
            x += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMonthlySpendPanel(snapshot: DetailsSnapshot, content: NSRect, y: CGFloat, height: CGFloat) {
        let rect = NSRect(x: content.minX, y: y, width: content.width, height: height)
        drawPanel(rect)
        drawText(t(.monthlySpendHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: 220, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        let costSource = selectedDetailsSource
        let rows = monthlySpendRows(
            report: sourceReport(for: snapshot),
            limit: sourceCostLimit(for: snapshot),
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: costSource),
            paymentStartDay: AppSettings.paymentStartDay(for: costSource)
        )
        guard !rows.isEmpty else {
            drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 48, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let visible = Array(rows.prefix(4))
        drawRight(t(.total), rect: NSRect(x: rect.maxX - 210, y: rect.minY + 24, width: 110, height: 14), color: NSColor.white.withAlphaComponent(0.40), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight("%", rect: NSRect(x: rect.maxX - 84, y: rect.minY + 24, width: 68, height: 14), color: NSColor.white.withAlphaComponent(0.40), font: .systemFont(ofSize: 10, weight: .bold))
        for (index, row) in visible.enumerated() {
            let rowY = rect.minY + 42 + CGFloat(index) * 16
            drawText(row.month, rect: NSRect(x: rect.minX + 16, y: rowY, width: 72, height: 14), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .white)
            drawRight(displayMoney(row.usedValue, source: costSource), rect: NSRect(x: rect.maxX - 210, y: rowY, width: 110, height: 14), color: .white, font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
            drawRight(String(format: "%.0f%%", row.usedPercentOfPlan), rect: NSRect(x: rect.maxX - 84, y: rowY, width: 68, height: 14), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }
    }

    private func drawModelsPage(snapshot: DetailsSnapshot, content: NSRect) {
        modelUsageHoverRows.removeAll(keepingCapacity: true)
        drawQuotaRows(snapshot: snapshot, content: content, y: content.minY + 78, height: 128)
        drawModelsTable(snapshot: snapshot, content: content, y: content.minY + 222, height: 296, maxRows: 10)
        let noteRect = NSRect(x: content.minX, y: content.minY + 534, width: content.width, height: min(76, content.maxY - (content.minY + 534)))
        drawPanel(noteRect)
        drawText(t(.modelGroupingNote), rect: NSRect(x: noteRect.minX + 16, y: noteRect.minY + 16, width: noteRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
        drawText(t(.modelMissingNote), rect: NSRect(x: noteRect.minX + 16, y: noteRect.minY + 40, width: noteRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
    }

    private func drawInsightsPage(snapshot: DetailsSnapshot, content: NSRect) {
        let report = insightReport(for: snapshot)
        let rows = sortedInsightRows(report.rows)
        drawInsightControls(content: content)
        let topY = content.minY + 112

        if selectedInsightDetailMode == .usageTime {
            let timeRect = NSRect(x: content.minX, y: topY, width: content.width, height: min(520, max(360, content.maxY - topY)))
            drawInsightUsageTimePage(report: report, rect: timeRect)
            return
        }

        if rows.isEmpty {
            let emptyRect = NSRect(x: content.minX, y: topY, width: content.width, height: 180)
            drawPanel(emptyRect)
            drawText(insightEmptyTitle, rect: NSRect(x: emptyRect.minX + 18, y: emptyRect.minY + 22, width: emptyRect.width - 36, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
            drawText(insightEmptyDescription, rect: NSRect(x: emptyRect.minX + 18, y: emptyRect.minY + 56, width: emptyRect.width - 36, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.54))
            return
        }

        drawInsightStatusChips(rows: rows, content: content, y: topY)
        let filtered = rows.filter { selectedInsightStatusFilter.matches($0.risk) }
        let panelTop = topY + 40
        let grouped = selectedInsightStatusFilter == .all

        if filtered.isEmpty {
            let listRect = NSRect(x: content.minX, y: panelTop, width: content.width, height: 140)
            drawPanel(listRect)
            drawCentered(AppLanguage.current.insightCopy.projectCount(0), rect: NSRect(x: listRect.minX, y: listRect.midY - 9, width: listRect.width, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
            return
        }

        let panelHeight: CGFloat = 384
        if content.width >= 940 {
            let gap: CGFloat = 16
            let listWidth = min(CGFloat(370), content.width * 0.40)
            let listRect = NSRect(x: content.minX, y: panelTop, width: listWidth, height: panelHeight)
            let detailRect = NSRect(x: listRect.maxX + gap, y: panelTop, width: content.width - listWidth - gap, height: panelHeight)
            let heatmapRect = NSRect(x: content.minX, y: panelTop + panelHeight + 16, width: content.width, height: 148)
            drawInsightProjectList(rows: filtered, grouped: grouped, rect: listRect)
            let selected = selectedInsight(in: filtered)
            drawInsightDetail(selected, rect: detailRect)
            drawInsightHeatmap(row: selected, rect: heatmapRect)
        } else {
            let selected = selectedInsight(in: filtered)
            let listRect = NSRect(x: content.minX, y: panelTop, width: content.width, height: 384)
            let detailRect = NSRect(x: content.minX, y: listRect.maxY + 16, width: content.width, height: panelHeight)
            let heatmapRect = NSRect(x: content.minX, y: detailRect.maxY + 16, width: content.width, height: 148)
            drawInsightProjectList(rows: filtered, grouped: grouped, rect: listRect)
            drawInsightDetail(selected, rect: detailRect)
            drawInsightHeatmap(row: selected, rect: heatmapRect)
        }
    }

    private func drawInsightStatusChips(rows: [RepoInsight], content: NSRect, y: CGFloat) {
        let copy = AppLanguage.current.insightCopy
        let chipH: CGFloat = 28
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let chips: [(InsightStatusFilter, String, NSColor?)] = [
            (.all, localizedInsightFilterAll, nil),
            (.frequentCompression, copy.riskLabel(.frequentCompression), accentRose),
            (.longRunning, copy.riskLabel(.longRunning), accentAmber),
            (.good, localizedInsightGoodStatus, accentTeal)
        ]
        var x = content.minX
        for (filter, label, dotColor) in chips {
            let count = rows.reduce(0) { $0 + (filter.matches($1.risk) ? 1 : 0) }
            let text = "\(label) \(count)"
            let textW = measuredTextWidth(text, font: font)
            let dotW: CGFloat = dotColor == nil ? 0 : 13
            let chipRect = NSRect(x: x, y: y, width: textW + dotW + 24, height: chipH)
            insightStatusFilterRects[filter] = chipRect
            let selected = selectedInsightStatusFilter == filter
            (selected ? accentBlue.withAlphaComponent(0.74) : inputSurfaceColor.withAlphaComponent(0.30)).setFill()
            NSBezierPath(roundedRect: chipRect, xRadius: chipH / 2, yRadius: chipH / 2).fill()
            (selected ? accentTeal.withAlphaComponent(0.45) : borderColor.withAlphaComponent(0.8)).setStroke()
            let outline = NSBezierPath(roundedRect: chipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: chipH / 2, yRadius: chipH / 2)
            outline.lineWidth = 1
            outline.stroke()
            var textX = chipRect.minX + 12
            if let dotColor {
                dotColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: textX, y: chipRect.midY - 4, width: 8, height: 8)).fill()
                textX += 13
            }
            drawText(text, rect: NSRect(x: textX, y: chipRect.minY + 7, width: textW + 4, height: 15), font: font, color: selected ? .white : NSColor.white.withAlphaComponent(0.75))
            x += chipRect.width + 8
        }
        let totalConversations = rows.reduce(0) { $0 + $1.conversations }
        let summary = "\(copy.windowLabel(days: selectedInsightWindowDays)) · \(totalConversations) \(copy.chatsMetric)"
        if content.maxX - x > 200 {
            drawRight(summary, rect: NSRect(x: content.maxX - 260, y: y + 7, width: 244, height: 15), color: NSColor.white.withAlphaComponent(0.42), font: font)
        }
    }

    private func selectedInsight(in rows: [RepoInsight]) -> RepoInsight {
        if let selectedInsightKey,
           let row = rows.first(where: { $0.key == selectedInsightKey }) {
            return row
        }
        selectedInsightKey = rows.first?.key
        return rows[0]
    }

    private func insightReport(for snapshot: DetailsSnapshot) -> RepoInsightsReport {
        switch selectedDetailsSource {
        case .all:
            return snapshot.repoInsightReports[selectedInsightWindowDays] ?? snapshot.repoInsights
        case .codex:
            return snapshot.codexRepoInsightReports[selectedInsightWindowDays] ?? snapshot.codexRepoInsights
        case .claude:
            return snapshot.claudeRepoInsightReports[selectedInsightWindowDays] ?? snapshot.claudeRepoInsights
        }
    }

    private func normalizeSelectedInsight(for report: RepoInsightsReport) {
        if let selectedInsightKey,
           report.rows.contains(where: { $0.key == selectedInsightKey }) {
            return
        }
        selectedInsightKey = sortedInsightRows(report.rows).first?.key
    }

    private func sortedInsightRows(_ rows: [RepoInsight]) -> [RepoInsight] {
        rows.sorted { lhs, rhs in
            let ascending = isInsightSortAscending
            switch selectedInsightSort {
            case .project:
                let order = insightListDisplayName(for: lhs).localizedCaseInsensitiveCompare(insightListDisplayName(for: rhs))
                if order != .orderedSame {
                    return ascending ? order == .orderedAscending : order == .orderedDescending
                }
                if lhs.conversations != rhs.conversations {
                    return lhs.conversations > rhs.conversations
                }
            case .conversations:
                if lhs.conversations != rhs.conversations {
                    return ascending ? lhs.conversations < rhs.conversations : lhs.conversations > rhs.conversations
                }
                if lhs.compressions != rhs.compressions {
                    return lhs.compressions > rhs.compressions
                }
            case .compressions:
                if lhs.compressions != rhs.compressions {
                    return ascending ? lhs.compressions < rhs.compressions : lhs.compressions > rhs.compressions
                }
                if lhs.conversations != rhs.conversations {
                    return lhs.conversations > rhs.conversations
                }
            case .average:
                if lhs.averageCompressionsPerConversation != rhs.averageCompressionsPerConversation {
                    return ascending ? lhs.averageCompressionsPerConversation < rhs.averageCompressionsPerConversation : lhs.averageCompressionsPerConversation > rhs.averageCompressionsPerConversation
                }
                if lhs.compressions != rhs.compressions {
                    return lhs.compressions > rhs.compressions
                }
            case .status:
                let lhsRank = insightRiskSortRank(lhs.risk)
                let rhsRank = insightRiskSortRank(rhs.risk)
                if lhsRank != rhsRank {
                    return ascending ? lhsRank < rhsRank : lhsRank > rhsRank
                }
                if lhs.compressions != rhs.compressions {
                    return lhs.compressions > rhs.compressions
                }
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func insightRiskSortRank(_ risk: RepoInsightRisk) -> Int {
        switch risk {
        case .healthy: return 0
        case .wellSplit: return 1
        case .longRunning: return 2
        case .frequentCompression: return 3
        }
    }

    private var insightEmptyTitle: String {
        AppLanguage.current.insightCopy.emptyTitle
    }

    private var insightEmptyDescription: String {
        AppLanguage.current.insightCopy.emptyDescription
    }

    private func drawInsightControls(content: NSRect) {
        let y = content.minY + 64
        let rowH: CGFloat = 28
        let modePillW: CGFloat = 104
        let modeGap: CGFloat = 8
        let modes: [(InsightDetailMode, String)] = [
            (.usageHabits, localizedInsightDetailMode(.usageHabits)),
            (.usageTime, localizedInsightDetailMode(.usageTime))
        ]
        var x = content.minX
        for mode in modes {
            let rect = NSRect(x: x, y: y, width: modePillW, height: rowH)
            insightDetailModeRects[mode.0] = rect
            drawSelectablePill(mode.1, rect: rect, selected: selectedInsightDetailMode == mode.0)
            x += modePillW + modeGap
        }

        x += 8
        drawInsightControlSeparator(x: x, y: y, height: rowH)
        x += 17

        let compactH: CGFloat = 24
        let compactY = y + (rowH - compactH) / 2
        let compactGap: CGFloat = 5
        let sourceW: CGFloat = 54
        for option in [QuotaViewOption.all, .codex, .claude] {
            let rect = NSRect(x: x, y: compactY, width: sourceW, height: compactH)
            sourceOptionRects[option] = rect
            drawCompactInsightPill(detailsSourceTitle(option), rect: rect, selected: selectedDetailsSource == option)
            x += sourceW + compactGap
        }

        x += 12 - compactGap
        drawInsightControlSeparator(x: x, y: y, height: rowH)
        x += 17

        let copy = AppLanguage.current.insightCopy
        let windowW: CGFloat = 46
        for days in insightWindowOptions {
            let rect = NSRect(x: x, y: compactY, width: windowW, height: compactH)
            insightWindowRects[days] = rect
            drawCompactInsightPill(copy.windowLabel(days: days), rect: rect, selected: days == selectedInsightWindowDays)
            x += windowW + compactGap
        }
    }

    private func drawInsightControlSeparator(x: CGFloat, y: CGFloat, height: CGFloat) {
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: NSRect(x: x, y: y + 6, width: 1, height: height - 12)).fill()
    }

    private func drawCompactInsightPill(_ text: String, rect: NSRect, selected: Bool) {
        let fill = selected ? accentBlue.withAlphaComponent(0.74) : inputSurfaceColor.withAlphaComponent(0.30)
        let stroke = selected ? accentTeal.withAlphaComponent(0.50) : borderColor.withAlphaComponent(0.80)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        stroke.setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        outline.lineWidth = 1
        outline.stroke()
        drawCentered(text, rect: rect.insetBy(dx: 4, dy: 0), font: .systemFont(ofSize: 10, weight: .bold), color: selected ? .white : NSColor.white.withAlphaComponent(0.72))
    }

    private func drawInsightProjectList(rows: [RepoInsight], grouped: Bool, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        drawPanel(rect)

        let headerY = rect.minY + 18
        let avgW: CGFloat = 56
        let conversationsW: CGFloat = 56
        let avgX = rect.maxX - 16 - avgW
        let conversationsX = avgX - 10 - conversationsW
        let nameW = max(110, conversationsX - rect.minX - 34)
        let headerColor = NSColor.white.withAlphaComponent(0.42)
        let projectHeader = NSRect(x: rect.minX + 16, y: headerY, width: nameW, height: 16)
        let conversationsHeader = NSRect(x: conversationsX, y: headerY, width: conversationsW, height: 16)
        let avgHeader = NSRect(x: avgX, y: headerY, width: avgW, height: 16)
        insightSortRects[.project] = projectHeader
        insightSortRects[.conversations] = conversationsHeader
        insightSortRects[.average] = avgHeader
        drawInsightHeader(.project, rect: projectHeader, alignment: .left, color: headerColor)
        drawInsightHeader(.conversations, rect: conversationsHeader, alignment: .right, color: headerColor)
        drawInsightHeader(.average, rect: avgHeader, alignment: .right, color: headerColor)

        enum ListItem {
            case group(String, Int)
            case row(RepoInsight)
        }
        var items: [ListItem] = []
        if grouped {
            let attention = rows.filter { $0.risk == .frequentCompression || $0.risk == .longRunning }
            let good = rows.filter { $0.risk == .wellSplit || $0.risk == .healthy }
            if !attention.isEmpty {
                items.append(.group(localizedInsightAttentionGroup, attention.count))
                items.append(contentsOf: attention.map(ListItem.row))
            }
            if !good.isEmpty {
                items.append(.group(localizedInsightGoodStatus, good.count))
                items.append(contentsOf: good.map(ListItem.row))
            }
        } else {
            items = rows.map(ListItem.row)
        }

        let rowHeight: CGFloat = 40
        let groupHeight: CGFloat = 30
        func itemHeight(_ item: ListItem) -> CGFloat {
            if case .group = item { return groupHeight }
            return rowHeight
        }
        let contentHeight = items.reduce(CGFloat(0)) { $0 + itemHeight($1) }
        insightListContentHeight = contentHeight
        let viewport = NSRect(x: rect.minX, y: rect.minY + 42, width: rect.width, height: max(0, rect.height - 84))
        insightListViewportRect = viewport
        let maxOffset = max(0, contentHeight - viewport.height)
        insightListScrollOffset = min(max(0, insightListScrollOffset), maxOffset)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: viewport).addClip()
        var y = viewport.minY - insightListScrollOffset
        for item in items {
            let itemH = itemHeight(item)
            defer { y += itemH }
            guard y + itemH > viewport.minY, y < viewport.maxY else { continue }
            switch item {
            case .group(let title, let count):
                drawText("\(title) · \(count)", rect: NSRect(x: rect.minX + 16, y: y + 11, width: rect.width - 32, height: 14), font: .systemFont(ofSize: 10, weight: .bold), color: NSColor.white.withAlphaComponent(0.38))
            case .row(let row):
                let rowRect = NSRect(x: rect.minX, y: y, width: rect.width, height: itemH)
                insightRowRects[row.key] = rowRect
                let riskColor = insightRiskColor(row.risk)
                let isSelected = row.key == selectedInsightKey
                if isSelected {
                    accentBlue.withAlphaComponent(0.76).setFill()
                    NSBezierPath(roundedRect: rowRect.insetBy(dx: 6, dy: 2), xRadius: 7, yRadius: 7).fill()
                }
                riskColor.withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX + 10, y: y + 9, width: 3, height: itemH - 18), xRadius: 1.5, yRadius: 1.5).fill()
                let textColor = isSelected ? NSColor.white : NSColor.white.withAlphaComponent(0.78)
                drawTruncatedText(insightListDisplayName(for: row), rect: NSRect(x: rect.minX + 22, y: y + 11, width: nameW - 6, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: textColor)
                drawRight("\(row.conversations)", rect: NSRect(x: conversationsX, y: y + 11, width: conversationsW, height: 18), color: isSelected ? .white : NSColor.white.withAlphaComponent(0.62))
                drawRight(String(format: "%.2f", row.averageCompressionsPerConversation), rect: NSRect(x: avgX, y: y + 11, width: avgW, height: 18), color: isSelected ? .white : riskColor.withAlphaComponent(0.95))
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        drawInsightListScrollbar(viewport: viewport, contentHeight: contentHeight)

        drawText(copy.projectCount(rows.count), rect: NSRect(x: rect.minX + 16, y: rect.maxY - 30, width: 200, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
    }

    private enum InsightHeaderAlignment {
        case left
        case center
        case right
    }

    private func drawInsightHeader(_ column: InsightSortColumn, rect: NSRect, alignment: InsightHeaderAlignment, color: NSColor) {
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let arrowFont = NSFont.systemFont(ofSize: 10, weight: .bold)
        let arrow = selectedInsightSort == column ? (isInsightSortAscending ? "↑" : "↓") : nil
        let arrowWidth: CGFloat = 10

        switch alignment {
        case .left:
            drawText(column.title, rect: rect, font: font, color: color)
            if let arrow {
                let x = rect.minX + measuredTextWidth(column.title, font: font) + 4
                drawText(arrow, rect: NSRect(x: x, y: rect.minY, width: arrowWidth, height: rect.height), font: arrowFont, color: color)
            }
        case .center:
            drawCentered(column.title, rect: rect, font: font, color: color)
            if let arrow {
                let titleWidth = measuredTextWidth(column.title, font: font)
                let x = rect.midX + titleWidth / 2 + 4
                drawText(arrow, rect: NSRect(x: x, y: rect.minY, width: arrowWidth, height: rect.height), font: arrowFont, color: color)
            }
        case .right:
            let titleRect = NSRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - arrowWidth - 4), height: rect.height)
            drawRight(column.title, rect: titleRect, color: color, font: font)
            if let arrow {
                drawText(arrow, rect: NSRect(x: rect.maxX - arrowWidth, y: rect.minY, width: arrowWidth, height: rect.height), font: arrowFont, color: color)
            }
        }
    }

    private func drawInsightListScrollbar(viewport: NSRect, contentHeight: CGFloat) {
        guard contentHeight > viewport.height else { return }
        let track = NSRect(x: viewport.maxX - 7, y: viewport.minY + 4, width: 3, height: viewport.height - 8)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let thumbHeight = max(CGFloat(28), track.height * viewport.height / contentHeight)
        let maxOffset = max(1, contentHeight - viewport.height)
        let travel = max(0, track.height - thumbHeight)
        let thumbY = track.minY + travel * (insightListScrollOffset / maxOffset)
        accentBlue.withAlphaComponent(0.52).setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight), xRadius: 1.5, yRadius: 1.5).fill()
    }

    private func insightListDisplayName(for row: RepoInsight) -> String {
        if row.displayName.hasPrefix("github/") {
            let rawName = String(row.displayName.dropFirst("github/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let name = rawName.split(separator: "/").last {
                return String(name)
            }
            return githubRepoName(from: row.primaryFolder)
                ?? githubRepoName(from: row.key)
                ?? "github"
        }
        if row.displayName.hasPrefix("worktrees/") {
            let rawName = String(row.displayName.dropFirst("worktrees/".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let name = rawName.split(separator: "/").last {
                return String(name)
            }
            return "worktrees"
        }
        if row.displayName.hasPrefix("~/Documents/") {
            let parts = row.displayName.split(separator: "/")
            return parts.last.map(String.init) ?? row.displayName
        }
        return row.displayName
    }

    private func githubRepoName(from path: String) -> String? {
        let components = (path as NSString)
            .standardizingPath
            .split(separator: "/")
            .map(String.init)
        guard let githubIndex = components.firstIndex(of: "github"),
              components.count > githubIndex + 1 else {
            return nil
        }
        let repoName = components[githubIndex + 1]
        return repoName.isEmpty ? nil : repoName
    }

    private func drawInsightDetail(_ row: RepoInsight, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        drawPanel(rect)
        drawText(row.displayName, rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 140, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
        drawInsightRiskPill(row.risk, rect: NSRect(x: rect.maxX - 112, y: rect.minY + 16, width: 88, height: 24))

        drawText(insightDiagnosisText(for: row), rect: NSRect(x: rect.minX + 16, y: rect.minY + 46, width: rect.width - 32, height: 34), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.66))

        let riskColor = insightRiskColor(row.risk)
        let attention = row.risk == .frequentCompression || row.risk == .longRunning
        let plain = NSColor.white.withAlphaComponent(0.94)
        let metricY = rect.minY + 90
        let metricW = (rect.width - 32) / 5
        let metrics: [(String, String, NSColor)] = [
            (copy.chatsMetric, "\(row.conversations)", plain),
            (copy.turnsMetric, "\(row.turns)", plain),
            (copy.compactionsMetric, "\(row.compressions)", attention ? riskColor : plain),
            (copy.avgCompactionsMetric, String(format: "%.2f", row.averageCompressionsPerConversation), attention ? riskColor : plain),
            (copy.maxTurnsMetric, "\(row.longestTurns)", plain)
        ]
        for (index, metric) in metrics.enumerated() {
            let x = rect.minX + 16 + CGFloat(index) * metricW
            drawTruncatedText(metric.0, rect: NSRect(x: x, y: metricY, width: metricW - 10, height: 14), font: .systemFont(ofSize: 10, weight: .bold), color: NSColor.white.withAlphaComponent(0.48))
            drawText(metric.1, rect: NSRect(x: x, y: metricY + 16, width: metricW - 10, height: 24), font: .monospacedDigitSystemFont(ofSize: 19, weight: .bold), color: metric.2)
        }

        let sectionY = metricY + 52
        let sectionH: CGFloat = 124
        let sectionGap: CGFloat = 10
        let sectionW = (rect.width - 32 - sectionGap) / 2
        let lengthRect = NSRect(x: rect.minX + 16, y: sectionY, width: sectionW, height: sectionH)
        drawInsightDonutSection(
            title: copy.lengthDistributionTitle,
            rightText: nil,
            buckets: [
                (copy.shortBucket, row.turnBuckets.short, accentTeal),
                (copy.mediumBucket, row.turnBuckets.medium, accentBlue),
                (copy.longBucket, row.turnBuckets.long, accentAmber),
                (copy.extraLongBucket, row.turnBuckets.extraLong, accentRose)
            ],
            rect: lengthRect
        )

        let conversationTotal = max(1, row.conversations)
        let compressedCount = max(0, conversationTotal - row.compressionBuckets.zero)
        let compressedPercent = Int(round(Double(compressedCount) / Double(conversationTotal) * 100))
        let compressionRect = NSRect(x: lengthRect.maxX + sectionGap, y: sectionY, width: sectionW, height: sectionH)
        drawInsightDonutSection(
            title: copy.compactionDistributionTitle,
            rightText: copy.compactedPercent(compressedPercent),
            buckets: [
                (copy.zeroCompactions, row.compressionBuckets.zero, accentTeal),
                (copy.oneCompaction, row.compressionBuckets.one, accentBlue),
                (copy.twoCompactions, row.compressionBuckets.two, accentAmber),
                (copy.threePlusCompactions, row.compressionBuckets.threePlus, accentRose)
            ],
            rect: compressionRect
        )

        let recommendationRect = NSRect(x: rect.minX + 16, y: compressionRect.maxY + 12, width: rect.width - 32, height: max(70, rect.maxY - compressionRect.maxY - 26))
        drawInsightRecommendations(row, rect: recommendationRect)
    }

    private func drawInsightDonutSection(title: String, rightText: String?, buckets: [(String, Int, NSColor)], rect: NSRect) {
        inputSurfaceColor.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        let rightW: CGFloat = rightText == nil ? 0 : 96
        drawTruncatedText(title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 9, width: rect.width - 24 - rightW, height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: NSColor.white.withAlphaComponent(0.76))
        if let rightText {
            drawRight(rightText, rect: NSRect(x: rect.maxX - 12 - rightW, y: rect.minY + 10, width: rightW, height: 15), color: NSColor.white.withAlphaComponent(0.48), font: .systemFont(ofSize: 10, weight: .semibold))
        }

        let total = max(1, buckets.reduce(0) { $0 + $1.1 })
        let bodyTop = rect.minY + 30
        let bodyHeight = rect.height - 38
        let radius: CGFloat = min(30, bodyHeight / 2 - 4)
        let thickness: CGFloat = 11
        let center = NSPoint(x: rect.minX + 14 + radius, y: bodyTop + bodyHeight / 2)

        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = thickness
        NSColor.white.withAlphaComponent(0.06).setStroke()
        track.stroke()

        var angle: CGFloat = 90
        for bucket in buckets where bucket.1 > 0 {
            let sweep = 360 * CGFloat(bucket.1) / CGFloat(total)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle + sweep, clockwise: false)
            arc.lineWidth = thickness
            arc.lineCapStyle = .butt
            bucket.2.withAlphaComponent(0.9).setStroke()
            arc.stroke()
            angle += sweep
        }

        if let dominant = buckets.max(by: { $0.1 < $1.1 }), dominant.1 > 0 {
            let percent = Int(round(Double(dominant.1) / Double(total) * 100))
            drawCentered("\(percent)%", rect: NSRect(x: center.x - radius + 4, y: center.y - 7, width: (radius - 4) * 2, height: 14), font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: dominant.2.withAlphaComponent(0.95))
        }

        let legendX = center.x + radius + 18
        let rowH = bodyHeight / CGFloat(max(1, buckets.count))
        for (index, bucket) in buckets.enumerated() {
            let y = bodyTop + CGFloat(index) * rowH
            bucket.2.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: y + rowH / 2 - 3.5, width: 7, height: 7)).fill()
            let percent = Int(round(Double(bucket.1) / Double(total) * 100))
            let valueW: CGFloat = 82
            drawTruncatedText(bucket.0, rect: NSRect(x: legendX + 12, y: y + rowH / 2 - 7, width: max(30, rect.maxX - 12 - valueW - legendX - 18), height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            drawRight("\(bucket.1) · \(percent)%", rect: NSRect(x: rect.maxX - 12 - valueW, y: y + rowH / 2 - 7, width: valueW, height: 14), color: NSColor.white.withAlphaComponent(0.72), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    private func drawInsightUsageTimePage(report: RepoInsightsReport, rect: NSRect) {
        drawPanel(rect)
        let hours = aggregateInsightHours(report)
        let windowLabel = AppLanguage.current.insightCopy.windowLabel(days: selectedInsightWindowDays)
        let title = "\(localizedInsightUsageTimeTitle) · \(detailsSourceTitle(selectedDetailsSource)) · \(windowLabel)"
        drawText(title, rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 36, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
        drawText(insightUsageTimeSummary(hours), rect: NSRect(x: rect.minX + 18, y: rect.minY + 44, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))

        let summaryRect = NSRect(x: rect.minX + 18, y: rect.minY + 78, width: rect.width - 36, height: 74)
        drawInsightTimePeriodCards(hours: hours, rect: summaryRect)

        let chartPanel = NSRect(x: rect.minX + 18, y: summaryRect.maxY + 16, width: rect.width - 36, height: max(210, rect.maxY - summaryRect.maxY - 40))
        inputSurfaceColor.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: chartPanel, xRadius: 7, yRadius: 7).fill()
        drawText(localizedInsightHourlyCallsTitle, rect: NSRect(x: chartPanel.minX + 14, y: chartPanel.minY + 12, width: chartPanel.width - 28, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: NSColor.white.withAlphaComponent(0.76))

        let hoursByHour = Dictionary(uniqueKeysWithValues: hours.map { ($0.hour, $0) })
        let maxTurns = max(1, hours.map(\.turns).max() ?? 0)
        let axisWidth: CGFloat = 44
        let chart = NSRect(x: chartPanel.minX + 18 + axisWidth, y: chartPanel.minY + 48, width: chartPanel.width - 36 - axisWidth, height: chartPanel.height - 94)
        let tickValues = insightAxisTickValues(maxValue: maxTurns)
        let axisMax = max(1, tickValues.last ?? maxTurns)
        for tick in tickValues {
            let ratio = CGFloat(tick) / CGFloat(axisMax)
            let y = chart.maxY - chart.height * ratio
            let tickColor = NSColor.white.withAlphaComponent(tick == 0 ? 0.30 : 0.12)
            tickColor.setStroke()
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: chart.minX - 5, y: y))
            grid.line(to: NSPoint(x: chart.maxX, y: y))
            grid.lineWidth = tick == 0 ? 1.1 : 0.8
            grid.stroke()
            drawRight(compact(Int64(tick)), rect: NSRect(x: chartPanel.minX + 12, y: y - 7, width: axisWidth - 12, height: 14), color: NSColor.white.withAlphaComponent(0.46), font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold))
        }
        NSColor.white.withAlphaComponent(0.20).setStroke()
        let axis = NSBezierPath()
        axis.move(to: NSPoint(x: chart.minX - 5, y: chart.minY))
        axis.line(to: NSPoint(x: chart.minX - 5, y: chart.maxY))
        axis.lineWidth = 1
        axis.stroke()
        drawRight("turns", rect: NSRect(x: chartPanel.minX + 12, y: chart.minY - 18, width: axisWidth - 12, height: 12), color: NSColor.white.withAlphaComponent(0.36), font: .systemFont(ofSize: 8, weight: .bold))
        let gap: CGFloat = 4
        let barWidth = max(CGFloat(6), (chart.width - CGFloat(23) * gap) / 24)
        for hour in 0..<24 {
            let turns = hoursByHour[hour]?.turns ?? 0
            let ratio = CGFloat(turns) / CGFloat(axisMax)
            let height = turns > 0 ? max(CGFloat(5), chart.height * ratio) : 2
            let x = chart.minX + CGFloat(hour) * (barWidth + gap)
            let bar = NSRect(x: x, y: chart.maxY - height, width: barWidth, height: height)
            insightHourRects[hour] = NSRect(x: x - max(2, gap / 2), y: chart.minY, width: barWidth + max(4, gap), height: chart.height)
            insightHourBarRects[hour] = bar
            insightHourColor(hour).withAlphaComponent(turns > 0 ? 0.86 : 0.16).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            if hoveredInsightHour == hour {
                NSColor.white.withAlphaComponent(0.34).setStroke()
                let focus = NSBezierPath(roundedRect: bar.insetBy(dx: -3, dy: -3), xRadius: 5, yRadius: 5)
                focus.lineWidth = 1.4
                focus.stroke()
            }
            if [0, 6, 12, 18, 23].contains(hour) {
                drawCentered(String(format: "%02d", hour), rect: NSRect(x: x - 6, y: chart.maxY + 6, width: barWidth + 12, height: 14), font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
            }
        }

        let legendY = chartPanel.maxY - 30
        let legend: [(String, NSColor)] = [
            (localizedInsightMorning, accentTeal),
            (localizedInsightAfternoon, accentBlue),
            (localizedInsightEvening, accentAmber),
            (localizedInsightLateNight, accentRose)
        ]
        var legendX = chartPanel.minX + 14
        for item in legend {
            item.1.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: legendY + 4, width: 7, height: 7)).fill()
            drawText(item.0, rect: NSRect(x: legendX + 11, y: legendY, width: 78, height: 15), font: .systemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))
            legendX += min(92, chartPanel.width / 4)
        }
    }

    private func aggregateInsightHours(_ report: RepoInsightsReport) -> [RepoInsightHour] {
        var buckets: [Int: RepoInsightHour] = [:]
        for row in report.rows {
            for hour in row.hours {
                var bucket = buckets[hour.hour] ?? RepoInsightHour(hour: hour.hour, conversations: 0, turns: 0, tokens: 0)
                bucket.conversations += hour.conversations
                bucket.turns += hour.turns
                bucket.tokens += hour.tokens
                buckets[hour.hour] = bucket
            }
        }
        return buckets.values.sorted { $0.hour < $1.hour }
    }

    private func insightAxisTickValues(maxValue: Int) -> [Int] {
        guard maxValue > 0 else { return [0, 1] }
        if maxValue <= 4 {
            return Array(0...maxValue)
        }
        let roughStep = Double(maxValue) / 4.0
        let magnitude = pow(10.0, floor(log10(roughStep)))
        let normalized = roughStep / magnitude
        let multiplier: Double
        if normalized <= 1 {
            multiplier = 1
        } else if normalized <= 2 {
            multiplier = 2
        } else if normalized <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }
        let step = max(1, Int(multiplier * magnitude))
        let top = Int(ceil(Double(maxValue) / Double(step))) * step
        return stride(from: 0, through: top, by: step).map { $0 }
    }

    private func drawInsightTimePeriodCards(hours: [RepoInsightHour], rect: NSRect) {
        let groups = insightPeriodDefinitions()
        let totals = groups.map { item in
            (item.0, hours.filter { item.1.contains($0.hour) }.reduce(0) { $0 + $1.turns }, item.2)
        }
        let totalTurns = max(1, totals.reduce(0) { $0 + $1.1 })
        let gap: CGFloat = 10
        let cardW = (rect.width - gap * CGFloat(max(0, totals.count - 1))) / CGFloat(max(1, totals.count))
        for (index, item) in totals.enumerated() {
            let card = NSRect(x: rect.minX + CGFloat(index) * (cardW + gap), y: rect.minY, width: cardW, height: rect.height)
            insightPeriodRects[item.0] = card
            inputSurfaceColor.withAlphaComponent(0.62).setFill()
            NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
            item.2.withAlphaComponent(0.80).setFill()
            NSBezierPath(roundedRect: NSRect(x: card.minX, y: card.minY, width: 4, height: card.height), xRadius: 2, yRadius: 2).fill()
            if hoveredInsightPeriod == item.0 {
                NSColor.white.withAlphaComponent(0.22).setStroke()
                let focus = NSBezierPath(roundedRect: card.insetBy(dx: -2, dy: -2), xRadius: 8, yRadius: 8)
                focus.lineWidth = 1.3
                focus.stroke()
            }
            drawText(item.0, rect: NSRect(x: card.minX + 14, y: card.minY + 10, width: card.width - 28, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: NSColor.white.withAlphaComponent(0.58))
            drawText("\(item.1)", rect: NSRect(x: card.minX + 14, y: card.minY + 30, width: card.width * 0.55, height: 24), font: .monospacedDigitSystemFont(ofSize: 18, weight: .bold), color: item.2.withAlphaComponent(0.96))
            let percent = Int(round(Double(item.1) / Double(totalTurns) * 100))
            drawRight("\(percent)%", rect: NSRect(x: card.midX, y: card.minY + 34, width: card.width / 2 - 14, height: 18), color: NSColor.white.withAlphaComponent(0.44), font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold))
        }
    }

    private func drawInsightUsageTimeTooltip() {
        guard selectedSection == .insights,
              selectedInsightDetailMode == .usageTime,
              let snapshot else {
            return
        }
        let report = insightReport(for: snapshot)
        let hours = aggregateInsightHours(report)
        let totalTurns = max(1, hours.reduce(0) { $0 + $1.turns })

        let title: String
        let color: NSColor
        let anchorRect: NSRect
        let lines: [(String, String)]

        if let hoveredInsightHour,
           let rect = insightHourBarRects[hoveredInsightHour] ?? insightHourRects[hoveredInsightHour] {
            let turns = hours.first(where: { $0.hour == hoveredInsightHour })?.turns ?? 0
            title = String(format: "%02d:00-%02d:00", hoveredInsightHour, (hoveredInsightHour + 1) % 24)
            color = insightHourColor(hoveredInsightHour)
            anchorRect = rect
            lines = [
                (localizedInsightTooltipTurns, "\(turns) turns"),
                (localizedInsightTooltipShare, "\(Int(round(Double(turns) / Double(totalTurns) * 100)))%"),
                (localizedInsightTooltipDailyAverage, String(format: "%.1f turns", Double(turns) / Double(max(1, selectedInsightWindowDays)))),
                (localizedInsightTooltipPeriod, localizedInsightDayPart(for: hoveredInsightHour))
            ]
        } else if let hoveredInsightPeriod,
                  let rect = insightPeriodRects[hoveredInsightPeriod],
                  let period = insightPeriodDefinitions().first(where: { $0.0 == hoveredInsightPeriod }) {
            let periodHours = hours.filter { period.1.contains($0.hour) }
            let turns = periodHours.reduce(0) { $0 + $1.turns }
            let peak = periodHours.max { $0.turns < $1.turns }
            title = hoveredInsightPeriod
            color = period.2
            anchorRect = rect
            lines = [
                (localizedInsightTooltipTurns, "\(turns) turns"),
                (localizedInsightTooltipShare, "\(Int(round(Double(turns) / Double(totalTurns) * 100)))%"),
                (localizedInsightTooltipDailyAverage, String(format: "%.1f turns", Double(turns) / Double(max(1, selectedInsightWindowDays)))),
                (localizedInsightTooltipHourlyAverage, String(format: "%.1f turns", Double(turns) / 6.0)),
                (localizedInsightTooltipPeakHour, peak.map { String(format: "%02d:00 · %d", $0.hour, $0.turns) } ?? "--")
            ]
        } else {
            return
        }

        let width: CGFloat = 236
        let rowHeight: CGFloat = 20
        let height: CGFloat = 42 + CGFloat(lines.count) * rowHeight
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.minY - height - 10)
        if origin.y < bounds.minY + 12 {
            origin.y = anchorRect.maxY + 10
        }
        origin.x = max(bounds.minX + 12, min(origin.x, bounds.maxX - width - 12))
        origin.y = max(bounds.minY + 12, min(origin.y, bounds.maxY - height - 12))
        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        color.withAlphaComponent(0.55).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()
        drawText(title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: .white)

        for (index, line) in lines.enumerated() {
            let y = rect.minY + 34 + CGFloat(index) * rowHeight
            drawText(line.0, rect: NSRect(x: rect.minX + 12, y: y, width: 104, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            drawRight(line.1, rect: NSRect(x: rect.minX + 118, y: y, width: rect.width - 130, height: 16), color: color.withAlphaComponent(0.96), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    private func insightPeriodDefinitions() -> [(String, Range<Int>, NSColor)] {
        [
            (localizedInsightMorning, 6..<12, accentTeal),
            (localizedInsightAfternoon, 12..<18, accentBlue),
            (localizedInsightEvening, 18..<24, accentAmber),
            (localizedInsightLateNight, 0..<6, accentRose)
        ]
    }

    private func insightUsageTimeSummary(_ hours: [RepoInsightHour]) -> String {
        guard let peak = hours.max(by: { $0.turns < $1.turns }), peak.turns > 0 else {
            return localizedInsightNoUsageTime
        }
        return localizedInsightPeakSummary(range: localizedInsightDayPart(for: peak.hour), hour: peak.hour, turns: peak.turns)
    }

    private func insightHourColor(_ hour: Int) -> NSColor {
        switch hour {
        case 6..<12: return accentTeal
        case 12..<18: return accentBlue
        case 18..<24: return accentAmber
        default: return accentRose
        }
    }

    private func localizedInsightDetailMode(_ mode: InsightDetailMode) -> String {
        switch (mode, AppLanguage.current) {
        case (.usageHabits, .chinese), (.usageHabits, .traditionalChinese): return "使用习惯"
        case (.usageHabits, .japanese): return "使い方"
        case (.usageHabits, .polish): return "Nawyki"
        case (.usageHabits, .english): return "Habits"
        case (.usageHabits, _): return "Habits"
        case (.usageTime, .chinese), (.usageTime, .traditionalChinese): return "使用时间"
        case (.usageTime, .japanese): return "時間帯"
        case (.usageTime, .polish): return "Godziny"
        case (.usageTime, .english): return "Time"
        case (.usageTime, _): return "Time"
        }
    }

    private var localizedInsightUsageTimeTitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "调用时间分布（按小时）"
        case .japanese: return "利用時間の分布（時間別）"
        case .polish: return "Rozkład użycia według godzin"
        case .english: return "Usage time distribution by hour"
        default: return "Usage time distribution by hour"
        }
    }

    private var localizedInsightUsageTimePageTitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "使用时间"
        case .japanese: return "利用時間"
        case .polish: return "Godziny uzycia"
        case .english: return "Usage Time"
        default: return "Usage Time"
        }
    }

    private var localizedInsightUsageTimePageSubtitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "按来源和时间窗口查看高峰调用时段"
        case .japanese: return "ソースと期間ごとの利用ピークを確認"
        case .polish: return "Pory szczytu wedlug zrodla i zakresu"
        case .english: return "Find peak usage periods by source and window"
        default: return "Find peak usage periods by source and window"
        }
    }

    private var localizedInsightTooltipTurns: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "数量"
        case .japanese: return "回数"
        case .polish: return "Liczba"
        case .english: return "Count"
        default: return "Count"
        }
    }

    private var localizedInsightTooltipShare: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "占比"
        case .japanese: return "割合"
        case .polish: return "Udzial"
        case .english: return "Share"
        default: return "Share"
        }
    }

    private var localizedInsightTooltipDailyAverage: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "日均"
        case .japanese: return "日平均"
        case .polish: return "Dziennie"
        case .english: return "Daily avg"
        default: return "Daily avg"
        }
    }

    private var localizedInsightTooltipHourlyAverage: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "小时均值"
        case .japanese: return "時間平均"
        case .polish: return "Na godz."
        case .english: return "Hourly avg"
        default: return "Hourly avg"
        }
    }

    private var localizedInsightTooltipPeriod: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "时段"
        case .japanese: return "時間帯"
        case .polish: return "Pora"
        case .english: return "Period"
        default: return "Period"
        }
    }

    private var localizedInsightTooltipPeakHour: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "峰值小时"
        case .japanese: return "ピーク時間"
        case .polish: return "Szczyt"
        case .english: return "Peak hour"
        default: return "Peak hour"
        }
    }

    private var localizedInsightHourlyCallsTitle: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "24 小时调用柱状图"
        case .japanese: return "24時間の利用バー"
        case .polish: return "Godzinowy wykres uzycia"
        case .english: return "24-hour usage bars"
        default: return "24-hour usage bars"
        }
    }

    private var localizedInsightNoUsageTime: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "这个窗口内还没有可展示的调用时间。"
        case .japanese: return "この期間には表示できる利用時間がありません。"
        case .polish: return "Brak godzin użycia w tym zakresie."
        case .english: return "No usage time is available for this window."
        default: return "No usage time is available for this window."
        }
    }

    private var localizedInsightMorning: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "早上"
        case .japanese: return "朝"
        case .polish: return "Rano"
        case .english: return "Morning"
        default: return "Morning"
        }
    }

    private var localizedInsightAfternoon: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "下午"
        case .japanese: return "午後"
        case .polish: return "Popoludnie"
        case .english: return "Afternoon"
        default: return "Afternoon"
        }
    }

    private var localizedInsightEvening: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "晚上"
        case .japanese: return "夜"
        case .polish: return "Wieczor"
        case .english: return "Evening"
        default: return "Evening"
        }
    }

    private var localizedInsightLateNight: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "深夜"
        case .japanese: return "深夜"
        case .polish: return "Noc"
        case .english: return "Late night"
        default: return "Late night"
        }
    }

    private func localizedInsightDayPart(for hour: Int) -> String {
        switch hour {
        case 6..<12: return localizedInsightMorning
        case 12..<18: return localizedInsightAfternoon
        case 18..<24: return localizedInsightEvening
        default: return localizedInsightLateNight
        }
    }

    private func localizedInsightPeakSummary(range: String, hour: Int, turns: Int) -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "高峰在\(range)，\(String(format: "%02d:00", hour)) 附近最多（\(turns) turns）。"
        case .japanese:
            return "ピークは\(range)、\(String(format: "%02d:00", hour)) 頃が最多（\(turns) turns）。"
        case .polish:
            return "Szczyt: \(range), okolo \(String(format: "%02d:00", hour)) (\(turns) turns)."
        case .english:
            return "Peak usage is in the \(range.lowercased()), highest around \(String(format: "%02d:00", hour)) (\(turns) turns)."
        default:
            return "Peak usage is in the \(range.lowercased()), highest around \(String(format: "%02d:00", hour)) (\(turns) turns)."
        }
    }

    private func drawInsightRecommendations(_ row: RepoInsight, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        let recommendations = insightRecommendations(for: row)
        guard let primary = recommendations.first else { return }
        drawText(copy.recommendationsTitle, rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: .white)
        let card = NSRect(x: rect.minX, y: rect.minY + 22, width: rect.width, height: 38)
        primary.2.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
        primary.2.withAlphaComponent(0.34).setStroke()
        let outline = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        outline.lineWidth = 1
        outline.stroke()
        drawTruncatedText(primary.0, rect: NSRect(x: card.minX + 12, y: card.minY + 4, width: card.width - 24, height: 14), font: .systemFont(ofSize: 11, weight: .bold), color: primary.2)
        drawTruncatedText(primary.1, rect: NSRect(x: card.minX + 12, y: card.minY + 20, width: card.width - 24, height: 14), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.60))
        let secondary = recommendations.dropFirst().map(\.0).joined(separator: "  ·  ")
        if !secondary.isEmpty {
            drawTruncatedText(secondary, rect: NSRect(x: rect.minX + 2, y: card.maxY + 7, width: rect.width - 4, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
        }
    }

    private func drawInsightHeatmap(row: RepoInsight, rect: NSRect) {
        let copy = AppLanguage.current.insightCopy
        drawPanel(rect)
        drawText(copy.heatmapTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        let days = recentInsightDays(count: 90)
        let dayMap = Dictionary(uniqueKeysWithValues: row.days.map { ($0.day, $0) })
        let cols = 30
        let rows = 3
        let gap: CGFloat = 4
        let legendW: CGFloat = min(170, rect.width * 0.22)
        let gridW = rect.width - 32 - legendW - 18
        let cell = min(CGFloat(16), (gridW - CGFloat(cols - 1) * gap) / CGFloat(cols))
        let startX = rect.minX + 16
        let startY = rect.minY + 48
        for (index, day) in days.enumerated() {
            let col = index / rows
            let rowIndex = index % rows
            let cellRect = NSRect(x: startX + CGFloat(col) * (cell + gap), y: startY + CGFloat(rowIndex) * (cell + gap), width: cell, height: cell)
            insightDayColor(dayMap[day]).setFill()
            NSBezierPath(roundedRect: cellRect, xRadius: 3, yRadius: 3).fill()
        }
        let legendX = startX + CGFloat(cols) * (cell + gap) + 18
        let legends: [(String, NSColor)] = [
            (copy.normalLegend, accentTeal),
            (copy.highLegend, accentAmber),
            (copy.veryHighLegend, accentRose),
            (copy.noActivityLegend, NSColor.white.withAlphaComponent(0.10))
        ]
        for (index, legend) in legends.enumerated() {
            let y = rect.minY + 44 + CGFloat(index) * 22
            legend.1.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: y + 4, width: 8, height: 8)).fill()
            drawText(legend.0, rect: NSRect(x: legendX + 14, y: y, width: rect.maxX - legendX - 24, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
        }
    }

    private func insightDayColor(_ day: RepoInsightDay?) -> NSColor {
        guard let day, day.conversations > 0 else {
            return NSColor.white.withAlphaComponent(0.08)
        }
        let rate = Double(day.compressions) / Double(max(1, day.conversations))
        if rate > 1 {
            return accentRose.withAlphaComponent(0.82)
        }
        if rate > 0.3 {
            return accentAmber.withAlphaComponent(0.82)
        }
        return accentTeal.withAlphaComponent(0.72)
    }

    private func insightRecommendations(for row: RepoInsight) -> [(String, String, NSColor)] {
        let colors: [NSColor]
        switch row.risk {
        case .frequentCompression:
            colors = [accentRose, accentAmber, accentBlue]
        case .longRunning:
            colors = [accentAmber, accentBlue, accentTeal]
        case .wellSplit, .healthy:
            colors = [accentTeal, accentBlue, accentAmber]
        }
        return AppLanguage.current.insightCopy.recommendations(row.risk).enumerated().map { index, item in
            (item.title, item.body, colors[min(index, colors.count - 1)])
        }
    }

    private func drawInsightRiskPill(_ risk: RepoInsightRisk, rect: NSRect) {
        let label = AppLanguage.current.insightCopy.riskLabel(risk)
        let color = insightRiskColor(risk)
        color.withAlphaComponent(0.42).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        drawCentered(label, rect: rect.insetBy(dx: 4, dy: 0), font: .systemFont(ofSize: 10, weight: .bold), color: color.withAlphaComponent(0.95))
    }

    private func insightRiskColor(_ risk: RepoInsightRisk) -> NSColor {
        switch risk {
        case .frequentCompression: return accentRose
        case .longRunning: return accentAmber
        case .wellSplit: return accentTeal
        case .healthy: return NSColor.systemGreen
        }
    }

    private var localizedInsightFilterAll: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "全部"
        case .japanese: return "すべて"
        case .polish: return "Wszystkie"
        default: return "All"
        }
    }

    private var localizedInsightGoodStatus: String {
        switch AppLanguage.current {
        case .chinese: return "状态良好"
        case .traditionalChinese: return "狀態良好"
        case .japanese: return "良好"
        case .polish: return "W normie"
        default: return "Doing fine"
        }
    }

    private var localizedInsightAttentionGroup: String {
        switch AppLanguage.current {
        case .chinese: return "需要关注"
        case .traditionalChinese: return "需要關注"
        case .japanese: return "要注意"
        case .polish: return "Wymaga uwagi"
        default: return "Needs attention"
        }
    }

    private func insightDiagnosisText(for row: RepoInsight) -> String {
        let days = selectedInsightWindowDays
        let avg = String(format: "%.2f", row.averageCompressionsPerConversation)
        let percent = Int(round(row.compressionConversationRate * 100))
        switch AppLanguage.current {
        case .chinese:
            switch row.risk {
            case .frequentCompression:
                return "\(days) 天内 \(row.conversations) 个对话共压缩 \(row.compressions) 次，平均 \(avg) 次/对话，明显偏高；\(percent)% 的对话发生过压缩，最长 \(row.longestTurns) turns。"
            case .longRunning:
                return "对话偏长：最长 \(row.longestTurns) turns，平均压缩 \(avg) 次/对话；建议阶段完成后开新窗口，避免触发压缩。"
            case .wellSplit:
                return "切分习惯良好：对话普遍较短，平均压缩 \(avg) 次/对话，上下文保持干净。"
            case .healthy:
                return "\(days) 天内 \(row.conversations) 个对话，平均压缩 \(avg) 次/对话，处于健康区间，保持当前节奏即可。"
            }
        case .traditionalChinese:
            switch row.risk {
            case .frequentCompression:
                return "\(days) 天內 \(row.conversations) 個對話共壓縮 \(row.compressions) 次，平均 \(avg) 次/對話，明顯偏高；\(percent)% 的對話發生過壓縮，最長 \(row.longestTurns) turns。"
            case .longRunning:
                return "對話偏長：最長 \(row.longestTurns) turns，平均壓縮 \(avg) 次/對話；建議階段完成後開新視窗，避免觸發壓縮。"
            case .wellSplit:
                return "切分習慣良好：對話普遍較短，平均壓縮 \(avg) 次/對話，上下文保持乾淨。"
            case .healthy:
                return "\(days) 天內 \(row.conversations) 個對話，平均壓縮 \(avg) 次/對話，處於健康區間，保持目前節奏即可。"
            }
        case .japanese:
            switch row.risk {
            case .frequentCompression:
                return "直近\(days)日で\(row.conversations)会話・圧縮\(row.compressions)回（平均\(avg)回/会話）と高水準。\(percent)%の会話で圧縮が発生、最長\(row.longestTurns) turns。"
            case .longRunning:
                return "会話が長め：最長\(row.longestTurns) turns、平均圧縮\(avg)回/会話。区切りごとに新しいウィンドウを開くのがおすすめ。"
            case .wellSplit:
                return "分割が良好：会話は短めで平均圧縮\(avg)回/会話。コンテキストはきれいに保たれています。"
            case .healthy:
                return "直近\(days)日で\(row.conversations)会話、平均圧縮\(avg)回/会話。健全な範囲です。"
            }
        default:
            switch row.risk {
            case .frequentCompression:
                return "\(row.conversations) chats compacted \(row.compressions) times in \(days) days — \(avg) per chat, well above healthy; \(percent)% of chats hit compaction, longest \(row.longestTurns) turns."
            case .longRunning:
                return "Chats run long: up to \(row.longestTurns) turns, \(avg) compactions per chat. Start a fresh window after each milestone."
            case .wellSplit:
                return "Well split: chats stay short with \(avg) compactions per chat, keeping context clean."
            case .healthy:
                return "\(row.conversations) chats in \(days) days with \(avg) compactions per chat — comfortably in the healthy range."
            }
        }
    }

    private func recentInsightDays(count: Int) -> [String] {
        let formatter = dayFormatter()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { formatter.string(from: $0) }
        }
    }

    private func drawDiagnosticsPage(snapshot: DetailsSnapshot, content: NSRect) {
        let sourceRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 268)
        drawPanel(sourceRect)
        drawText(t(.sourceHealth), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawDiagnosticRows(sourceDiagnostics(snapshot: snapshot), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 48, width: sourceRect.width - 32, height: sourceRect.height - 64))

        let apiRect = NSRect(x: content.minX, y: sourceRect.maxY + 16, width: content.width, height: 124)
        drawPanel(apiRect)
        drawText(t(.externalAPICost), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.externalAPICostHint), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 40, width: apiRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        drawDiagnosticRows(apiDiagnostics(), rect: NSRect(x: apiRect.minX + 16, y: apiRect.minY + 66, width: apiRect.width - 32, height: 44))

        let toolsRect = NSRect(x: content.minX, y: apiRect.maxY + 16, width: content.width, height: 168)
        drawPanel(toolsRect)
        drawText(t(.otherTools), rect: NSRect(x: toolsRect.minX + 16, y: toolsRect.minY + 14, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawDiagnosticRows(otherToolDiagnostics(), rect: NSRect(x: toolsRect.minX + 16, y: toolsRect.minY + 48, width: toolsRect.width - 32, height: toolsRect.height - 64))
    }

    private func drawDiagnosticRows(_ rows: [(String, String, NSColor)], rect: NSRect) {
        let rowHeight = min(CGFloat(28), rect.height / CGFloat(max(rows.count, 1)))
        for (index, row) in rows.enumerated() {
            let y = rect.minY + CGFloat(index) * rowHeight
            guard y + min(22, rowHeight) <= rect.maxY + 0.5 else { break }
            drawText(row.0, rect: NSRect(x: rect.minX, y: y + 2, width: min(220, rect.width * 0.34), height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.58))
            let dot = NSRect(x: rect.maxX - 10, y: y + max(5, (rowHeight - 8) / 2), width: 8, height: 8)
            row.2.setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawRight(row.1, rect: NSRect(x: rect.minX + rect.width * 0.34, y: y + 1, width: rect.width * 0.64 - 18, height: 18), color: .white, font: .systemFont(ofSize: 12, weight: .semibold))
        }
    }

    private func sourceDiagnostics(snapshot: DetailsSnapshot) -> [(String, String, NSColor)] {
        selectedDetailsSource == .claude ? claudeSourceDiagnostics(snapshot: snapshot) : codexSourceDiagnostics(snapshot: snapshot)
    }

    private func codexSourceDiagnostics(snapshot: DetailsSnapshot) -> [(String, String, NSColor)] {
        let cliPath = LiveRateLimitReader.codexExecutablePath()
        let authURL = AppSettings.defaultCodexHomeURL.appendingPathComponent("auth.json")
        let liveText = snapshot.liveLimits.isEmpty
            ? t(.liveLimitUnavailable)
            : "\(snapshot.liveLimits.count) windows"
        let serviceText = snapshot.serviceStatus.map { localizedCodexStatus($0.overallStatus) } ?? t(.codexStatusUnavailable)
        let serviceColor = snapshot.serviceStatus.map { codexStatusColor($0.overallStatus) } ?? accentAmber
        let incidentText = snapshot.serviceStatus?.activeIncident?.name ?? t(.codexNoActiveIncident)
        let incidentColor = snapshot.serviceStatus?.activeIncident.map { codexStatusColor($0.status) } ?? NSColor.white.withAlphaComponent(0.58)
        let profileText: String
        let profileColor: NSColor
        if !AppSettings.profileAPITotalsEnabled {
            profileText = t(.disabled)
            profileColor = accentAmber
        } else if let accountUsage = snapshot.accountUsage, accountUsage.hasData {
            profileText = accountUsage.summary.lifetimeTokens.map { compact($0) } ?? "\(accountUsage.dailyUsageBuckets.count) days"
            profileColor = accentTeal
        } else {
            profileText = t(.liveLimitUnavailable)
            profileColor = accentRose
        }
        let rollouts = AppSettings.logFolderURLs.reduce(0) { $0 + rolloutCount(in: $1, modifiedWithinDays: 14) }
        return [
            ("Codex CLI", cliPath.map(shortenedPath) ?? t(.fileMissing), cliPath == nil ? accentRose : accentTeal),
            ("auth.json", FileManager.default.fileExists(atPath: authURL.path) ? t(.filePresent) : t(.fileMissing), FileManager.default.fileExists(atPath: authURL.path) ? accentTeal : accentAmber),
            (t(.liveQuota), liveText, snapshot.liveLimits.isEmpty ? accentRose : accentTeal),
            (t(.codexStatus), serviceText, serviceColor),
            (t(.codexIncident), incidentText, incidentColor),
            (t(.profileAPITotals), profileText, profileColor),
            (t(.modelLimit), "\(AppSettings.modelLimitName) / \(AppSettings.modelLimitID)", accentTeal),
            (t(.logFolder), "\(AppSettings.logFolderURLs.count) roots", AppSettings.logFolderURLs.isEmpty ? accentRose : accentTeal),
            (t(.recentRollouts), "\(rollouts) files / 14d", rollouts > 0 ? accentTeal : accentAmber),
            (t(.quotaWarnings), AppSettings.quotaWarningsEnabled ? t(.enabled) : t(.disabled), AppSettings.quotaWarningsEnabled ? accentTeal : accentAmber)
        ]
    }

    private func claudeSourceDiagnostics(snapshot: DetailsSnapshot) -> [(String, String, NSColor)] {
        let claudeLogs = AppSettings.claudeLogFolderURLs.reduce(0) { $0 + jsonlCount(in: $1, modifiedWithinDays: 14) }
        let claudeRootExists = AppSettings.claudeLogFolderURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
        let claudeStatuslineStore = ClaudeStatuslineStore()
        let claudeStatusline = claudeStatuslineStore.read()
        let claudeStatuslineText: String
        let claudeStatuslineColor: NSColor
        if let claudeStatusline, claudeStatusline.liveRateLimit != nil {
            let fiveHour = claudeStatusline.fiveHour.map { "\(Int(round($0.usedPercent)))% 5h" } ?? "5h --"
            let sevenDay = claudeStatusline.sevenDay.map { "\(Int(round($0.usedPercent)))% 7d" } ?? "7d --"
            claudeStatuslineText = "\(fiveHour) / \(sevenDay)"
            claudeStatuslineColor = accentTeal
        } else {
            claudeStatuslineText = "not captured: \(shortenedPath(claudeStatuslineStore.path))"
            claudeStatuslineColor = accentAmber
        }
        return [
            (t(.claudeLogs), AppSettings.claudeLogFolderDisplayPath, claudeRootExists ? accentTeal : accentAmber),
            (t(.recentRollouts), "\(claudeLogs) files / 14d", claudeLogs > 0 ? accentTeal : accentAmber),
            ("Claude statusline", claudeStatuslineText, claudeStatuslineColor),
            (t(.claudeActiveRefresh), AppSettings.claudeActiveQuotaRefreshEnabled ? t(.enabled) : t(.disabled), AppSettings.claudeActiveQuotaRefreshEnabled ? accentTeal : accentAmber),
            (t(.cacheHit), String(format: "%.0f%%", snapshot.all.usage.cachePercent), accentTeal),
            (t(.models), "\(snapshot.all.modelBreakdown.count)", accentTeal),
            (t(.sessions), "\(snapshot.all.sessions)", accentTeal),
            (t(.turns), "\(snapshot.all.turns)", accentTeal)
        ]
    }

    private func apiDiagnostics() -> [(String, String, NSColor)] {
        let url = AppSettings.externalAPICostURL
        if let snapshot = ExternalAPICostStore.read(url: url), snapshot.hasData {
            let tokenPart = snapshot.totalTokens > 0 ? " · \(compact(snapshot.totalTokens)) tokens" : ""
            return [
                ("api-usage.json", "\(displayAPIMoney(snapshot.usdValue))\(tokenPart)", accentTeal),
                ("Path", shortenedPath(url.path), NSColor.white.withAlphaComponent(0.62))
            ]
        }
        return [
            ("api-usage.json", t(.fileMissing), accentAmber),
            ("Path", shortenedPath(url.path), NSColor.white.withAlphaComponent(0.62))
        ]
    }

    private func otherToolDiagnostics() -> [(String, String, NSColor)] {
        let home = NSHomeDirectory()
        let probes: [(String, String, Bool)] = [
            ("Codex", AppSettings.logFolderDisplayPath, true),
            ("Claude Code", "\(home)/.claude/projects", true),
            ("Cursor", "\(home)/Library/Application Support/Cursor", false),
            ("OpenCode", "\(home)/.local/share/opencode", false),
            ("Gemini CLI", "\(home)/.gemini", false)
        ]
        return probes.map { name, path, tracked in
            let exists = FileManager.default.fileExists(atPath: path)
            let value: String
            if tracked {
                value = t(.tracked)
            } else if exists {
                value = t(.detectedNotTracked)
            } else {
                value = t(.fileMissing)
            }
            let color: NSColor = tracked ? accentTeal : (exists ? accentAmber : NSColor.white.withAlphaComponent(0.36))
            return (name, value, color)
        }
    }

    private func rolloutCount(in root: URL, modifiedWithinDays days: Int) -> Int {
        let start = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix("rollout-"), url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if (values?.contentModificationDate ?? .distantPast) >= start {
                count += 1
            }
        }
        return count
    }

    private func jsonlCount(in root: URL, modifiedWithinDays days: Int) -> Int {
        let start = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if (values?.contentModificationDate ?? .distantPast) >= start {
                count += 1
            }
        }
        return count
    }

    private func shortenedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path.count > 72 ? "..." + path.suffix(69) : path
    }

    private func drawCalendarPage(snapshot: DetailsSnapshot, content: NSRect) {
        let report = calendarReport(for: snapshot)
        let useProfilePanel = usesProfileAPIReport(for: snapshot)
            && !profileSelectedDayUsesLocalFallback(snapshot: snapshot, report: report)
        let title = useProfilePanel
            ? "\(t(.tokenActivity)) · \(t(.profileAPISource))"
            : t(.tokenActivity)
        let preferredGridHeight = contributionGridPreferredHeight(report: report, width: content.width, compact: false)
        let gridHeight = min(preferredGridHeight, max(224, content.height * 0.36))
        let gridRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: gridHeight)
        drawContributionGrid(report: report, rect: gridRect, title: title, compact: false)

        let weekSummary = selectedCalendarWeekSummary()
        let available = max(248, content.maxY - gridRect.maxY - 16)
        let preferredHeight = weekSummary != nil
            ? selectedWeekPanelPreferredHeight(contentWidth: content.width)
            : selectedDayPanelPreferredHeight(contentWidth: content.width)
        let detailRect = NSRect(x: content.minX, y: gridRect.maxY + 16, width: content.width, height: min(preferredHeight, available))
        if let weekSummary {
            drawSelectedWeekPanel(snapshot: snapshot, report: report, summary: weekSummary, rect: detailRect)
        } else if useProfilePanel {
            drawProfileSelectedDayPanel(snapshot: snapshot, report: report, rect: detailRect)
        } else {
            drawSelectedDayPanel(snapshot: snapshot, rect: detailRect)
        }
    }

    private func reportCostSignature(_ report: TokenReport?) -> String {
        guard let report else { return "none" }
        let first = report.byDay.first
        let last = report.byDay.last
        return [
            String(format: "%.3f", report.scannedAt.timeIntervalSince1970),
            "\(report.events)",
            "\(report.turns)",
            "\(report.usage.total)",
            "\(report.usage.input)",
            "\(report.usage.cachedInput)",
            "\(report.usage.output)",
            "\(report.modelBreakdown.count)",
            "\(report.byDay.count)",
            first?.day ?? "",
            "\(first?.usage.total ?? 0)",
            last?.day ?? "",
            "\(last?.usage.total ?? 0)"
        ].joined(separator: "|")
    }

    private func cachedAvailableCostYears(from report: TokenReport?, source: QuotaViewOption) -> [Int] {
        let key = [
            reportCostSignature(report),
            source.rawValue,
            AppSettings.paymentStartDay(for: source) ?? "",
            todayKey()
        ].joined(separator: "|")
        if costYearOptionsCacheKey == key {
            return costYearOptionsCache
        }
        let years = availableCostYears(from: report, paymentStartDay: AppSettings.paymentStartDay(for: source))
        costYearOptionsCacheKey = key
        costYearOptionsCache = years
        return years
    }

    private func costPageDataKey(snapshot: DetailsSnapshot, limit: LiveRateLimit?, year: Int) -> String {
        let weekly = limit?.secondary
        let report = sourceReport(for: snapshot)
        let referenceReport = sourceCostReferenceReport(for: snapshot)
        let costSource = selectedDetailsSource
        return [
            costSource.rawValue,
            reportCostSignature(report),
            "\(year)",
            AppLanguage.current.rawValue,
            String(format: "%.4f", AppSettings.monthlyPlanCost(for: costSource)),
            AppSettings.paymentStartDay(for: costSource) ?? "",
            AppSettings.paymentCurrency(for: costSource).rawValue,
            AppSettings.displayCurrency(for: costSource).rawValue,
            AppSettings.showHistoricalEmptyWeeks ? "1" : "0",
            String(format: "%.4f", weekly?.usedPercent ?? -1),
            String(format: "%.4f", weekly?.remainingPercent ?? -1),
            "\(weekly?.windowMinutes ?? 0)",
            "\(referenceReport?.usage.total ?? -1)",
            String(format: "%.3f", referenceReport?.scannedAt.timeIntervalSince1970 ?? -1),
            todayKey()
        ].joined(separator: "|")
    }

    private func costPageData(for snapshot: DetailsSnapshot, limit: LiveRateLimit?, year: Int) -> CostPageData {
        let key = costPageDataKey(snapshot: snapshot, limit: limit, year: year)
        if let cached = costPageDataCache, cached.key == key {
            return cached
        }
        let report = sourceReport(for: snapshot)
        let referenceReport = sourceCostReferenceReport(for: snapshot)
        let costSource = selectedDetailsSource
        let monthlyCost = AppSettings.monthlyPlanCost(for: costSource)
        let paymentStartDay = AppSettings.paymentStartDay(for: costSource)
        let data = CostPageData(
            key: key,
            estimate: planCostEstimate(report: report, selectedDay: nil, limit: limit, quotaReferenceReport: referenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay),
            apiEstimate: APICostEstimator.estimate(report: report),
            weeklyRows: weeklySpendRows(report: report, limit: limit, year: year, quotaReferenceReport: referenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay),
            monthlyRows: monthlySpendRows(report: report, limit: limit, year: year, quotaReferenceReport: referenceReport, monthlyCost: monthlyCost, paymentStartDay: paymentStartDay)
        )
        costPageDataCache = data
        return data
    }

    private func drawCostOverviewPanel(estimate: PlanCostEstimate?, apiEstimate: APICostEstimate, source: QuotaViewOption, rect: NSRect) {
        drawPanel(rect)
        let externalAPI = ExternalAPICostStore.read()
        guard let estimate else {
            if apiEstimate.hasUsage {
                let coverage = String(format: "%.0f%%", apiEstimate.coveragePercent)
                drawText(t(.apiEquivalent), rect: NSRect(x: rect.minX + 18, y: rect.minY + 20, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
                drawText(displayAPIMoney(apiEstimate.usdValue, source: source), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: rect.width - 36, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: accentTeal)
                drawText("\(coverage) \(t(.priced)) · \(t(.apiEquivalentHint))", rect: NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))
                let unavailableY: CGFloat = externalAPI?.hasData == true ? 138 : 124
                if let externalAPI, externalAPI.hasData {
                    drawCostOverviewRow(title: t(.externalAPICost), value: displayAPIMoney(externalAPI.usdValue, source: source), color: accentAmber, rect: NSRect(x: rect.minX + 18, y: rect.minY + 116, width: rect.width - 36, height: 20), info: .externalAPI)
                }
                drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + unavailableY, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
                return
            }
            if let externalAPI, externalAPI.hasData {
                drawText(t(.externalAPICost), rect: NSRect(x: rect.minX + 18, y: rect.minY + 20, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
                drawText(displayAPIMoney(externalAPI.usdValue, source: source), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: rect.width - 36, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: accentAmber)
                drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))
                return
            }
            drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX + 16, y: rect.minY + 54, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
            return
        }

        let inset: CGFloat = 18
        let dividerX = rect.minX + max(282, rect.width * 0.48)
        let leftRect = NSRect(x: rect.minX + inset, y: rect.minY + 16, width: dividerX - rect.minX - inset * 2, height: rect.height - 32)
        let rightRect = NSRect(x: dividerX + 18, y: rect.minY + 16, width: rect.maxX - dividerX - 34, height: rect.height - 32)

        borderColor.setStroke()
        NSBezierPath(rect: NSRect(x: dividerX, y: rect.minY + 18, width: 1, height: rect.height - 36)).stroke()

        let usageRate = estimate.weeklyBudget > 0 ? estimate.weeklyUsedValue / estimate.weeklyBudget : 0
        let clampedRate = min(1, max(0, usageRate))
        let usedColor = usageRate > 1 ? accentAmber : costUsedColor

        drawText(t(.weeklyUsedValue), rect: NSRect(x: leftRect.minX, y: leftRect.minY, width: leftRect.width, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
        drawText(displayMoney(estimate.weeklyUsedValue, source: source), rect: NSRect(x: leftRect.minX, y: leftRect.minY + 26, width: leftRect.width - 92, height: 34), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: usedColor)
        drawRight(String(format: "%.0f%%", usageRate * 100), rect: NSRect(x: leftRect.maxX - 86, y: leftRect.minY + 31, width: 86, height: 24), color: NSColor.white.withAlphaComponent(0.82), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold))

        let progressRect = NSRect(x: leftRect.minX, y: leftRect.minY + 74, width: leftRect.width, height: 10)
        costRemainingMutedColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: progressRect, xRadius: 5, yRadius: 5).fill()
        usedColor.setFill()
        let usedProgressWidth = clampedRate > 0 ? max(6, progressRect.width * CGFloat(clampedRate)) : 0
        if usedProgressWidth > 0 {
            NSBezierPath(roundedRect: NSRect(x: progressRect.minX, y: progressRect.minY, width: usedProgressWidth, height: progressRect.height), xRadius: 5, yRadius: 5).fill()
        }

        let budgetLine = "\(t(.weeklyUnusedValue)) \(displayMoney(estimate.weeklyUnusedValue, source: source))  /  \(t(.weeklyBudget)) \(displayMoney(estimate.weeklyBudget, source: source))"
        drawText(budgetLine, rect: NSRect(x: leftRect.minX, y: leftRect.minY + 96, width: leftRect.width, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.52))

        let planLine = "\(t(.paymentMonthly)) \(paymentMoney(estimate.monthlyCost, source: source))  ·  \(t(.displayEquivalent)) \(displayMoney(estimate.monthlyCost, source: source))"
        drawText(planLine, rect: NSRect(x: rightRect.minX, y: rightRect.minY, width: rightRect.width, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
        let apiTitle = apiEstimate.hasUsage && apiEstimate.coveragePercent < 99.5
            ? "\(t(.apiEquivalent)) \(String(format: "%.0f%%", apiEstimate.coveragePercent))"
            : t(.apiEquivalent)
        var summaryRows: [(String, String, NSColor, CostOverviewInfo)] = [
            (t(.usageRate), String(format: "%.0f%%", usageRate * 100), usedColor, .usageRate),
            (t(.totalSpendValue), displayMoney(estimate.totalSpentValue, source: source), accentAmber, .totalSpend),
            (apiTitle, displayAPIMoney(apiEstimate.usdValue, source: source), accentTeal, .apiEquivalent)
        ]
        if let externalAPI, externalAPI.hasData {
            summaryRows.append((t(.externalAPICost), displayAPIMoney(externalAPI.usdValue, source: source), accentAmber, .externalAPI))
        }
        summaryRows.append((t(.totalWasteValue), displayMoney(estimate.totalWastedValue, source: source), accentRose.withAlphaComponent(0.92), .totalWaste))
        let rowSpacing: CGFloat = summaryRows.count > 4 ? 22 : 26
        for (index, row) in summaryRows.enumerated() {
            drawCostOverviewRow(
                title: row.0,
                value: row.1,
                color: row.2,
                rect: NSRect(x: rightRect.minX, y: rightRect.minY + 28 + CGFloat(index) * rowSpacing, width: rightRect.width, height: 20),
                info: row.3
            )
        }
    }

    private func drawCostOverviewRow(title: String, value: String, color: NSColor, rect: NSRect, info: CostOverviewInfo? = nil) {
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let titleRect = NSRect(x: rect.minX, y: rect.minY + 2, width: max(90, rect.width * 0.34), height: 16)
        drawText(title, rect: titleRect, font: titleFont, color: NSColor.white.withAlphaComponent(0.48))
        if let info {
            let titleWidth = min(titleRect.width - 16, measuredTextWidth(title, font: titleFont))
            let iconRect = NSRect(x: titleRect.minX + titleWidth + 5, y: rect.minY + 1, width: 16, height: 16)
            costOverviewInfoRects[info] = iconRect
            drawInfoMark(rect: iconRect, highlighted: hoveredCostOverviewInfo == info)
        }
        drawRight(value, rect: NSRect(x: rect.minX + rect.width * 0.34, y: rect.minY, width: rect.width * 0.66, height: 20), color: color, font: .monospacedDigitSystemFont(ofSize: 15, weight: .bold))
    }

    private func drawToggle(rect: NSRect, isOn: Bool) {
        let trackColor = isOn ? accentTeal.withAlphaComponent(0.72) : NSColor.white.withAlphaComponent(0.13)
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2).stroke()

        let knobSize = rect.height - 4
        let knobX = isOn ? rect.maxX - knobSize - 2 : rect.minX + 2
        let knobRect = NSRect(x: knobX, y: rect.minY + 2, width: knobSize, height: knobSize)
        NSColor.white.withAlphaComponent(0.88).setFill()
        NSBezierPath(ovalIn: knobRect).fill()
    }

    private struct CostHistoryHeaderLayout {
        let hintRect: NSRect
        let emptyWeeksLabelRect: NSRect
        let emptyWeeksSwitchRect: NSRect
        let yearRect: NSRect
        let ringsRect: NSRect
    }

    private func costHistoryHeaderLayout(chartRect: NSRect) -> CostHistoryHeaderLayout {
        let inset: CGFloat = 16
        let rowGap: CGFloat = 12
        let labelSwitchGap: CGFloat = 6
        let switchWidth: CGFloat = 40
        let switchHeight: CGFloat = 22
        let yearWidth: CGFloat = 152
        let toggleY = chartRect.minY + 12
        let yearY = chartRect.minY + 42
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let labelWidth = ceil(measuredTextWidth(t(.showPastEmptyWeeks), font: labelFont)) + 2

        let yearRect = NSRect(
            x: chartRect.maxX - inset - yearWidth,
            y: yearY,
            width: yearWidth,
            height: 28
        )
        let groupWidth = labelWidth + labelSwitchGap + switchWidth
        let groupX = max(chartRect.minX + inset, chartRect.maxX - inset - groupWidth)
        let labelRect = NSRect(
            x: groupX,
            y: toggleY + 4,
            width: labelWidth,
            height: 14
        )
        let switchRect = NSRect(
            x: labelRect.maxX + labelSwitchGap,
            y: toggleY,
            width: switchWidth,
            height: switchHeight
        )
        let maxHintWidth = max(0, yearRect.minX - chartRect.minX - inset - rowGap)
        let hintWidth = min(430, maxHintWidth)
        let hintRect = NSRect(
            x: chartRect.minX + inset,
            y: chartRect.minY + 36,
            width: hintWidth,
            height: 16
        )
        let ringsRect = NSRect(
            x: chartRect.minX + inset,
            y: chartRect.minY + 84,
            width: chartRect.width - inset * 2,
            height: chartRect.height - 102
        )
        return CostHistoryHeaderLayout(
            hintRect: hintRect,
            emptyWeeksLabelRect: labelRect,
            emptyWeeksSwitchRect: switchRect,
            yearRect: yearRect,
            ringsRect: ringsRect
        )
    }

    private enum QuotaCycleRowKind {
        case current
        case earlyRefresh
        case scheduledReset
    }

    private struct QuotaCycleRowModel {
        let shortRange: String
        let fullRange: String
        let kind: QuotaCycleRowKind
        let badgeText: String
        let kindTimeText: String
        let durationText: String
        let percent: Double
        let isCurrent: Bool
        let isPartial: Bool
        var tokenText: String?
        var apiCostText: String?
        var moneyValue: Double?
        var usedMoneyValue: Double?

        var isEarlyRefresh: Bool { kind == .earlyRefresh }
        var isCapped: Bool { percent >= 97 }
        var wastedMoneyValue: Double? {
            guard let moneyValue, let usedMoneyValue, !isCurrent else { return nil }
            return max(0, moneyValue - usedMoneyValue)
        }
    }

    private struct QuotaCycleMoneySummary {
        let cycleCount: Int
        let totalValue: Double
        let usedValue: Double
        let wastedValue: Double
        let currentValue: Double?
        let currentUsedValue: Double?
        let currentRemainTokensText: String?
        let monthlyCost: Double
        let weeklyBudget: Double
    }

    private struct QuotaCycleBarModel {
        var percent: Double
        var resetAt: Date
        var windowMinutes: Int
        var isCurrent: Bool
        var isEarlyRefresh: Bool
        var tokenText: String?
    }

    private struct QuotaCyclePageModel {
        let limit: LiveRateLimit?
        let weeklyRows: [QuotaCycleRowModel]
        let fiveHourBars: [QuotaCycleBarModel]
        let cappedCount: Int
        let hasBackfilledRows: Bool
        let hasEarlyRefreshRows: Bool
        let moneySummary: QuotaCycleMoneySummary?
        let currentDailyUsage: [(day: String, total: Int64)]

        var hasFootnote: Bool { hasBackfilledRows || hasEarlyRefreshRows }
    }

    private static let cycleISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let cycleRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let resetCreditExpiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let resetCreditFullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = appTimeZone()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let cycleDayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    private static let cycleTimeLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let cycleClockLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var quotaCycleSource: QuotaViewOption {
        selectedDetailsSource == .claude ? .claude : .codex
    }

    private func quotaCyclePageModel(for snapshot: DetailsSnapshot) -> QuotaCyclePageModel {
        let limitID = quotaCycleSource.liveLimitID
        let limit = snapshot.liveLimits.first { $0.id == limitID }
        let iso = Self.cycleISOFormatter

        struct WeeklyCycleInfo {
            var start: Date?
            var end: Date
            var percent: Double
            var isBackfilled: Bool
            var isCurrent: Bool
            var earlyRefreshAt: Date?
        }

        // Local-log usage attributed to each cycle, for tooltips: day-level
        // sums for weekly cycles, hour-level sums for 5h cycles.
        let usageReport = quotaCycleSource == .claude ? snapshot.claude : snapshot.codex
        let moneySource = quotaCycleSource
        let monthlyCost = AppSettings.monthlyPlanCost(for: moneySource)
        let weeklyBudget = monthlyCost > 0 ? monthlyCost * 12 / 52 : 0
        let dayParser = dayFormatter()
        struct CycleDayStat {
            let midpoint: Date
            let total: Int64
            let usd: Double
            let priced: Bool
        }
        let dayStats: [CycleDayStat] = usageReport.byDay.compactMap { day in
            guard day.usage.total > 0, let date = dayParser.date(from: day.day) else { return nil }
            let estimate = APICostEstimator.estimate(day: day)
            return CycleDayStat(midpoint: date.addingTimeInterval(43_200), total: day.usage.total, usd: estimate.usdValue, priced: estimate.hasPricedUsage)
        }
        func cycleUsageStats(start: Date?, end: Date) -> (tokenText: String?, apiCostText: String?) {
            guard let start else { return (nil, nil) }
            var total: Int64 = 0
            var usd = 0.0
            var hasPriced = false
            for stat in dayStats where stat.midpoint >= start && stat.midpoint < end {
                total += stat.total
                if stat.priced {
                    usd += stat.usd
                    hasPriced = true
                }
            }
            guard total > 0 else { return (nil, nil) }
            return (compact(total), hasPriced ? compactDisplayAPIMoney(usd) : nil)
        }
        func fiveHourTokenText(start: Date, end: Date) -> String? {
            let total = usageReport.byHour.reduce(Int64(0)) { partial, hour in
                hour.hour >= start && hour.hour < end ? partial + hour.usage.total : partial
            }
            return total > 0 ? compact(total) : nil
        }

        let weeklyRecords = QuotaCycleStore.shared.cycles(limitID: limitID, kind: .weekly)
        let weeklyTolerance: TimeInterval = 24 * 3600
        var matchedWeeklyIndex: Int?
        var currentInfo: WeeklyCycleInfo?
        if let liveWeekly = limit?.secondary, let resetsAt = liveWeekly.resetsAt, liveWeekly.windowMinutes > 0 {
            matchedWeeklyIndex = weeklyRecords.firstIndex { record in
                record.resetAtDate(iso).map { abs($0.timeIntervalSince(resetsAt)) <= weeklyTolerance } == true
            }
            let recordedPeak = matchedWeeklyIndex.map { weeklyRecords[$0].maxUsedPercent } ?? 0
            currentInfo = WeeklyCycleInfo(
                start: resetsAt.addingTimeInterval(-Double(liveWeekly.windowMinutes) * 60),
                end: resetsAt,
                percent: max(0, min(100, max(liveWeekly.usedPercent, recordedPeak))),
                isBackfilled: false,
                isCurrent: true
            )
        }

        var infos: [WeeklyCycleInfo] = []
        for (index, record) in weeklyRecords.enumerated() {
            if index == matchedWeeklyIndex { continue }
            guard let end = record.resetAtDate(iso) else { continue }
            if currentInfo != nil && end.timeIntervalSinceNow > 0 { continue }
            infos.append(WeeklyCycleInfo(
                start: record.cycleStartDate(iso),
                end: end,
                percent: max(0, min(100, record.maxUsedPercent)),
                isBackfilled: record.isBackfilled,
                isCurrent: false
            ))
        }
        infos.sort { $0.end < $1.end }
        if let currentInfo {
            infos.append(currentInfo)
        }

        // A cycle whose successor starts well before the scheduled reset was
        // refreshed early (e.g. a provider promotion). Backfilled estimates
        // carry too much calendar-week drift to classify.
        let earlyRefreshTolerance: TimeInterval = 12 * 3600
        for index in 0..<max(0, infos.count - 1) {
            guard !infos[index].isBackfilled, !infos[index + 1].isBackfilled,
                  let nextStart = infos[index + 1].start,
                  nextStart < infos[index].end.addingTimeInterval(-earlyRefreshTolerance) else {
                continue
            }
            infos[index].earlyRefreshAt = nextStart
        }
        // Backfilled cycles carry their real span in start/end; one clearly
        // shorter than a weekly window means the quota was refreshed early.
        // The oldest cycle is exempt: its start is when observation began,
        // not the true cycle start, so a short span proves nothing.
        for index in 1..<max(1, infos.count) {
            guard infos[index].isBackfilled, infos[index].earlyRefreshAt == nil,
                  let start = infos[index].start,
                  infos[index].end.timeIntervalSince(start) < 5.5 * 86_400 else {
                continue
            }
            infos[index].earlyRefreshAt = infos[index].end
        }

        var hasBackfilled = false
        var hasEarlyRefresh = false
        var rows: [QuotaCycleRowModel] = []
        for info in infos {
            if info.isBackfilled { hasBackfilled = true }
            if info.earlyRefreshAt != nil { hasEarlyRefresh = true }
            let effectiveEnd = info.earlyRefreshAt ?? info.end
            let dayText: (Date) -> String = { Self.cycleDayLabelFormatter.string(from: $0) }
            let timeText: (Date) -> String = { Self.cycleTimeLabelFormatter.string(from: $0) }

            let shortRange: String
            let fullRange: String
            if info.isCurrent {
                let startDay = info.start.map(dayText) ?? "--"
                let startFull = info.start.map(timeText) ?? "--"
                shortRange = "\(startDay)→\(t(.cycleNow))"
                fullRange = "\(startFull) → \(t(.cycleNow))"
            } else if let start = info.start {
                shortRange = "\(dayText(start))→\(dayText(effectiveEnd))"
                fullRange = "\(timeText(start)) → \(timeText(effectiveEnd))"
            } else {
                shortRange = dayText(effectiveEnd)
                fullRange = timeText(effectiveEnd)
            }

            // Badges stay short: the range line above already carries the
            // dates, and the hover tooltip has the exact timestamps.
            let kind: QuotaCycleRowKind = info.isCurrent ? .current : (info.earlyRefreshAt != nil ? .earlyRefresh : .scheduledReset)
            let kindTimeText: String
            let badgeText: String
            switch kind {
            case .current:
                kindTimeText = timeText(info.end)
                badgeText = "\(t(.cycleInProgress)) · \(compactResetRelative(info.end))"
            case .earlyRefresh:
                kindTimeText = timeText(effectiveEnd)
                badgeText = t(.cycleEarlyRefresh)
            case .scheduledReset:
                kindTimeText = timeText(info.end)
                badgeText = "\(t(.cycleNormalReset))\(info.isBackfilled ? " *" : "")"
            }

            let durationText: String
            if let start = info.start {
                let referenceEnd = info.isCurrent ? Date() : effectiveEnd
                let days = max(0, referenceEnd.timeIntervalSince(start)) / 86_400
                durationText = String(format: t(info.isCurrent ? .cycleCurrentDayFormat : .cycleDurationDaysFormat), days)
            } else {
                durationText = "--"
            }

            let usageStats = cycleUsageStats(start: info.start, end: info.isCurrent ? Date() : effectiveEnd)
            // Cycle value: the weekly plan budget, pro-rated for cycles that
            // were cut short by an early refresh.
            var moneyValue: Double?
            var usedMoneyValue: Double?
            if weeklyBudget > 0, let start = info.start {
                let span = max(0, effectiveEnd.timeIntervalSince(start))
                let value = weeklyBudget * min(1, span / (7 * 86_400))
                moneyValue = value
                usedMoneyValue = value * max(0, min(100, info.percent)) / 100
            }
            rows.append(QuotaCycleRowModel(
                shortRange: shortRange,
                fullRange: fullRange,
                kind: kind,
                badgeText: badgeText,
                kindTimeText: kindTimeText,
                durationText: durationText,
                percent: info.percent,
                isCurrent: info.isCurrent,
                isPartial: info.isBackfilled,
                tokenText: usageStats.tokenText,
                apiCostText: usageStats.apiCostText,
                moneyValue: moneyValue,
                usedMoneyValue: usedMoneyValue
            ))
        }
        rows.reverse()
        rows = Array(rows.prefix(60))

        // Money summary over the shown cycles, plus a token estimate for the
        // remaining share of the current cycle.
        var moneySummary: QuotaCycleMoneySummary?
        if weeklyBudget > 0, !rows.isEmpty {
            var totalValue = 0.0
            var usedValue = 0.0
            var wastedValue = 0.0
            var currentValue: Double?
            var currentUsedValue: Double?
            for row in rows {
                guard let value = row.moneyValue, let used = row.usedMoneyValue else { continue }
                totalValue += value
                usedValue += used
                if row.isCurrent {
                    currentValue = value
                    currentUsedValue = used
                } else {
                    wastedValue += max(0, value - used)
                }
            }
            var remainTokensText: String?
            if let currentRow = rows.first(where: { $0.isCurrent }),
               let estimator = CostEstimator(
                   report: usageReport,
                   limit: limit,
                   quotaReferenceReport: nil,
                   monthlyCost: monthlyCost,
                   paymentStartDay: AppSettings.paymentStartDay(for: moneySource)
               ) {
                let remainPercent = max(0, 100 - currentRow.percent)
                let tokens = Int64(estimator.weeklyReferenceTotal * remainPercent / 100)
                if tokens > 0 {
                    remainTokensText = String(format: t(.cycleTokensApproxFormat), compact(tokens))
                }
            }
            moneySummary = QuotaCycleMoneySummary(
                cycleCount: rows.count,
                totalValue: totalValue,
                usedValue: usedValue,
                wastedValue: wastedValue,
                currentValue: currentValue,
                currentUsedValue: currentUsedValue,
                currentRemainTokensText: remainTokensText,
                monthlyCost: monthlyCost,
                weeklyBudget: weeklyBudget
            )
        }

        // Daily usage inside the current cycle for the mini distribution.
        var currentDailyUsage: [(day: String, total: Int64)] = []
        if let currentInfo, let currentStart = currentInfo.start {
            for day in usageReport.byDay {
                guard let date = dayParser.date(from: day.day) else { continue }
                let midpoint = date.addingTimeInterval(43_200)
                guard midpoint >= currentStart, midpoint < Date().addingTimeInterval(43_200) else { continue }
                currentDailyUsage.append((day: day.day, total: day.usage.total))
            }
            currentDailyUsage.sort { $0.day < $1.day }
        }

        var bars: [QuotaCycleBarModel] = QuotaCycleStore.shared.cycles(limitID: limitID, kind: .fiveHour).compactMap { record in
            guard let end = record.resetAtDate(iso) else { return nil }
            return QuotaCycleBarModel(
                percent: max(0, min(100, record.maxUsedPercent)),
                resetAt: end,
                windowMinutes: record.windowMinutes,
                isCurrent: false,
                isEarlyRefresh: false
            )
        }
        if let livePrimary = limit?.primary, let resetsAt = livePrimary.resetsAt {
            let tolerance = min(max(Double(livePrimary.windowMinutes) * 60 * 0.1, 20 * 60), 24 * 3600)
            let liveUsed = max(0, min(100, livePrimary.usedPercent))
            if let index = bars.firstIndex(where: { abs($0.resetAt.timeIntervalSince(resetsAt)) <= tolerance }) {
                bars[index].isCurrent = true
                bars[index].percent = max(bars[index].percent, liveUsed)
            } else {
                bars.append(QuotaCycleBarModel(
                    percent: liveUsed,
                    resetAt: resetsAt,
                    windowMinutes: livePrimary.windowMinutes,
                    isCurrent: true,
                    isEarlyRefresh: false
                ))
            }
        }
        bars.sort { $0.resetAt < $1.resetAt }
        if bars.count > 36 {
            bars = Array(bars.suffix(36))
        }
        let fiveHourEarlyTolerance: TimeInterval = 30 * 60
        for index in 0..<max(0, bars.count - 1) {
            let next = bars[index + 1]
            guard next.windowMinutes > 0 else { continue }
            let nextStart = next.resetAt.addingTimeInterval(-Double(next.windowMinutes) * 60)
            if nextStart < bars[index].resetAt.addingTimeInterval(-fiveHourEarlyTolerance) {
                bars[index].isEarlyRefresh = true
                hasEarlyRefresh = true
            }
        }
        for index in 0..<bars.count {
            let bar = bars[index]
            let start = bar.resetAt.addingTimeInterval(-Double(max(bar.windowMinutes, 1)) * 60)
            bars[index].tokenText = fiveHourTokenText(start: start, end: bar.isCurrent ? Date() : bar.resetAt)
        }
        let capped = bars.filter { $0.percent >= 97 }.count

        return QuotaCyclePageModel(
            limit: limit,
            weeklyRows: rows,
            fiveHourBars: bars,
            cappedCount: capped,
            hasBackfilledRows: hasBackfilled,
            hasEarlyRefreshRows: hasEarlyRefresh,
            moneySummary: moneySummary,
            currentDailyUsage: currentDailyUsage
        )
    }

    private func cycleSeverityColor(_ percent: Double) -> NSColor {
        if percent >= 97 { return accentRose }
        if percent >= 70 { return accentAmber }
        return accentTeal
    }

    private func drawQuotaCyclesPage(snapshot: DetailsSnapshot, content: NSRect) {
        let model = quotaCyclePageModel(for: snapshot)
        let panelGap: CGFloat = 16

        guard model.moneySummary != nil else {
            // No plan cost configured: fall back to the percent-only layout.
            let currentHeight: CGFloat = 150
            let panelWidth = (content.width - panelGap) / 2
            let fiveHourRect = NSRect(x: content.minX, y: content.minY + 78, width: panelWidth, height: currentHeight)
            let weeklyCurrentRect = NSRect(x: fiveHourRect.maxX + panelGap, y: fiveHourRect.minY, width: panelWidth, height: currentHeight)
            drawCurrentCyclePanel(window: model.limit?.primary, title: t(.fiveHourWindow), rect: fiveHourRect)
            drawCurrentCyclePanel(window: model.limit?.secondary, title: t(.weeklyWindow), rect: weeklyCurrentRect)
            let historyHeight = weeklyHistoryPanelHeight(rowCount: model.weeklyRows.count, contentWidth: content.width)
            let historyRect = NSRect(x: content.minX, y: fiveHourRect.maxY + panelGap, width: content.width, height: historyHeight)
            drawWeeklyCycleHistory(model: model, rect: historyRect)
            let stripRect = NSRect(x: content.minX, y: historyRect.maxY + panelGap, width: content.width, height: 176)
            drawFiveHourCycleStrip(model: model, rect: stripRect)
            return
        }

        var y = content.minY + 78
        drawMoneySummaryCards(model: model, rect: NSRect(x: content.minX, y: y, width: content.width, height: 96))
        y += 96 + panelGap
        let currentRect = NSRect(x: content.minX, y: y, width: content.width, height: 172)
        drawCurrentCycleMoneyPanel(model: model, rect: currentRect)
        y += 172 + panelGap
        let barsRect = NSRect(x: content.minX, y: y, width: content.width, height: 330)
        drawCycleValueBars(model: model, rect: barsRect)
        y += 330 + panelGap
        drawFiveHourCycleStrip(model: model, rect: NSRect(x: content.minX, y: y, width: content.width, height: 176))
    }

    private func drawMoneySummaryCards(model: QuotaCyclePageModel, rect: NSRect) {
        guard let money = model.moneySummary else { return }
        let source = quotaCycleSource
        let gap: CGFloat = 12
        let cardWidth = (rect.width - gap * 3) / 4
        let usedShare = money.totalValue > 0 ? Int(round(money.usedValue / money.totalValue * 100)) : 0
        let wastedShare = money.totalValue > 0 ? Int(round(money.wastedValue / money.totalValue * 100)) : 0
        let currentRemain = (money.currentValue ?? 0) - (money.currentUsedValue ?? 0)
        let currentRemainShare = (money.currentValue ?? 0) > 0 ? Int(round(currentRemain / (money.currentValue ?? 1) * 100)) : 0
        var remainSub = "\(currentRemainShare)%"
        if let tokens = money.currentRemainTokensText {
            remainSub += " \(tokens)"
        }

        let cards: [(title: String, value: String, valueColor: NSColor, sub: String)] = [
            (
                String(format: t(.cycleMoneySummaryValueFormat), money.cycleCount),
                displayMoney(money.totalValue, source: source),
                .white,
                String(format: t(.cycleMoneyPerCycleFormat), displayMoney(money.monthlyCost, source: source), displayMoney(money.weeklyBudget, source: source))
            ),
            (
                t(.cycleMoneyUsedTitle),
                displayMoney(money.usedValue, source: source),
                accentTeal,
                "\(usedShare)%"
            ),
            (
                t(.cycleMoneyWastedTitle),
                displayMoney(money.wastedValue, source: source),
                money.wastedValue >= money.weeklyBudget * 0.5 ? accentRose : NSColor.white.withAlphaComponent(0.85),
                "\(wastedShare)%"
            ),
            (
                t(.cycleMoneyRemainTitle),
                money.currentValue != nil ? displayMoney(max(0, currentRemain), source: source) : "--",
                accentAmber,
                remainSub
            )
        ]
        for (index, card) in cards.enumerated() {
            let cardRect = NSRect(x: rect.minX + CGFloat(index) * (cardWidth + gap), y: rect.minY, width: cardWidth, height: rect.height)
            drawPanel(cardRect)
            drawText(card.title, rect: NSRect(x: cardRect.minX + 16, y: cardRect.minY + 14, width: cardRect.width - 32, height: 16), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.5))
            drawText(card.value, rect: NSRect(x: cardRect.minX + 16, y: cardRect.minY + 34, width: cardRect.width - 32, height: 28), font: .monospacedDigitSystemFont(ofSize: 23, weight: .bold), color: card.valueColor)
            drawTruncatedText(card.sub, rect: NSRect(x: cardRect.minX + 16, y: cardRect.minY + 66, width: cardRect.width - 32, height: 15), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
        }
    }

    private func drawCurrentCycleMoneyPanel(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        let source = quotaCycleSource
        guard let window = model.limit?.secondary,
              window.windowMinutes > 0,
              let currentRow = model.weeklyRows.first(where: { $0.isCurrent }) else {
            drawText(t(.cycleCurrentTitle), rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: 300, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
            drawText(t(.liveLimitUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + 52, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let headerText = "\(t(.cycleCurrentTitle)) · \(currentRow.shortRange)"
        drawText(headerText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width * 0.5, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        if let resetsAt = window.resetsAt {
            let resetText = "\(t(.reset)) \(compactResetRelative(resetsAt)) · \(Self.cycleRangeFormatter.string(from: resetsAt))"
            drawRight(resetText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: rect.width - 36, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }

        let used = max(0, min(100, window.usedPercent))
        let usedColor = cycleSeverityColor(used)
        let leftWidth = rect.width * 0.56 - 18
        var bigText = "\(t(.used)) \(Int(round(used)))%"
        if let usedMoney = currentRow.usedMoneyValue {
            bigText += " · \(displayMoney(usedMoney, source: source))"
        }
        drawText(bigText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 46, width: leftWidth, height: 30), font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold), color: usedColor)

        let barRect = NSRect(x: rect.minX + 18, y: rect.minY + 96, width: leftWidth, height: 10)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 5, yRadius: 5).fill()
        let fillWidth = barRect.width * CGFloat(used / 100)
        if fillWidth > 1 {
            usedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height), xRadius: 5, yRadius: 5).fill()
        }
        var paceText = ""
        if let pace = paceComparison(for: window) {
            let markerX = barRect.minX + barRect.width * CGFloat(min(100, max(0, pace.progressPercent)) / 100)
            NSColor.white.withAlphaComponent(0.72).setFill()
            NSRect(x: markerX - 1, y: barRect.minY - 4, width: 2, height: barRect.height + 8).fill()
            let delta = Int(round(used - pace.progressPercent))
            paceText = delta > 0 ? String(format: t(.cyclePaceAheadFormat), delta) : String(format: t(.cyclePaceBehindFormat), -delta)
            let progressFraction = pace.progressPercent / 100
            if progressFraction >= 0.03, used >= 1, used < 100 {
                let projectedEnd = used / progressFraction
                if projectedEnd >= 100 {
                    let elapsedSeconds = Double(window.windowMinutes) * 60 * progressFraction
                    let secondsToCap = elapsedSeconds * (100 - used) / used
                    paceText += " · \(String(format: t(.cyclePaceCapEtaFormat), compactResetRelative(Date().addingTimeInterval(secondsToCap))))"
                } else {
                    paceText += " · \(String(format: t(.cyclePaceEndProjectionFormat), Int(round(projectedEnd))))"
                }
            }
        }
        if !paceText.isEmpty {
            drawTruncatedText(paceText, rect: NSRect(x: rect.minX + 18, y: barRect.maxY + 12, width: leftWidth, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        }

        // Right column: remaining money/tokens plus the daily distribution.
        let rightX = rect.minX + rect.width * 0.6
        let rightWidth = rect.maxX - 18 - rightX
        if let money = model.moneySummary, let currentValue = money.currentValue, let currentUsed = money.currentUsedValue {
            let remain = max(0, currentValue - currentUsed)
            var remainText = "\(t(.remaining)) \(displayMoney(remain, source: source))"
            if let tokens = money.currentRemainTokensText {
                remainText += " \(tokens)"
            }
            drawText(remainText, rect: NSRect(x: rightX, y: rect.minY + 50, width: rightWidth, height: 18), font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold), color: NSColor.white.withAlphaComponent(0.82))
        }
        if !model.currentDailyUsage.isEmpty {
            let barsTop = rect.minY + 82
            let barsBottom = rect.minY + 130
            let barsHeight = barsBottom - barsTop
            let count = model.currentDailyUsage.count
            let gap: CGFloat = 6
            let dayBarWidth = min(40, (rightWidth - gap * CGFloat(max(count - 1, 0))) / CGFloat(count))
            let maxTotal = max(model.currentDailyUsage.map(\.total).max() ?? 1, 1)
            for (index, day) in model.currentDailyUsage.enumerated() {
                let height = max(3, barsHeight * CGFloat(Double(day.total) / Double(maxTotal)))
                let dayRect = NSRect(
                    x: rightX + CGFloat(index) * (dayBarWidth + gap),
                    y: barsBottom - height,
                    width: dayBarWidth,
                    height: height
                )
                accentAmber.withAlphaComponent(index == count - 1 ? 1 : 0.5).setFill()
                NSBezierPath(roundedRect: dayRect, xRadius: 2.5, yRadius: 2.5).fill()
            }
            drawText(t(.cycleDailyHint), rect: NSRect(x: rightX, y: barsBottom + 8, width: rightWidth, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.38))
        }
    }

    private func drawCycleValueBars(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        quotaCycleTooltipRows = model.weeklyRows
        drawText(t(.cycleHistoryTitle), rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 320, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let completed = model.weeklyRows.filter { !$0.isCurrent }
        var summaryParts: [String] = []
        summaryParts.append(String(format: t(.cycleCappedCountFormat), completed.filter(\.isCapped).count))
        let earlyCount = model.weeklyRows.filter(\.isEarlyRefresh).count
        if earlyCount > 0 {
            summaryParts.append(String(format: t(.cycleEarlyCountFormat), earlyCount))
        }
        drawRight(summaryParts.joined(separator: " · "), rect: NSRect(x: rect.minX + 16, y: rect.minY + 18, width: rect.width - 32, height: 16), color: NSColor.white.withAlphaComponent(0.5), font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))

        guard !model.weeklyRows.isEmpty else {
            drawText(t(.cycleNoHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let source = quotaCycleSource
        let cells = Array(model.weeklyRows.reversed())
        let count = cells.count
        let showsBadges = count <= 8
        let areaX = rect.minX + 18
        let areaWidth = rect.width - 36
        let gap: CGFloat = count > 16 ? 6 : 14
        let barWidth = min(66, (areaWidth - gap * CGFloat(max(count - 1, 0))) / CGFloat(count))
        let groupWidth = barWidth * CGFloat(count) + gap * CGFloat(max(count - 1, 0))
        let groupX = areaX + max(0, (areaWidth - groupWidth) / 2)
        let barsTop = rect.minY + 56
        let barsBottom = rect.maxY - (showsBadges ? 96 : 72)
        let maxValue = max(model.weeklyRows.compactMap(\.moneyValue).max() ?? 1, 0.01)

        for (displayIndex, row) in cells.enumerated() {
            let modelIndex = count - 1 - displayIndex
            let value = row.moneyValue ?? 0
            let usedMoney = row.usedMoneyValue ?? 0
            let barX = groupX + CGFloat(displayIndex) * (barWidth + gap)
            let totalHeight = max(6, (barsBottom - barsTop) * CGFloat(value / maxValue))
            let usedHeight = max(3, totalHeight * CGFloat(max(0, min(100, row.percent)) / 100))
            let wasteHeight = max(0, totalHeight - usedHeight)

            if wasteHeight > 0.5 {
                accentRose.withAlphaComponent(row.isCurrent ? 0.14 : (row.isPartial ? 0.3 : 0.45)).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: barsBottom - totalHeight, width: barWidth, height: wasteHeight), xRadius: 4, yRadius: 4).fill()
            }
            let usedColor = row.isCurrent ? accentAmber : (row.isPartial ? accentTeal.withAlphaComponent(0.55) : accentTeal)
            let usedPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barsBottom - usedHeight, width: barWidth, height: usedHeight), xRadius: 4, yRadius: 4)
            usedColor.setFill()
            usedPath.fill()
            if row.isCurrent {
                accentAmber.setStroke()
                let focus = NSBezierPath(roundedRect: NSRect(x: barX - 3, y: barsBottom - totalHeight - 3, width: barWidth + 6, height: totalHeight + 6), xRadius: 6, yRadius: 6)
                focus.lineWidth = 1.5
                focus.stroke()
            }

            let topLabel: String
            let topColor: NSColor
            if row.isCurrent {
                topLabel = displayMoney(usedMoney, source: source)
                topColor = accentAmber
            } else if let waste = row.wastedMoneyValue, waste >= 1 {
                topLabel = "-\(displayMoney(waste, source: source))"
                topColor = accentRose.withAlphaComponent(0.92)
            } else {
                topLabel = "≈0"
                topColor = NSColor.white.withAlphaComponent(0.4)
            }
            let topLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            let topLabelY = barsBottom - totalHeight - 20
            drawCentered(topLabel, rect: NSRect(x: barX - gap / 2, y: topLabelY, width: barWidth + gap, height: 14), font: topLabelFont, color: topColor)
            if row.isCapped {
                let topLabelWidth = measuredTextWidth(topLabel, font: topLabelFont)
                accentRose.setFill()
                NSBezierPath(ovalIn: NSRect(x: barX + barWidth / 2 + topLabelWidth / 2 + 5, y: topLabelY + 5, width: 4.5, height: 4.5)).fill()
            }

            let labelY = barsBottom + 8
            drawCentered(row.shortRange, rect: NSRect(x: barX - gap / 2 - 8, y: labelY, width: barWidth + gap + 16, height: 15), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold), color: NSColor.white.withAlphaComponent(row.isCurrent ? 0.94 : 0.66))
            if showsBadges {
                drawCycleBadge(row: row, centerX: barX + barWidth / 2, y: labelY + 20, maxWidth: barWidth + gap + 8)
            }
            quotaCycleHitAreas.append((
                rect: NSRect(x: barX - gap / 2, y: barsTop, width: barWidth + gap, height: barsBottom - barsTop + 20),
                index: modelIndex
            ))
        }

        let legendY = rect.maxY - 26
        var legendX = rect.minX + 16
        let legendFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let legendColor = NSColor.white.withAlphaComponent(0.42)
        func legendSwatch(_ color: NSColor, _ text: String) {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: legendX, y: legendY + 3, width: 9, height: 9), xRadius: 2, yRadius: 2).fill()
            drawText(text, rect: NSRect(x: legendX + 13, y: legendY, width: 120, height: 14), font: legendFont, color: legendColor)
            legendX += 13 + measuredTextWidth(text, font: legendFont) + 18
        }
        legendSwatch(accentTeal, t(.used))
        legendSwatch(accentRose.withAlphaComponent(0.5), t(.cycleWasteLabel))
        var footnotes = [t(.cycleMoneyHint)]
        if model.hasBackfilledRows {
            footnotes.append("* \(t(.cycleBackfilled))")
        }
        drawTruncatedText(footnotes.joined(separator: "   ·   "), rect: NSRect(x: legendX + 8, y: legendY, width: rect.maxX - 16 - legendX - 8, height: 14), font: legendFont, color: NSColor.white.withAlphaComponent(0.36))
    }

    private func drawCurrentCyclePanel(window: RateWindow?, title: String, rect: NSRect) {
        drawPanel(rect)
        drawText(title, rect: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 200, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        guard let window, window.windowMinutes > 0 else {
            drawText(t(.liveLimitUnavailable), rect: NSRect(x: rect.minX + 18, y: rect.minY + 52, width: rect.width - 36, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        if let resetsAt = window.resetsAt {
            let resetText = "\(t(.reset)) \(compactResetRelative(resetsAt)) · \(Self.cycleRangeFormatter.string(from: resetsAt))"
            drawRight(resetText, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: rect.width - 36, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }

        let used = max(0, min(100, window.usedPercent))
        let usedColor = cycleSeverityColor(used)
        drawText("\(t(.used)) \(Int(round(used)))%", rect: NSRect(x: rect.minX + 18, y: rect.minY + 44, width: rect.width - 36, height: 32), font: .monospacedDigitSystemFont(ofSize: 26, weight: .bold), color: usedColor)

        let barRect = NSRect(x: rect.minX + 18, y: rect.minY + 92, width: rect.width - 36, height: 10)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 5, yRadius: 5).fill()
        let fillWidth = barRect.width * CGFloat(used / 100)
        if fillWidth > 1 {
            usedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height), xRadius: 5, yRadius: 5).fill()
        }

        var paceText = ""
        if let pace = paceComparison(for: window) {
            let markerX = barRect.minX + barRect.width * CGFloat(min(100, max(0, pace.progressPercent)) / 100)
            NSColor.white.withAlphaComponent(0.72).setFill()
            NSRect(x: markerX - 1, y: barRect.minY - 4, width: 2, height: barRect.height + 8).fill()
            let delta = Int(round(used - pace.progressPercent))
            if delta > 0 {
                paceText = String(format: t(.cyclePaceAheadFormat), delta)
            } else {
                paceText = String(format: t(.cyclePaceBehindFormat), -delta)
            }
            paceText += " · \(t(.cycleTimeMarkerHint)) \(Int(round(pace.progressPercent)))%"

            // Constant-rate projection: will this cycle hit the cap, and when?
            let progressFraction = pace.progressPercent / 100
            if progressFraction >= 0.03, used >= 1, used < 100 {
                let projectedEnd = used / progressFraction
                if projectedEnd >= 100 {
                    let elapsedSeconds = Double(window.windowMinutes) * 60 * progressFraction
                    let secondsToCap = elapsedSeconds * (100 - used) / used
                    let capText = compactResetRelative(Date().addingTimeInterval(secondsToCap))
                    paceText += " · \(String(format: t(.cyclePaceCapEtaFormat), capText))"
                } else {
                    paceText += " · \(String(format: t(.cyclePaceEndProjectionFormat), Int(round(projectedEnd))))"
                }
            }
        }
        if !paceText.isEmpty {
            drawTruncatedText(paceText, rect: NSRect(x: rect.minX + 18, y: barRect.maxY + 12, width: rect.width - 36, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        }
    }

    private func weeklyHistoryPanelHeight(rowCount: Int, contentWidth: CGFloat) -> CGFloat {
        guard rowCount > 0 else { return 96 }
        let bandCount = max(0, rowCount - 6)
        let bandHeight: CGFloat
        if bandCount > 0 {
            let perRow = max(1, Int((contentWidth - 32 + 8) / 32))
            let bandRows = Int(ceil(Double(bandCount) / Double(perRow)))
            bandHeight = 32 + CGFloat(bandRows) * 32
        } else {
            bandHeight = 30
        }
        return 50 + 138 + bandHeight + 30
    }

    private func drawCycleRing(rect: NSRect, thickness: CGFloat, percent: Double, color: NSColor, highlighted: Bool) {
        fillDonut(in: rect, thickness: thickness, color: NSColor.white.withAlphaComponent(0.09))
        let progress = CGFloat(max(0, min(100, percent)) / 100)
        // Semi-transparent fills would double-darken where the rounded caps
        // overlap the arc, so draw the arc opaque inside a transparency layer
        // and apply the alpha to the composited result.
        let alpha = color.alphaComponent
        let opaqueColor = alpha < 0.999 ? color.withAlphaComponent(1) : color
        let cgContext = alpha < 0.999 ? NSGraphicsContext.current?.cgContext : nil
        if let cgContext {
            cgContext.saveGState()
            cgContext.setAlpha(alpha)
            cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if progress >= 0.999 {
            fillDonut(in: rect, thickness: thickness, color: opaqueColor)
        } else if progress > 0.001 {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let outerRadius = rect.width / 2
            let startAngle = -CGFloat.pi / 2
            let endAngle = startAngle + CGFloat.pi * 2 * progress
            fillDonutSegment(center: center, outerRadius: outerRadius, thickness: thickness, startAngle: startAngle, endAngle: endAngle, color: opaqueColor)
            let midRadius = outerRadius - thickness / 2
            opaqueColor.setFill()
            for angle in [startAngle, endAngle] {
                let capCenter = CGPoint(x: center.x + midRadius * cos(angle), y: center.y + midRadius * sin(angle))
                NSBezierPath(ovalIn: NSRect(x: capCenter.x - thickness / 2, y: capCenter.y - thickness / 2, width: thickness, height: thickness)).fill()
            }
        }
        if let cgContext {
            cgContext.endTransparencyLayer()
            cgContext.restoreGState()
        }
        if highlighted {
            color.setStroke()
            let focus = NSBezierPath(ovalIn: rect.insetBy(dx: -4.5, dy: -4.5))
            focus.lineWidth = 1.5
            focus.stroke()
        }
    }

    private func drawCycleBadge(row: QuotaCycleRowModel, centerX: CGFloat, y: CGFloat, maxWidth: CGFloat) {
        let font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let iconName: String
        let tint: NSColor
        let background: NSColor
        switch row.kind {
        case .current:
            iconName = "play.fill"
            tint = NSColor.systemGreen
            background = NSColor.systemGreen.withAlphaComponent(0.13)
        case .earlyRefresh:
            iconName = "bolt.fill"
            tint = accentBlue
            background = accentBlue.withAlphaComponent(0.16)
        case .scheduledReset:
            iconName = "arrow.clockwise"
            tint = NSColor.white.withAlphaComponent(0.56)
            background = NSColor.white.withAlphaComponent(0.08)
        }
        let textWidth = min(maxWidth - 32, measuredTextWidth(row.badgeText, font: font))
        let pillWidth = textWidth + 30
        let pill = NSRect(x: centerX - pillWidth / 2, y: y, width: pillWidth, height: 18)
        background.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
        drawSymbolIcon(iconName, in: NSRect(x: pill.minX + 7, y: pill.minY + 4.5, width: 9, height: 9), color: tint, pointSize: 8)
        drawTruncatedText(row.badgeText, rect: NSRect(x: pill.minX + 20, y: pill.minY + 2.5, width: pill.width - 26, height: 13), font: font, color: tint)
    }

    private func drawWeeklyCycleHistory(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        quotaCycleTooltipRows = model.weeklyRows
        drawText(t(.cycleHistoryTitle), rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 320, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)

        let completed = model.weeklyRows.filter { !$0.isCurrent }
        let statsBase = completed.isEmpty ? model.weeklyRows : completed
        if !statsBase.isEmpty {
            let averagePeak = Int(round(statsBase.map(\.percent).reduce(0, +) / Double(statsBase.count)))
            var summaryParts = [String(format: t(.cycleAvgPeakFormat), averagePeak)]
            summaryParts.append(String(format: t(.cycleCappedCountFormat), completed.filter(\.isCapped).count))
            let earlyCount = model.weeklyRows.filter(\.isEarlyRefresh).count
            if earlyCount > 0 {
                summaryParts.append(String(format: t(.cycleEarlyCountFormat), earlyCount))
            }
            drawRight(summaryParts.joined(separator: " · "), rect: NSRect(x: rect.minX + 16, y: rect.minY + 18, width: rect.width - 32, height: 16), color: NSColor.white.withAlphaComponent(0.5), font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium))
        }

        guard !model.weeklyRows.isEmpty else {
            drawText(t(.cycleNoHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        // Recent cycles as large rings: oldest on the left, current on the right.
        let bigCount = min(model.weeklyRows.count, 6)
        let bigRows = Array(model.weeklyRows.prefix(bigCount).reversed())
        let cellWidth = min(178, (rect.width - 32) / CGFloat(bigCount))
        let startX = rect.minX + 16 + max(0, (rect.width - 32 - cellWidth * CGFloat(bigCount)) / 2)
        let ringSide: CGFloat = 84
        let ringTop = rect.minY + 52
        let rangeFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        for (displayIndex, row) in bigRows.enumerated() {
            let modelIndex = bigCount - 1 - displayIndex
            let cellMidX = startX + CGFloat(displayIndex) * cellWidth + cellWidth / 2
            let ringRect = NSRect(x: cellMidX - ringSide / 2, y: ringTop, width: ringSide, height: ringSide)
            let percent = max(0, min(100, row.percent))
            let color = cycleSeverityColor(percent)
            drawCycleRing(rect: ringRect, thickness: 9, percent: percent, color: row.isPartial ? color.withAlphaComponent(0.5) : color, highlighted: row.isCurrent)
            drawCentered("\(Int(round(percent)))%", rect: NSRect(x: ringRect.minX, y: ringRect.midY - 11, width: ringRect.width, height: 18), font: .monospacedDigitSystemFont(ofSize: 16, weight: .bold), color: row.isCurrent ? .white : NSColor.white.withAlphaComponent(0.9))
            drawCentered(row.isCurrent ? t(.used) : t(.cyclePeak), rect: NSRect(x: ringRect.minX, y: ringRect.midY + 7, width: ringRect.width, height: 12), font: .systemFont(ofSize: 8.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))

            let rangeY = ringRect.maxY + 10
            drawCentered(row.shortRange, rect: NSRect(x: cellMidX - cellWidth / 2 - 8, y: rangeY, width: cellWidth + 16, height: 15), font: rangeFont, color: NSColor.white.withAlphaComponent(row.isCurrent ? 0.94 : 0.7))
            if row.isCapped {
                let rangeWidth = measuredTextWidth(row.shortRange, font: rangeFont)
                accentRose.setFill()
                NSBezierPath(ovalIn: NSRect(x: cellMidX + rangeWidth / 2 + 5, y: rangeY + 5, width: 5, height: 5)).fill()
            }
            drawCycleBadge(row: row, centerX: cellMidX, y: rangeY + 20, maxWidth: cellWidth - 8)
            quotaCycleHitAreas.append((rect: ringRect.insetBy(dx: -6, dy: -6), index: modelIndex))
        }

        // Older cycles as a dense mini-ring band, oldest first.
        let bandTop = ringTop + ringSide + 52
        let bandModels = Array(model.weeklyRows.dropFirst(6).reversed())
        if bandModels.isEmpty {
            drawText(t(.cycleBandGrowHint), rect: NSRect(x: rect.minX + 16, y: bandTop + 4, width: rect.width - 32, height: 15), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.34))
        } else {
            drawText("\(t(.cycleEarlierBand)) (\(bandModels.count))", rect: NSRect(x: rect.minX + 16, y: bandTop, width: rect.width - 32, height: 15), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.44))
            let miniSide: CGFloat = 24
            let miniGap: CGFloat = 8
            let perRow = max(1, Int((rect.width - 32 + miniGap) / (miniSide + miniGap)))
            for (bandIndex, row) in bandModels.enumerated() {
                let modelIndex = model.weeklyRows.count - 1 - bandIndex
                let column = bandIndex % perRow
                let bandRow = bandIndex / perRow
                let miniRect = NSRect(
                    x: rect.minX + 16 + CGFloat(column) * (miniSide + miniGap),
                    y: bandTop + 22 + CGFloat(bandRow) * (miniSide + 8),
                    width: miniSide,
                    height: miniSide
                )
                let percent = max(0, min(100, row.percent))
                let color = cycleSeverityColor(percent)
                drawCycleRing(rect: miniRect, thickness: 4.5, percent: percent, color: row.isPartial ? color.withAlphaComponent(0.5) : color, highlighted: false)
                if hoveredQuotaCycleIndex == modelIndex {
                    NSColor.white.withAlphaComponent(0.65).setStroke()
                    let focus = NSBezierPath(ovalIn: miniRect.insetBy(dx: -2.5, dy: -2.5))
                    focus.lineWidth = 1
                    focus.stroke()
                }
                quotaCycleHitAreas.append((rect: miniRect.insetBy(dx: -4, dy: -4), index: modelIndex))
            }
        }

        var footnotes = [t(.cycleHistoryHint)]
        if model.hasBackfilledRows {
            footnotes.append("* \(t(.cycleBackfilled))")
        }
        if model.hasEarlyRefreshRows {
            footnotes.append(t(.cycleEarlyRefreshFootnote))
        }
        drawTruncatedText(footnotes.joined(separator: "   ·   "), rect: NSRect(x: rect.minX + 16, y: rect.maxY - 24, width: rect.width - 32, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.36))
    }

    private func updateQuotaCycleHover(at point: CGPoint) {
        let match = quotaCycleHitAreas.first { $0.rect.contains(point) }
        let newIndex = match?.index
        if hoveredQuotaCycleIndex != newIndex {
            hoveredQuotaCycleIndex = newIndex
            needsDisplay = true
        }
    }

    private func drawQuotaCycleTooltip(container: NSRect) {
        guard let index = hoveredQuotaCycleIndex,
              index >= 0, index < quotaCycleTooltipRows.count,
              let hit = quotaCycleHitAreas.first(where: { $0.index == index }) else {
            return
        }
        let row = quotaCycleTooltipRows[index]

        var lines: [(String, String, NSColor)] = []
        let percentColor = cycleSeverityColor(row.percent)
        var percentValue = "\(Int(round(row.percent)))%"
        if let usedMoney = row.usedMoneyValue {
            percentValue += " · \(displayMoney(usedMoney, source: quotaCycleSource))"
        }
        lines.append((row.isCurrent ? t(.used) : t(.cyclePeak), percentValue, percentColor))
        if let waste = row.wastedMoneyValue, waste >= 0.5 {
            lines.append((t(.cycleWasteLabel), displayMoney(waste, source: quotaCycleSource), accentRose.withAlphaComponent(0.92)))
        }
        if let value = row.moneyValue {
            lines.append((t(.cycleValueLabel), displayMoney(value, source: quotaCycleSource), NSColor.white.withAlphaComponent(0.88)))
        }
        if let tokenText = row.tokenText {
            lines.append(("Token", tokenText, NSColor.white.withAlphaComponent(0.9)))
        }
        if let apiCostText = row.apiCostText {
            lines.append((t(.apiEquivalent), apiCostText, accentTeal))
        }
        switch row.kind {
        case .current:
            lines.append((t(.reset), row.kindTimeText, NSColor.white.withAlphaComponent(0.88)))
        case .earlyRefresh:
            lines.append((t(.cycleEarlyRefresh), row.kindTimeText, accentBlue))
        case .scheduledReset:
            lines.append((t(.cycleNormalReset), row.kindTimeText, NSColor.white.withAlphaComponent(0.88)))
        }
        lines.append((t(.cycleDurationLabel), row.durationText, NSColor.white.withAlphaComponent(0.88)))
        let footerText: String? = row.isPartial ? "* \(t(.cycleBackfilled))" : nil

        let width: CGFloat = 238
        let height: CGFloat = 30 + CGFloat(lines.count) * 16 + (footerText != nil ? 18 : 8)
        let gap: CGFloat = 12
        var origin = CGPoint(x: hit.rect.midX - width / 2, y: hit.rect.minY - height - gap)
        if origin.y < container.minY + 10 {
            origin.y = hit.rect.maxY + gap
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        drawText(row.fullRange, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 14), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.85))
        for (lineIndex, line) in lines.enumerated() {
            let y = tooltipRect.minY + 28 + CGFloat(lineIndex) * 16
            drawText(line.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 100, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.5))
            drawRight(line.1, rect: NSRect(x: tooltipRect.minX + 104, y: y - 1, width: tooltipRect.width - 114, height: 15), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
        if let footerText {
            drawText(footerText, rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.maxY - 17, width: tooltipRect.width - 20, height: 12), font: .systemFont(ofSize: 9, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))
        }
    }

    private func drawFiveHourCycleStrip(model: QuotaCyclePageModel, rect: NSRect) {
        drawPanel(rect)
        drawText(t(.fiveHourCyclesTitle), rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 260, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let summary = String(format: t(.cycleCappedFormat), model.cappedCount, model.fiveHourBars.count)
        drawRight(summary, rect: NSRect(x: rect.minX + 16, y: rect.minY + 18, width: rect.width - 32, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        var hintText = t(.fiveHourCyclesHint)
        if let primary = model.limit?.primary, primary.windowMinutes > 0 {
            hintText += " · \(t(.cycleCurrentTitle)) \(t(.used)) \(Int(round(max(0, min(100, primary.usedPercent)))))%"
            if let resetsAt = primary.resetsAt {
                hintText += " · \(t(.reset)) \(compactResetRelative(resetsAt))"
            }
        }
        drawTruncatedText(hintText, rect: NSRect(x: rect.minX + 16, y: rect.minY + 38, width: rect.width - 32, height: 15), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.44))

        guard !model.fiveHourBars.isEmpty else {
            drawText(t(.cycleNoHistory), rect: NSRect(x: rect.minX + 16, y: rect.minY + 76, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let areaTop = rect.minY + 62
        let areaBottom = rect.maxY - 34
        let areaHeight = areaBottom - areaTop
        let areaX = rect.minX + 18
        let areaWidth = rect.width - 36
        let count = model.fiveHourBars.count
        let showsPerBarLabels = count <= 10
        let gap: CGFloat = count > 24 ? 4 : (showsPerBarLabels ? 14 : 6)
        let maxBarWidth: CGFloat = showsPerBarLabels ? 38 : 26
        let barWidth = min(maxBarWidth, (areaWidth - gap * CGFloat(max(count - 1, 0))) / CGFloat(count))
        let groupWidth = barWidth * CGFloat(count) + gap * CGFloat(max(count - 1, 0))
        let groupX = areaX + max(0, (areaWidth - groupWidth) / 2)
        let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let labelColor = NSColor.white.withAlphaComponent(0.42)
        let tooltipIndexBase = quotaCycleTooltipRows.count

        for (index, bar) in model.fiveHourBars.enumerated() {
            let percent = max(0, min(100, bar.percent))
            let height = max(4, areaHeight * CGFloat(percent / 100))
            let barRect = NSRect(
                x: groupX + CGFloat(index) * (barWidth + gap),
                y: areaBottom - height,
                width: barWidth,
                height: height
            )
            cycleSeverityColor(percent).setFill()
            let path = NSBezierPath(roundedRect: barRect, xRadius: 2.5, yRadius: 2.5)
            path.fill()
            if bar.isCurrent {
                NSColor.white.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            if bar.isEarlyRefresh {
                accentBlue.setFill()
                NSBezierPath(ovalIn: NSRect(x: barRect.midX - 2.5, y: barRect.minY - 10, width: 5, height: 5)).fill()
            }
            if hoveredQuotaCycleIndex == tooltipIndexBase + index {
                NSColor.white.withAlphaComponent(0.65).setStroke()
                let focus = NSBezierPath(roundedRect: barRect.insetBy(dx: -2.5, dy: -2.5), xRadius: 4, yRadius: 4)
                focus.lineWidth = 1
                focus.stroke()
            }
            if showsPerBarLabels {
                drawCentered(Self.cycleClockLabelFormatter.string(from: bar.resetAt), rect: NSRect(x: barRect.midX - 30, y: areaBottom + 8, width: 60, height: 14), font: labelFont, color: labelColor)
            }

            let start = bar.resetAt.addingTimeInterval(-Double(max(bar.windowMinutes, 1)) * 60)
            let endText = bar.isCurrent ? t(.cycleNow) : Self.cycleTimeLabelFormatter.string(from: bar.resetAt)
            let minutes = max(bar.windowMinutes, 1)
            let durationText = minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m"
            quotaCycleTooltipRows.append(QuotaCycleRowModel(
                shortRange: "",
                fullRange: "\(Self.cycleTimeLabelFormatter.string(from: start)) → \(endText)",
                kind: bar.isCurrent ? .current : (bar.isEarlyRefresh ? .earlyRefresh : .scheduledReset),
                badgeText: "",
                kindTimeText: Self.cycleTimeLabelFormatter.string(from: bar.resetAt),
                durationText: durationText,
                percent: percent,
                isCurrent: bar.isCurrent,
                isPartial: false,
                tokenText: bar.tokenText,
                apiCostText: nil
            ))
            quotaCycleHitAreas.append((
                rect: NSRect(x: barRect.minX - gap / 2, y: areaTop, width: barWidth + gap, height: areaBottom - areaTop + 6),
                index: tooltipIndexBase + index
            ))
        }

        if !showsPerBarLabels {
            if let first = model.fiveHourBars.first {
                drawText(Self.cycleDayLabelFormatter.string(from: first.resetAt), rect: NSRect(x: areaX, y: areaBottom + 8, width: 90, height: 14), font: labelFont, color: labelColor)
            }
            if let last = model.fiveHourBars.last, model.fiveHourBars.count > 1 {
                drawRight(Self.cycleDayLabelFormatter.string(from: last.resetAt), rect: NSRect(x: rect.maxX - 16 - 90, y: areaBottom + 8, width: 90, height: 14), color: labelColor, font: labelFont)
            }
        }
    }

    private func drawCostPage(snapshot: DetailsSnapshot, content: NSRect) {
        let limit = sourceCostLimit(for: snapshot)
        let costSource = selectedDetailsSource
        let costData = costPageData(for: snapshot, limit: limit, year: selectedCostYear)
        let estimate = costData.estimate

        let summaryRect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 168)
        let settingsRect = NSRect(x: content.minX, y: summaryRect.maxY + 16, width: content.width, height: 244)
        let controlWidth = min(300, max(252, settingsRect.width * 0.34))
        let controlX = settingsRect.maxX - controlWidth - 16
        let labelX = settingsRect.minX + 16
        let leftColumnWidth = max(180, controlX - labelX - 24)
        let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let centeredLabelY: (NSRect) -> CGFloat = { frame in
            frame.midY - 10
        }
        drawCostOverviewPanel(estimate: estimate, apiEstimate: costData.apiEstimate, source: costSource, rect: summaryRect)
        drawPanel(settingsRect)
        let planTitle = costSource == .all ? "\(t(.planCost)) · \(t(.all))" : "\(t(.planCost)) · \(costSource.shortTitle)"
        drawText(planTitle, rect: NSRect(x: settingsRect.minX + 16, y: settingsRect.minY + 14, width: 300, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let monthlyLabelY = max(settingsRect.minY + 38, costAmountField.frame.midY - 12)
        drawText(t(.paymentMonthly), rect: NSRect(x: labelX, y: monthlyLabelY, width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawMultilineText(t(.planCostHint), rect: NSRect(x: labelX, y: monthlyLabelY + 22, width: leftColumnWidth, height: 32), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))

        drawText(t(.paymentStartDate), rect: NSRect(x: labelX, y: centeredLabelY(paymentStartDayField.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawText(t(.paymentCurrency), rect: NSRect(x: labelX, y: centeredLabelY(paymentCurrencyPopup.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawText(t(.displayCurrency), rect: NSRect(x: labelX, y: centeredLabelY(displayCurrencyPopup.frame), width: leftColumnWidth, height: 20), font: labelFont, color: .white)
        drawInputFieldBackground(costAmountField.frame)
        drawInputFieldBackground(paymentStartDayField.frame)

        let chartY = settingsRect.maxY + 16
        let chartRect = NSRect(x: content.minX, y: chartY, width: content.width, height: 332)
        drawPanel(chartRect)
        let headerLayout = costHistoryHeaderLayout(chartRect: chartRect)
        showHistoricalEmptyWeeksToggleRect = headerLayout.emptyWeeksSwitchRect
        drawText(t(.costHistory), rect: NSRect(x: chartRect.minX + 16, y: chartRect.minY + 12, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.costHistoryHint), rect: headerLayout.hintRect, font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.44))
        drawRight(t(.showPastEmptyWeeks), rect: headerLayout.emptyWeeksLabelRect, color: NSColor.white.withAlphaComponent(0.50), font: .systemFont(ofSize: 11, weight: .semibold))
        drawToggle(rect: headerLayout.emptyWeeksSwitchRect, isOn: AppSettings.showHistoricalEmptyWeeks)

        drawCostRings(rows: costData.weeklyRows, rect: headerLayout.ringsRect, year: selectedCostYear)

        let tableY = chartRect.maxY + 16
        let tableRect = NSRect(x: content.minX, y: tableY, width: content.width, height: max(120, content.maxY - tableY))
        drawPanel(tableRect)
        drawText(t(.monthlySpendHistory), rect: NSRect(x: tableRect.minX + 16, y: tableRect.minY + 12, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let rows = costData.monthlyRows
        if rows.isEmpty {
            let emptyMessage = estimate == nil ? t(.planCostUnavailable) : t(.noUsage)
            drawText(emptyMessage, rect: NSRect(x: tableRect.minX + 16, y: tableRect.minY + 48, width: tableRect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        } else {
            let visible = Array(rows.prefix(6))
            let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let headerFont = NSFont.systemFont(ofSize: 10, weight: .bold)
            let percentW = max(
                measuredTextWidth("%", font: headerFont),
                visible.map { measuredTextWidth(String(format: "%.0f%%", $0.usedPercentOfPlan), font: valueFont) }.max() ?? 0
            ) + 12
            let usedW = max(
                measuredTextWidth(t(.used), font: headerFont),
                visible.map { measuredTextWidth(displayMoney($0.usedValue, source: costSource), font: valueFont) }.max() ?? 0
            ) + 14
            let remainingW = max(
                measuredTextWidth(t(.remaining), font: headerFont),
                visible.map { measuredTextWidth(displayMoney(max(0, (estimate?.monthlyCost ?? AppSettings.monthlyPlanCost(for: costSource)) - $0.usedValue), source: costSource), font: valueFont) }.max() ?? 0
            ) + 14
            let percentX = tableRect.maxX - 18 - percentW
            let remainingX = percentX - 18 - remainingW
            let usedX = remainingX - 24 - usedW
            drawRight(t(.used), rect: NSRect(x: usedX, y: tableRect.minY + 20, width: usedW, height: 16), color: NSColor.white.withAlphaComponent(0.40), font: headerFont)
            drawRight(t(.remaining), rect: NSRect(x: remainingX, y: tableRect.minY + 20, width: remainingW, height: 16), color: NSColor.white.withAlphaComponent(0.40), font: headerFont)
            drawRight("%", rect: NSRect(x: percentX, y: tableRect.minY + 20, width: percentW, height: 16), color: NSColor.white.withAlphaComponent(0.40), font: headerFont)
            for (index, row) in visible.enumerated() {
                let rowY = tableRect.minY + 44 + CGFloat(index) * 18
                drawText(row.month, rect: NSRect(x: tableRect.minX + 16, y: rowY, width: max(90, usedX - tableRect.minX - 32), height: 16), font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .white)
                let monthlyCost = estimate?.monthlyCost ?? AppSettings.monthlyPlanCost(for: costSource)
                drawRight(displayMoney(row.usedValue, source: costSource), rect: NSRect(x: usedX, y: rowY, width: usedW, height: 16), color: .white, font: valueFont)
                drawRight(displayMoney(max(0, monthlyCost - row.usedValue), source: costSource), rect: NSRect(x: remainingX, y: rowY, width: remainingW, height: 16), color: NSColor.white.withAlphaComponent(0.60), font: valueFont)
                drawRight(String(format: "%.0f%%", row.usedPercentOfPlan), rect: NSRect(x: percentX, y: rowY, width: percentW, height: 16), color: NSColor.white.withAlphaComponent(0.52), font: valueFont)
            }
        }
    }

    private func drawProfileSelectedDayPanel(snapshot: DetailsSnapshot, report: TokenReport, rect: NSRect) {
        drawPanel(rect)
        let day = selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
            ?? report.byDay.last(where: { $0.usage.total > 0 })
            ?? report.byDay.last
        guard let day else {
            drawText(t(.noDaySelected), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
            return
        }

        let localDay = snapshot.codex.byDay.first { $0.day == day.day }
        let rawProfileDay = rawProfileCalendarReport(for: snapshot)?.byDay.first { $0.day == day.day }
        let rawProfileTotal = rawProfileDay?.usage.total ?? 0
        let localTotal = localDay?.usage.total ?? 0
        let isLocalFallback = rawProfileTotal == 0 && localTotal > 0 && day.usage.total == localTotal
        let maxTotal = max(report.byDay.map { $0.usage.total }.max() ?? 1, 1)
        let intensity = Double(day.usage.total) / Double(maxTotal)
        drawText(day.day, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 180, height: 24), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: .white)
        drawText(compact(day.usage.total), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: isLocalFallback ? NSColor.systemGreen : accentTeal)
        let sourceTitle = isLocalFallback ? "\(t(.profileAPISource)) + \(t(.logs))" : t(.profileAPISource)
        let dayMeta = "\(sourceTitle)  |  \(Int(round(intensity * 100)))% \(t(.peakDay))"
        let metaFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let metaRect = NSRect(x: rect.minX + 18, y: rect.minY + 90, width: 420, height: 18)
        drawText(dayMeta, rect: metaRect, font: metaFont, color: NSColor.white.withAlphaComponent(0.48))
        let metaWidth = min(metaRect.width - 22, measuredTextWidth(dayMeta, font: metaFont))
        let iconRect = NSRect(x: metaRect.minX + metaWidth + 6, y: metaRect.minY - 1, width: 16, height: 16)
        profileAPIInfoRect = iconRect
        drawInfoMark(rect: iconRect, highlighted: isHoveringProfileAPIInfo)

        typealias ProfileDayMetric = (title: String, value: String, color: NSColor, footer: String?)
        var metrics: [ProfileDayMetric] = [
            (t(.profileAPISource), rawProfileDay.map { compact($0.usage.total) } ?? "--", accentTeal, nil),
            (t(.logs), localDay.map { compact($0.usage.total) } ?? "--", NSColor.systemGreen, nil),
            (t(.peakDay), snapshot.accountUsage?.summary.peakDailyTokens.map { compact($0) } ?? "--", NSColor.systemCyan, nil)
        ]
        let apiEstimate = profileAPIDayEstimate(profileDay: day, localDay: localDay)
        if apiEstimate.hasPricedUsage {
            let footer = apiEstimate.coveragePercent < 99.5 ? "\(String(format: "%.0f%%", apiEstimate.coveragePercent)) \(t(.priced))" : nil
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, footer))
        }

        let startX = rect.minX + min(420, max(292, rect.width * 0.50))
        let gap: CGFloat = 12
        let availableMetricWidth = max(0, rect.maxX - startX - 18)
        let columns = metrics.count > 3 && availableMetricWidth >= 500 ? 4 : min(3, metrics.count)
        let metricW = (availableMetricWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let metricH: CGFloat = 74
        for (index, metric) in metrics.enumerated() {
            let col = index % columns
            let row = index / columns
            let card = NSRect(x: startX + CGFloat(col) * (metricW + gap), y: rect.minY + 42 + CGFloat(row) * (metricH + gap), width: metricW, height: metricH)
            NSColor.black.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
            let labelH: CGFloat = 16
            let valueH: CGFloat = 22
            let footerH: CGFloat = metric.footer == nil ? 0 : 14
            let blockH = labelH + 3 + valueH + (metric.footer == nil ? 0 : 2 + footerH)
            let blockY = card.midY - blockH / 2
            drawText(metric.title, rect: NSRect(x: card.minX + 12, y: blockY, width: card.width - 24, height: labelH), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
            drawText(metric.value, rect: NSRect(x: card.minX + 12, y: blockY + labelH + 3, width: card.width - 24, height: valueH), font: .monospacedDigitSystemFont(ofSize: metricW < 96 ? 13 : 15, weight: .bold), color: metric.color)
            if let footer = metric.footer {
                drawText(footer, rect: NSRect(x: card.minX + 12, y: blockY + labelH + 3 + valueH + 2, width: card.width - 24, height: footerH), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
            }
        }

        let metricRows = Int(ceil(Double(metrics.count) / Double(max(columns, 1))))
        let metricsBottom = rect.minY + 42 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * gap
        let modelY = max(rect.minY + 134, metricsBottom + 18)
        let modelRect = NSRect(
            x: rect.minX + 18,
            y: modelY,
            width: rect.width - 36,
            height: max(88, rect.maxY - modelY - 18)
        )
        drawSelectedDayModels(localDay?.modelBreakdown ?? [], rect: modelRect)
    }

    private func profileAPIDayEstimate(profileDay: DayUsage, localDay: DayUsage?) -> APICostEstimate {
        guard let localDay else {
            return APICostEstimator.estimate(day: profileDay)
        }
        let localEstimate = APICostEstimator.estimate(day: localDay)
        if localEstimate.hasPricedUsage {
            return APICostEstimate(
                usdValue: localEstimate.usdValue,
                pricedTokens: localEstimate.pricedTokens,
                totalTokens: max(profileDay.usage.total, localEstimate.totalTokens)
            )
        }
        let modelBreakdown = localDay.modelBreakdown.isEmpty ? profileDay.modelBreakdown : localDay.modelBreakdown
        let usage = profileDay.usage.total > 0 ? profileDay.usage : localDay.usage
        let mergedDay = DayUsage(day: profileDay.day, usage: usage, turns: profileDay.turns, modelBreakdown: modelBreakdown)
        return APICostEstimator.estimate(day: mergedDay)
    }

    private func drawSelectedDayPanel(snapshot: DetailsSnapshot, rect: NSRect) {
        drawPanel(rect)
        let report = calendarReport(for: snapshot)
        let day = selectedDay.flatMap { selected in report.byDay.first { $0.day == selected } }
            ?? report.byDay.last(where: { $0.usage.total > 0 })
            ?? report.byDay.last
        guard let day else {
            drawText(t(.noDaySelected), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 220, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
            return
        }

        let maxTotal = max(report.byDay.map { $0.usage.total }.max() ?? 1, 1)
        let intensity = Double(day.usage.total) / Double(maxTotal)
        drawText(day.day, rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 180, height: 24), font: .monospacedDigitSystemFont(ofSize: 17, weight: .bold), color: .white)
        drawText(compact(day.usage.total), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: .systemGreen)
        let limit = sourceCostLimit(for: snapshot)
        let cost = planCostEstimate(
            report: report,
            selectedDay: day,
            limit: limit,
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        )
        var dayMeta = "\(day.turns) \(t(.turns).lowercased())  |  \(Int(round(intensity * 100)))% \(t(.peakDay))"
        if let cost {
            dayMeta += "  |  \(String(format: "%.1f%%", cost.selectedDayQuotaPercent)) \(t(.weeklyQuotaShare))"
        }
        drawText(dayMeta, rect: NSRect(x: rect.minX + 18, y: rect.minY + 90, width: 420, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))

        typealias DayMetric = (title: String, value: String, color: NSColor, infoAnchor: Bool, footer: String?)
        var metrics: [DayMetric] = [
            (t(.input), compact(day.usage.input), NSColor.systemGreen, false, nil),
            (t(.output), compact(day.usage.output), NSColor.systemCyan, false, nil),
            (t(.cached), compact(day.usage.cachedInput), NSColor.systemTeal, false, nil),
            (t(.fresh), compact(day.usage.freshInput), NSColor.systemOrange, false, nil)
        ]
        if let cost {
            metrics.append(("\(t(.dayValue)) ?", displayMoney(cost.selectedDayValue, source: selectedDetailsSource), NSColor.systemGreen, true, nil))
        }
        let apiEstimate = APICostEstimator.estimate(day: day)
        if apiEstimate.hasPricedUsage {
            let footer = apiEstimate.coveragePercent < 99.5 ? "\(String(format: "%.0f%%", apiEstimate.coveragePercent)) \(t(.priced))" : nil
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, false, footer))
        }
        let startX = rect.minX + 310
        let gap: CGFloat = 12
        let availableMetricWidth = max(180, rect.maxX - startX - 18)
        let columns: Int
        if metrics.count > 4 {
            columns = availableMetricWidth >= 360 ? 3 : 2
        } else {
            columns = availableMetricWidth >= 460 ? 4 : 2
        }
        let metricW = (availableMetricWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let metricH: CGFloat
        switch columns {
        case 4:
            metricH = 72
        case 3:
            metricH = 62
        default:
            metricH = 56
        }
        for (index, metric) in metrics.enumerated() {
            let col = index % columns
            let row = index / columns
            let card = NSRect(x: startX + CGFloat(col) * (metricW + gap), y: rect.minY + 24 + CGFloat(row) * (metricH + 10), width: metricW, height: metricH)
            if metric.infoAnchor {
                dayValueInfoRect = card
            }
            NSColor.black.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
            let hasFooter = metric.footer != nil
            let labelH: CGFloat = 16
            let valueH: CGFloat = columns >= 3 ? 20 : 18
            let footerH: CGFloat = hasFooter ? 14 : 0
            let innerGap: CGFloat = columns >= 3 ? 3 : 1
            let footerGap: CGFloat = hasFooter ? 2 : 0
            let blockH = labelH + innerGap + valueH + footerGap + footerH
            let blockY = card.midY - blockH / 2
            drawText(metric.title, rect: NSRect(x: card.minX + 12, y: blockY, width: card.width - 24, height: labelH), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
            drawText(metric.value, rect: NSRect(x: card.minX + 12, y: blockY + labelH + innerGap, width: card.width - 24, height: valueH), font: .monospacedDigitSystemFont(ofSize: columns >= 3 ? 15 : 13, weight: .bold), color: metric.color)
            if let footer = metric.footer {
                drawText(footer, rect: NSRect(x: card.minX + 12, y: blockY + labelH + innerGap + valueH + footerGap, width: card.width - 24, height: footerH), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
            }
        }

        let metricRows = Int(ceil(Double(metrics.count) / Double(columns)))
        let metricsBottom = rect.minY + 24 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * 10
        var leftColumnBottom = rect.minY + 112
        if let split = daySourceSplit(snapshot: snapshot, day: day) {
            drawDaySourceSplit(split, rect: NSRect(x: rect.minX + 18, y: rect.minY + 114, width: 274, height: 90))
            leftColumnBottom = rect.minY + daySourceSplitPanelExtent
        }
        let visibleModelRows = max(1, min(day.modelBreakdown.count, 5))
        let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        let modelRect = NSRect(
            x: rect.minX + 18,
            y: modelY,
            width: rect.width - 36,
            height: max(minimumModelHeight, rect.maxY - modelY - 18)
        )
        drawSelectedDayModels(day.modelBreakdown, rect: modelRect)
    }

    private func drawSelectedWeekPanel(snapshot: DetailsSnapshot, report: TokenReport, summary: ContributionWeekSummary, rect: NSRect) {
        drawPanel(rect)
        let weeks = contributionWeekColumns(in: report)
        let maxTotal = max(weeks.map { $0.total }.max() ?? 1, 1)
        let intensity = Double(summary.total) / Double(maxTotal)
        drawText(contributionWeekRangeLabel(summary), rect: NSRect(x: rect.minX + 18, y: rect.minY + 18, width: 274, height: 24), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawText(compact(summary.total), rect: NSRect(x: rect.minX + 18, y: rect.minY + 48, width: 260, height: 34), font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold), color: .systemGreen)
        let weekMeta = "\(summary.turns) \(t(.turns).lowercased())  |  \(contributionWeekLabel(.activeDays)) \(summary.activeDays)/7  |  \(Int(round(intensity * 100)))% \(t(.peakWeek))"
        drawText(weekMeta, rect: NSRect(x: rect.minX + 18, y: rect.minY + 90, width: 420, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))

        typealias WeekMetric = (title: String, value: String, color: NSColor, footer: String?)
        var metrics: [WeekMetric] = [
            (t(.input), compact(summary.usage.input), NSColor.systemGreen, nil),
            (t(.output), compact(summary.usage.output), NSColor.systemCyan, nil),
            (t(.cached), compact(summary.usage.cachedInput), NSColor.systemTeal, nil),
            (t(.fresh), compact(summary.usage.freshInput), NSColor.systemOrange, nil)
        ]
        if let planValue = contributionWeekPlanValue(summary) {
            metrics.append((contributionPlanAmountLabel(), displayMoney(planValue, source: selectedDetailsSource), NSColor.systemGreen, nil))
        }
        let apiEstimate = contributionWeekAPIEstimate(summary)
        if apiEstimate.hasPricedUsage {
            let footer = apiEstimate.coveragePercent < 99.5 ? "\(String(format: "%.0f%%", apiEstimate.coveragePercent)) \(t(.priced))" : nil
            metrics.append((t(.apiEquivalent), compactDisplayAPIMoney(apiEstimate.usdValue), accentTeal, footer))
        }
        let startX = rect.minX + 310
        let gap: CGFloat = 12
        let availableMetricWidth = max(180, rect.maxX - startX - 18)
        let columns: Int
        if metrics.count > 4 {
            columns = availableMetricWidth >= 360 ? 3 : 2
        } else {
            columns = availableMetricWidth >= 460 ? 4 : 2
        }
        let metricW = (availableMetricWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let metricH: CGFloat
        switch columns {
        case 4:
            metricH = 72
        case 3:
            metricH = 62
        default:
            metricH = 56
        }
        for (index, metric) in metrics.enumerated() {
            let col = index % columns
            let row = index / columns
            let card = NSRect(x: startX + CGFloat(col) * (metricW + gap), y: rect.minY + 24 + CGFloat(row) * (metricH + 10), width: metricW, height: metricH)
            NSColor.black.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: card, xRadius: 7, yRadius: 7).fill()
            let hasFooter = metric.footer != nil
            let labelH: CGFloat = 16
            let valueH: CGFloat = columns >= 3 ? 20 : 18
            let footerH: CGFloat = hasFooter ? 14 : 0
            let innerGap: CGFloat = columns >= 3 ? 3 : 1
            let footerGap: CGFloat = hasFooter ? 2 : 0
            let blockH = labelH + innerGap + valueH + footerGap + footerH
            let blockY = card.midY - blockH / 2
            drawText(metric.title, rect: NSRect(x: card.minX + 12, y: blockY, width: card.width - 24, height: labelH), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
            drawText(metric.value, rect: NSRect(x: card.minX + 12, y: blockY + labelH + innerGap, width: card.width - 24, height: valueH), font: .monospacedDigitSystemFont(ofSize: columns >= 3 ? 15 : 13, weight: .bold), color: metric.color)
            if let footer = metric.footer {
                drawText(footer, rect: NSRect(x: card.minX + 12, y: blockY + labelH + innerGap + valueH + footerGap, width: card.width - 24, height: footerH), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.54))
            }
        }

        let metricRows = Int(ceil(Double(metrics.count) / Double(columns)))
        let metricsBottom = rect.minY + 24 + CGFloat(metricRows) * metricH + CGFloat(max(0, metricRows - 1)) * 10
        var leftColumnBottom = rect.minY + 112
        if let split = weekSourceSplit(snapshot: snapshot, summary: summary) {
            drawDaySourceSplit(split, rect: NSRect(x: rect.minX + 18, y: rect.minY + 114, width: 274, height: 90))
            leftColumnBottom = rect.minY + daySourceSplitPanelExtent
        }
        let models = weekModelBreakdown(summary)
        let visibleModelRows = max(1, min(models.count, 5))
        let minimumModelHeight = 22 + CGFloat(visibleModelRows) * 22
        let modelY = max(leftColumnBottom, metricsBottom + 12)
        let modelRect = NSRect(
            x: rect.minX + 18,
            y: modelY,
            width: rect.width - 36,
            height: max(minimumModelHeight, rect.maxY - modelY - 18)
        )
        drawSelectedDayModels(models, rect: modelRect)
    }

    private func weekModelBreakdown(_ summary: ContributionWeekSummary) -> [ModelUsage] {
        var byName: [String: ModelUsage] = [:]
        for day in summary.days {
            for model in day.modelBreakdown {
                if var existing = byName[model.name] {
                    existing.usage.add(model.usage)
                    existing.events += model.events
                    existing.sessions += model.sessions
                    byName[model.name] = existing
                } else {
                    byName[model.name] = model
                }
            }
        }
        return byName.values.sorted { $0.usage.total > $1.usage.total }
    }

    private func weekSourceSplit(snapshot: DetailsSnapshot, summary: ContributionWeekSummary) -> (codex: Int64, claude: Int64)? {
        guard selectedDetailsSource == .all else { return nil }
        let codex = snapshot.codex.byDay
            .filter { $0.day >= summary.startDay && $0.day <= summary.endDay }
            .reduce(Int64(0)) { $0 + $1.usage.total }
        let claude = snapshot.claude.byDay
            .filter { $0.day >= summary.startDay && $0.day <= summary.endDay }
            .reduce(Int64(0)) { $0 + $1.usage.total }
        guard codex + claude > 0 else { return nil }
        return (codex, claude)
    }

    private var daySourceSplitPanelExtent: CGFloat { 216 }

    private func daySourceSplit(snapshot: DetailsSnapshot, day: DayUsage) -> (codex: Int64, claude: Int64)? {
        guard selectedDetailsSource == .all else { return nil }
        let codex = snapshot.codex.byDay.first { $0.day == day.day }?.usage.total ?? 0
        let claude = snapshot.claude.byDay.first { $0.day == day.day }?.usage.total ?? 0
        guard codex + claude > 0 else { return nil }
        return (codex, claude)
    }

    private func drawDaySourceSplit(_ split: (codex: Int64, claude: Int64), rect: NSRect) {
        let codexColor = NSColor(calibratedRed: 0.45, green: 0.50, blue: 1.00, alpha: 1.0)
        let claudeColor = NSColor(calibratedRed: 0.898, green: 0.420, blue: 0.278, alpha: 1.0)
        let total = Double(split.codex + split.claude)
        let codexShare = CGFloat(Double(split.codex) / total)

        drawText(t(.sourceSplit), rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))

        let ringSize: CGFloat = 64
        let lineWidth: CGFloat = 12
        let ringRect = NSRect(x: rect.minX, y: rect.minY + 22, width: ringSize, height: ringSize)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringSize / 2 - lineWidth / 2

        if codexShare >= 1 || codexShare <= 0 {
            let path = NSBezierPath(ovalIn: ringRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            path.lineWidth = lineWidth
            (codexShare >= 1 ? codexColor : claudeColor).setStroke()
            path.stroke()
        } else {
            let start: CGFloat = -90
            let boundary = start + 360 * codexShare
            for (from, to, color) in [(start, boundary, codexColor), (boundary, start + 360, claudeColor)] {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: false)
                path.lineWidth = lineWidth
                color.setStroke()
                path.stroke()
            }
        }

        let legendX = ringRect.maxX + 14
        let legendW = max(0, rect.maxX - legendX)
        let rows: [(name: String, value: Int64, share: CGFloat, color: NSColor)] = [
            ("Codex", split.codex, codexShare, codexColor),
            ("Claude", split.claude, 1 - codexShare, claudeColor)
        ]
        for (index, row) in rows.enumerated() {
            let y = ringRect.minY + 8 + CGFloat(index) * 28
            row.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: y + 4, width: 8, height: 8)).fill()
            drawText(row.name, rect: NSRect(x: legendX + 14, y: y, width: 70, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.78))
            let valueText = "\(compact(row.value)) · \(String(format: "%.1f%%", row.share * 100))"
            drawRight(valueText, rect: NSRect(x: legendX + 84, y: y, width: max(0, legendW - 84), height: 16), color: row.color, font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold))
        }
    }

    private func drawSelectedDayModels(_ models: [ModelUsage], rect: NSRect) {
        drawText(t(.models), rect: NSRect(x: rect.minX, y: rect.minY, width: 120, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        guard !models.isEmpty else {
            drawText(t(.noModelLabelForDay), rect: NSRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.46))
            return
        }

        let visible = Array(models.prefix(5))
        let maxTotal = max(visible.map { $0.usage.total }.max() ?? 1, 1)
        let costX = rect.maxX - 92
        let totalX = costX - 88
        let outputX = totalX - 88
        let inputX = outputX - 90
        let nameW = min(220, rect.width * 0.30)
        let barX = rect.minX + nameW + 18
        let barW = max(0, inputX - barX - 24)
        drawRight(t(.input), rect: NSRect(x: inputX, y: rect.minY, width: 80, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.output), rect: NSRect(x: outputX, y: rect.minY, width: 80, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.total), rect: NSRect(x: totalX, y: rect.minY, width: 82, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        drawRight(t(.apiEquivalent), rect: NSRect(x: costX, y: rect.minY, width: 92, height: 18), color: NSColor.white.withAlphaComponent(0.42), font: .systemFont(ofSize: 10, weight: .bold))
        for (index, model) in visible.enumerated() {
            let y = rect.minY + 22 + CGFloat(index) * 22
            guard y + 18 <= rect.maxY else { break }
            drawText(model.name, rect: NSRect(x: rect.minX, y: y, width: nameW, height: 12), font: .systemFont(ofSize: 10, weight: .semibold), color: .white)
            drawText("\(model.events) \(t(.events).lowercased())", rect: NSRect(x: rect.minX, y: y + 11, width: nameW, height: 11), font: .systemFont(ofSize: 8, weight: .semibold), color: NSColor.white.withAlphaComponent(0.42))

            if barW >= 18 {
                let bar = NSRect(x: barX, y: y + 6, width: barW, height: 6)
                NSColor.white.withAlphaComponent(0.07).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 4, yRadius: 4).fill()
                let totalRatio = CGFloat(Double(model.usage.total) / Double(maxTotal))
                let filledWidth = max(4, bar.width * totalRatio)
                let inputOutput = max(model.usage.input + model.usage.output, 1)
                let inputWidth = filledWidth * CGFloat(model.usage.input) / CGFloat(inputOutput)
                NSColor.systemGreen.withAlphaComponent(0.92).setFill()
                NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: inputWidth, height: bar.height), xRadius: 4, yRadius: 4).fill()
                NSColor.systemCyan.withAlphaComponent(0.92).setFill()
                NSBezierPath(roundedRect: NSRect(x: bar.minX + inputWidth, y: bar.minY, width: max(0, filledWidth - inputWidth), height: bar.height), xRadius: 4, yRadius: 4).fill()
            }

            drawRight(compact(model.usage.input), rect: NSRect(x: inputX, y: y + 1, width: 80, height: 16), color: .systemGreen)
            drawRight(compact(model.usage.output), rect: NSRect(x: outputX, y: y + 1, width: 80, height: 16), color: .systemCyan)
            drawRight(compact(model.usage.total), rect: NSRect(x: totalX, y: y + 1, width: 82, height: 16), color: .white)
            let modelCost = APICostEstimator.estimate(usage: model.usage, modelName: model.name)
            let costText = modelCost.hasPricedUsage ? compactDisplayAPIMoney(modelCost.usdValue) : "—"
            drawRight(costText, rect: NSRect(x: costX, y: y + 1, width: 92, height: 16), color: modelCost.hasPricedUsage ? accentTeal : NSColor.white.withAlphaComponent(0.38))
        }
    }

    private func drawSettingsPage(content: NSRect) {
        numberUnitOptionRects.removeAll()
        quotaDisplayStyleRects.removeAll()
        codexHomeRingMetricRects.removeAll()
        claudeHomeRingMetricRects.removeAll()
        settingsSubsectionRects.removeAll()
        chooseLogFolderRect = nil
        resetLogFolderRect = nil
        openLogFolderRect = nil
        chooseCodexAPISourceRect = nil
        resetCodexAPISourceRect = nil
        openCodexAPISourceRect = nil

        let rect = settingsPanelRect(in: content)
        drawSettingsSubnavigation(in: rect)

        let page = settingsPageRect(in: rect)
        drawSettingsPageHeader(in: page)
        switch selectedSettingsSubsection {
        case .appearance:
            drawAppearanceSettings(in: page)
        case .data:
            drawDataSettings(in: page)
        case .quota:
            drawQuotaSettings(in: page)
        case .system:
            drawSystemSettings(in: page)
        }
    }

    private func drawSettingsSubnavigation(in rect: NSRect) {
        let navRect = NSRect(x: rect.minX, y: rect.minY + 2, width: settingsSubnavWidth, height: rect.height - 4)
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: rect.minX + settingsSubnavWidth + 16, y: rect.minY + 2, width: 1, height: rect.height - 4).fill()

        let title = AppLanguage.current == .english ? "Settings" : (AppLanguage.current == .japanese ? "設定分類" : "设置分类")
        drawText(title, rect: NSRect(x: navRect.minX, y: navRect.minY, width: navRect.width - 8, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: NSColor.white.withAlphaComponent(0.46))

        let itemHeight: CGFloat = 52
        let gap: CGFloat = 10
        var y = navRect.minY + 34
        for subsection in SettingsSubsection.allCases {
            let itemRect = NSRect(x: navRect.minX, y: y, width: navRect.width - 12, height: itemHeight)
            settingsSubsectionRects[subsection] = itemRect
            let selected = subsection == selectedSettingsSubsection
            (selected ? accentBlue.withAlphaComponent(0.70) : NSColor.clear).setFill()
            NSBezierPath(roundedRect: itemRect, xRadius: 8, yRadius: 8).fill()
            let textColor = selected ? NSColor.white : NSColor.white.withAlphaComponent(0.76)
            drawSymbolIcon(subsection.symbolName, in: NSRect(x: itemRect.minX + 12, y: itemRect.minY + 18, width: 18, height: 18), color: textColor.withAlphaComponent(selected ? 0.96 : 0.58), pointSize: 12)
            drawText(subsection.title, rect: NSRect(x: itemRect.minX + 38, y: itemRect.minY + 10, width: itemRect.width - 48, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: textColor)
            drawText(subsection.subtitle, rect: NSRect(x: itemRect.minX + 38, y: itemRect.minY + 30, width: itemRect.width - 48, height: 16), font: .systemFont(ofSize: 9, weight: .semibold), color: textColor.withAlphaComponent(selected ? 0.64 : 0.42))
            y += itemHeight + gap
        }
    }

    private func drawSettingsPageHeader(in page: NSRect) {
        drawText(selectedSettingsSubsection.title, rect: NSRect(x: page.minX, y: page.minY, width: page.width, height: 24), font: .systemFont(ofSize: 18, weight: .bold), color: .white)
        drawText(selectedSettingsSubsection.subtitle, rect: NSRect(x: page.minX, y: page.minY + 28, width: page.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSRect(x: page.minX, y: page.minY + 56, width: page.width, height: 1).fill()
    }

    private func drawAppearanceSettings(in page: NSRect) {
        let labelW = min(220, page.width * 0.35)
        let optionX = page.minX + labelW + 22
        let optionW = page.maxX - optionX

        drawSettingText(title: t(.interfaceLanguage), hint: t(.languageHint), x: page.minX, y: page.minY + 76, width: labelW)

        drawSettingText(title: t(.displayCurrency), hint: t(.displayCurrencyHint), x: page.minX, y: page.minY + 152, width: labelW)

        drawSettingText(title: t(.numberUnits), hint: t(.numberUnitsHint), x: page.minX, y: page.minY + 228, width: labelW)
        let unitStyles = NumberUnitStyle.availableCases
        let unitRects = segmentedRects(count: unitStyles.count, in: NSRect(x: optionX, y: page.minY + 222, width: optionW, height: 36), preferredWidth: 132)
        for (index, style) in unitStyles.enumerated() {
            let optionRect = unitRects[index]
            numberUnitOptionRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: style == NumberUnitStyle.effective)
        }

        let statusTextW = max(labelW, statusPrimaryMetricPopup.frame.minX - page.minX - 12)
        drawSettingText(title: t(.statusBarMetricOne), hint: t(.statusDisplayHint), x: page.minX, y: page.minY + 306, width: statusTextW)
        drawSettingText(title: t(.statusBarMetricTwo), hint: "", x: page.minX, y: page.minY + 376, width: statusTextW)
    }

    private func drawDataSettings(in page: NSRect) {
        drawSettingText(title: t(.logFolder), hint: t(.logFolderHint), x: page.minX, y: page.minY + 76, width: page.width)
        let logButtonY = page.minY + 128
        let buttonGap: CGFloat = 12
        let openW: CGFloat = 78
        let resetW: CGFloat = 76
        let chooseW: CGFloat = 108
        let buttonTotalW = openW + resetW + chooseW + buttonGap * 2
        let buttonStartX = page.maxX - buttonTotalW
        openLogFolderRect = NSRect(x: buttonStartX, y: logButtonY, width: openW, height: 34)
        resetLogFolderRect = NSRect(x: openLogFolderRect!.maxX + buttonGap, y: logButtonY, width: resetW, height: 34)
        chooseLogFolderRect = NSRect(x: resetLogFolderRect!.maxX + buttonGap, y: logButtonY, width: chooseW, height: 34)
        let pathRect = NSRect(x: page.minX, y: logButtonY, width: max(120, buttonStartX - page.minX - 16), height: 34)
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: pathRect, xRadius: 7, yRadius: 7).fill()
        drawTruncatedText(AppSettings.logFolderDisplayPath, rect: pathRect.insetBy(dx: 12, dy: 9), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
        drawSmallButton(t(.logs), rect: openLogFolderRect!, emphasized: false)
        drawSmallButton(t(.logFolderDefault), rect: resetLogFolderRect!, emphasized: false)
        drawSmallButton(t(.logFolderChoose), rect: chooseLogFolderRect!, emphasized: true)

        drawSettingText(title: t(.codexAPISources), hint: t(.codexAPISourcesHint), x: page.minX, y: page.minY + 186, width: page.width)
        let apiButtonY = page.minY + 238
        openCodexAPISourceRect = NSRect(x: buttonStartX, y: apiButtonY, width: openW, height: 34)
        resetCodexAPISourceRect = NSRect(x: openCodexAPISourceRect!.maxX + buttonGap, y: apiButtonY, width: resetW, height: 34)
        chooseCodexAPISourceRect = NSRect(x: resetCodexAPISourceRect!.maxX + buttonGap, y: apiButtonY, width: chooseW, height: 34)
        let apiPathRect = NSRect(x: page.minX, y: apiButtonY, width: max(120, buttonStartX - page.minX - 16), height: 34)
        NSColor.black.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: apiPathRect, xRadius: 7, yRadius: 7).fill()
        drawTruncatedText(AppSettings.codexAPISourceDisplayPath, rect: apiPathRect.insetBy(dx: 12, dy: 9), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
        drawSmallButton(t(.logFolderOpen), rect: openCodexAPISourceRect!, emphasized: false)
        drawSmallButton(t(.logFolderDefault), rect: resetCodexAPISourceRect!, emphasized: false)
        drawSmallButton(t(.codexAPISourcesChoose), rect: chooseCodexAPISourceRect!, emphasized: true)

        drawSwitchSetting(title: t(.profileAPITotals), hint: t(.profileAPITotalsHint), switchFrame: profileAPITotalsSwitch.frame, page: page, y: page.minY + 320)
        drawSwitchSetting(title: t(.claudeActiveRefresh), hint: t(.claudeActiveRefreshHint), switchFrame: claudeActiveQuotaRefreshSwitch.frame, page: page, y: page.minY + 390)
    }

    private func drawQuotaSettings(in page: NSRect) {
        let labelW = min(220, page.width * 0.34)
        let optionX = page.minX + labelW + 22
        let optionW = page.maxX - optionX

        drawSettingText(title: t(.quotaDisplayStyle), hint: t(.quotaDisplayHint), x: page.minX, y: page.minY + 76, width: labelW)
        let quotaStyleRects = segmentedRects(count: QuotaDisplayStyle.allCases.count, in: NSRect(x: optionX, y: page.minY + 70, width: optionW, height: 36), preferredWidth: 122)
        for (index, style) in QuotaDisplayStyle.allCases.enumerated() {
            let optionRect = quotaStyleRects[index]
            quotaDisplayStyleRects[style] = optionRect
            drawSelectablePill(style.title, rect: optionRect, selected: style == QuotaDisplayStyle.current)
        }

        drawSettingText(title: t(.codexHomeRing), hint: t(.quotaHomeRingHint), x: page.minX, y: page.minY + 150, width: labelW)
        drawSettingText(title: t(.claudeHomeRing), hint: "", x: page.minX, y: page.minY + 220, width: labelW)
        let homeMetricRects = segmentedRects(count: HomeQuotaRingMetric.allCases.count, in: NSRect(x: optionX, y: page.minY + 144, width: optionW, height: 36), preferredWidth: 122)
        let claudeMetricRects = segmentedRects(count: HomeQuotaRingMetric.allCases.count, in: NSRect(x: optionX, y: page.minY + 214, width: optionW, height: 36), preferredWidth: 122)
        for (index, metric) in HomeQuotaRingMetric.allCases.enumerated() {
            let codexRect = homeMetricRects[index]
            codexHomeRingMetricRects[metric] = codexRect
            drawSelectablePill(metric.title, rect: codexRect, selected: metric == AppSettings.codexHomeRingMetric)
            let claudeRect = claudeMetricRects[index]
            claudeHomeRingMetricRects[metric] = claudeRect
            drawSelectablePill(metric.title, rect: claudeRect, selected: metric == AppSettings.claudeHomeRingMetric)
        }

        drawSwitchSetting(title: t(.showCodexStatus), hint: codexStatusSettingHint, switchFrame: showCodexStatusSwitch.frame, page: page, y: page.minY + 306)
        drawSwitchSetting(title: t(.quotaWarnings), hint: t(.quotaWarningsHint), switchFrame: quotaWarningsSwitch.frame, page: page, y: page.minY + 390)
    }

    private func drawSystemSettings(in page: NSRect) {
        drawSwitchSetting(title: t(.launchAtLogin), hint: t(.launchAtLoginHint), switchFrame: launchAtLoginSwitch.frame, page: page, y: page.minY + 76)
    }

    private func drawSettingText(title: String, hint: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        drawText(title, rect: NSRect(x: x, y: y, width: width, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        if !hint.isEmpty {
            drawMultilineText(hint, rect: NSRect(x: x, y: y + 23, width: width, height: 34), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
        }
    }

    private func drawSwitchSetting(title: String, hint: String, switchFrame: NSRect, page: NSRect, y: CGFloat) {
        let textW = max(120, switchFrame.minX - page.minX - 12)
        drawText(title, rect: NSRect(x: page.minX, y: y, width: textW, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
        drawMultilineText(hint, rect: NSRect(x: page.minX, y: y + 23, width: textW, height: 32), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
    }

    private func segmentedRects(count: Int, in rect: NSRect, preferredWidth: CGFloat) -> [NSRect] {
        guard count > 0 else { return [] }
        let gap: CGFloat = 10
        let availableWidth = rect.width - gap * CGFloat(max(0, count - 1))
        let optionWidth = min(preferredWidth, max(82, availableWidth / CGFloat(count)))
        let totalWidth = optionWidth * CGFloat(count) + gap * CGFloat(max(0, count - 1))
        let startX = rect.maxX - totalWidth
        return (0..<count).map { index in
            NSRect(x: startX + CGFloat(index) * (optionWidth + gap), y: rect.minY, width: optionWidth, height: rect.height)
        }
    }

    private var codexStatusSettingHint: String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese: return "可用时在弹窗里显示 OpenAI Codex 服务状态。"
        case .japanese: return "利用可能な場合、ポップオーバーに Codex サービス状態を表示します。"
        default: return "Shows the OpenAI Codex service chip in the popover when available."
        }
    }

    private var costUsedColor: NSColor {
        accentTeal
    }

    private var costRemainingColor: NSColor {
        NSColor(calibratedRed: 0.52, green: 0.58, blue: 0.69, alpha: 1.0)
    }

    private var costRemainingMutedColor: NSColor {
        NSColor(calibratedRed: 0.168, green: 0.196, blue: 0.244, alpha: 1.0)
    }

    private func costUsedColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costUsedColor }
        return accentAmber
    }

    private func costRemainingColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costRemainingColor }
        return costRemainingColor.withAlphaComponent(0.78)
    }

    private func costRemainingMutedColor(for row: CostPeriodRow) -> NSColor {
        guard row.isShortCycle else { return costRemainingMutedColor }
        return costRemainingMutedColor.withAlphaComponent(0.95)
    }

    private func drawCurrencyOptions(rect: NSRect, y: CGFloat, selected: CurrencyCode, store: inout [CurrencyCode: NSRect]) {
        let optionW: CGFloat = 70
        let optionH: CGFloat = 32
        let gap: CGFloat = 8
        let startX = rect.maxX - 16 - optionW * CGFloat(CurrencyCode.allCases.count) - gap * CGFloat(CurrencyCode.allCases.count - 1)
        for (index, currency) in CurrencyCode.allCases.enumerated() {
            let optionRect = NSRect(x: startX + CGFloat(index) * (optionW + gap), y: y, width: optionW, height: optionH)
            store[currency] = optionRect
            drawSelectablePill(currency.rawValue, rect: optionRect, selected: currency == selected)
        }
    }

    private func drawCostHistoryBars(rows: [CostPeriodRow], rect: NSRect) {
        costHistoryRows = rows
        guard !rows.isEmpty else {
            drawText(t(.planCostUnavailable), rect: NSRect(x: rect.minX, y: rect.minY + 48, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let legendY = rect.minY
        drawText(t(.used), rect: NSRect(x: rect.minX, y: legendY, width: 48, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.78))
        costUsedColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 54, y: legendY + 4, width: 18, height: 8), xRadius: 4, yRadius: 4).fill()
        drawText(t(.remaining), rect: NSRect(x: rect.minX + 88, y: legendY, width: 58, height: 16), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
        costRemainingColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 154, y: legendY + 4, width: 18, height: 8), xRadius: 4, yRadius: 4).fill()

        let chart = NSRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: rect.height - 44)
        let maxValue = max(rows.map { max($0.usedValue + $0.remainingValue, $0.budgetValue) }.max() ?? 1, 1)
        let barWidth = max(34, min(58, (chart.width - CGFloat(rows.count - 1) * 12) / CGFloat(max(rows.count, 1))))
        let gap = max(12, (chart.width - barWidth * CGFloat(rows.count)) / CGFloat(max(rows.count - 1, 1)))
        for (index, row) in rows.enumerated() {
            let x = chart.minX + CGFloat(index) * (barWidth + gap)
            let totalHeight = chart.height - 28
            let usedHeight = totalHeight * CGFloat(row.usedValue / maxValue)
            let remainingHeight = totalHeight * CGFloat(row.remainingValue / maxValue)
            let baseY = chart.maxY - 10
            let fullBarRect = NSRect(x: x, y: baseY - usedHeight - remainingHeight, width: barWidth, height: max(6, usedHeight + remainingHeight))
            costHistoryBarRects[index] = fullBarRect.insetBy(dx: -4, dy: -4)

            costRemainingMutedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: baseY - totalHeight, width: barWidth, height: totalHeight), xRadius: 6, yRadius: 6).fill()
            if remainingHeight > 0 {
                costRemainingColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: baseY - usedHeight - remainingHeight, width: barWidth, height: remainingHeight), xRadius: 5, yRadius: 5).fill()
            }
            costUsedColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: baseY - usedHeight, width: barWidth, height: max(6, usedHeight)), xRadius: 5, yRadius: 5).fill()

            if hoveredCostHistoryIndex == index {
                NSColor.white.withAlphaComponent(0.22).setStroke()
                let focusRect = fullBarRect.insetBy(dx: -3, dy: -3)
                let focusPath = NSBezierPath(roundedRect: focusRect, xRadius: 8, yRadius: 8)
                focusPath.lineWidth = 1.5
                focusPath.stroke()
            }

            drawCentered(row.label, rect: NSRect(x: x - 8, y: chart.maxY + 2, width: barWidth + 16, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.46))
        }
    }

    private func drawCostRings(rows: [CostPeriodRow], rect: NSRect, year: Int) {
        costHistoryRows = rows
        guard !rows.isEmpty else {
            drawText(t(.noUsage), rect: NSRect(x: rect.minX, y: rect.minY + 32, width: rect.width, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let cacheKey = costRingCacheKey(rows: rows, rect: rect, year: year)
        if costRingCache?.key != cacheKey {
            costRingCache = CostRingCache(key: cacheKey, image: renderCostRingsImage(rows: rows, rect: rect, year: year))
        }
        costRingCache?.image.draw(in: rect)

        let layout = costRingLayout(rows: rows, rect: rect)
        costHistoryBarRects.removeAll(keepingCapacity: true)
        for (index, cell) in layout.cells.enumerated() {
            costHistoryBarRects[index] = cell.insetBy(dx: -4, dy: -4)
        }

        if let hoveredCostHistoryIndex,
           layout.cells.indices.contains(hoveredCostHistoryIndex) {
            drawCostRing(row: rows[hoveredCostHistoryIndex], rect: layout.cells[hoveredCostHistoryIndex], showLabel: false, highlighted: true)
        }
    }

    private func costRingLayout(rows: [CostPeriodRow], rect: NSRect) -> (cells: [NSRect], legendRect: NSRect, footerRect: NSRect, titleRect: NSRect) {
        let columns = min(13, max(rows.count, 1))
        let rowCount = Int(ceil(Double(rows.count) / Double(columns)))
        let ringGapX: CGFloat = 12
        let ringGapY: CGFloat = rowCount > 4 ? 10 : 18
        let availableWidth = rect.width
        let availableHeight = rect.height - 36
        let ringSize = floor(min(
            (availableWidth - CGFloat(columns - 1) * ringGapX) / CGFloat(columns),
            (availableHeight - CGFloat(max(rowCount - 1, 0)) * ringGapY) / CGFloat(max(rowCount, 1))
        ))
        let totalGridWidth = CGFloat(columns) * ringSize + CGFloat(columns - 1) * ringGapX
        let startX = rect.minX + max(0, (rect.width - totalGridWidth) / 2)
        let totalGridHeight = CGFloat(rowCount) * ringSize + CGFloat(max(rowCount - 1, 0)) * ringGapY
        let startY = rect.minY + max(20, (rect.height - totalGridHeight) / 2)

        var cells: [NSRect] = []
        cells.reserveCapacity(rows.count)
        for index in rows.indices {
            let gridRow = index / columns
            let gridColumn = index % columns
            let cell = NSRect(
                x: startX + CGFloat(gridColumn) * (ringSize + ringGapX),
                y: startY + CGFloat(gridRow) * (ringSize + ringGapY),
                width: ringSize,
                height: ringSize
            )
            cells.append(cell)
        }

        return (
            cells: cells,
            legendRect: NSRect(x: rect.minX + 96, y: rect.minY, width: 260, height: 16),
            footerRect: NSRect(x: rect.minX, y: rect.maxY - 18, width: rect.width, height: 14),
            titleRect: NSRect(x: rect.minX, y: rect.minY, width: 86, height: 16)
        )
    }

    private func renderCostRingsImage(rows: [CostPeriodRow], rect: NSRect, year: Int) -> NSImage {
        let image = NSImage(size: rect.size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        let localRect = NSRect(origin: .zero, size: rect.size)
        let translatedRows = rows
        let layout = costRingLayout(rows: translatedRows, rect: localRect)
        drawText(String(year), rect: layout.titleRect, font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: NSColor.white.withAlphaComponent(0.52))
        drawCostRingLegend(rect: layout.legendRect)
        for (index, cell) in layout.cells.enumerated() {
            drawCostRing(row: translatedRows[index], rect: cell, showLabel: false, highlighted: false)
        }
        drawRight(t(.costHistoryHint), rect: layout.footerRect, color: NSColor.white.withAlphaComponent(0.34), font: .systemFont(ofSize: 10, weight: .medium))
        return image
    }

    private func costRingCacheKey(rows: [CostPeriodRow], rect: NSRect, year: Int) -> String {
        let sizePart = "\(AppLanguage.current.rawValue):\(Int(rect.width.rounded()))x\(Int(rect.height.rounded())):\(year)"
        let rowsPart = rows.map {
            [
                $0.label,
                $0.title,
                $0.subtitle ?? "",
                String(format: "%.4f", $0.usedValue),
                String(format: "%.4f", $0.remainingValue),
                String(format: "%.4f", $0.budgetValue),
                String(format: "%.4f", $0.apiEquivalentUSD ?? -1),
                String(format: "%.2f", $0.apiEquivalentCoveragePercent),
                $0.hasData ? "1" : "0",
                $0.isFuture ? "1" : "0",
                $0.isShortCycle ? "1" : "0",
                "\($0.cycleIndex)"
            ].joined(separator: "|")
        }.joined(separator: ";")
        return sizePart + "#" + rowsPart
    }

    private func drawCostRingLegend(rect: NSRect) {
        let items: [(String, NSColor)] = [
            (t(.used), costUsedColor),
            (t(.remaining), costRemainingColor),
            (t(.noUsage), NSColor.white.withAlphaComponent(0.20)),
            (t(.future), NSColor.white.withAlphaComponent(0.10))
        ]
        var x = rect.minX
        for item in items {
            item.1.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.minY + 4, width: 8, height: 8)).fill()
            drawText(item.0, rect: NSRect(x: x + 12, y: rect.minY, width: 56, height: rect.height), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.44))
            x += 70
        }
    }

    private func drawCostRing(row: CostPeriodRow, rect: NSRect, showLabel: Bool, highlighted: Bool) {
        let labelHeight: CGFloat = showLabel ? 14 : 0
        let ringRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - labelHeight)
        let availableSide = max(0, min(ringRect.width, ringRect.height))
        let outerPadding = min(4, max(2, availableSide * 0.12))
        let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = max(2, availableSide / 2 - outerPadding)
        let preferredLineWidth = max(2.2, availableSide * 0.14)
        let lineWidth: CGFloat = min(8, min(preferredLineWidth, max(2, radius * 0.45)))
        let start = -CGFloat.pi / 2
        let end = start + CGFloat.pi * 2
        let fullCircleRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let baseColor = row.isFuture ? NSColor.white.withAlphaComponent(0.055) : costRemainingMutedColor(for: row).withAlphaComponent(row.hasData ? 0.62 : 0.50)

        fillDonut(in: fullCircleRect, thickness: lineWidth, color: baseColor)

        if row.hasData {
            let progress = min(1.0, max(0.0, row.usedPercent / 100))
            let usedEnd = start + CGFloat.pi * 2 * CGFloat(progress)
            if progress < 0.999 {
                fillDonutSegment(
                    center: center,
                    outerRadius: radius,
                    thickness: lineWidth,
                    startAngle: usedEnd,
                    endAngle: end,
                    color: costRemainingColor(for: row).withAlphaComponent(0.58)
                )
            }
            let ringColor: NSColor = row.usedPercent > 100 ? accentAmber : costUsedColor(for: row)
            if progress >= 0.999 {
                fillDonut(in: fullCircleRect, thickness: lineWidth, color: ringColor)
            } else if progress > 0.001 {
                fillDonutSegment(
                    center: center,
                    outerRadius: radius,
                    thickness: lineWidth,
                    startAngle: start,
                    endAngle: usedEnd,
                    color: ringColor
                )
            }
        } else if row.isFuture {
            fillDonut(in: fullCircleRect, thickness: lineWidth, color: NSColor.white.withAlphaComponent(0.075))
        } else {
            fillDonut(in: fullCircleRect, thickness: max(3, lineWidth * 0.72), color: NSColor.white.withAlphaComponent(0.18))
        }

        let ringColor: NSColor = row.usedPercent > 100 ? accentAmber : costUsedColor(for: row)

        if highlighted {
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: ringRect.insetBy(dx: 0.5, dy: 0.5)).fill()
            ringColor.setStroke()
            let focus = NSBezierPath(ovalIn: ringRect.insetBy(dx: 1.5, dy: 1.5))
            focus.lineWidth = 1.5
            focus.stroke()
        }

        if showLabel {
            drawCentered(row.label, rect: NSRect(x: rect.minX - 4, y: rect.maxY - 12, width: rect.width + 8, height: 12), font: .monospacedDigitSystemFont(ofSize: 9, weight: .semibold), color: NSColor.white.withAlphaComponent(row.isFuture ? 0.22 : 0.46))
        }
    }

    private func drawCostHistoryTooltip() {
        guard let hoveredCostHistoryIndex,
              costHistoryRows.indices.contains(hoveredCostHistoryIndex),
              let anchorRect = costHistoryBarRects[hoveredCostHistoryIndex] else {
            return
        }
        let row = costHistoryRows[hoveredCostHistoryIndex]
        let costSource = selectedDetailsSource
        var lines = costHistoryTooltipLines(for: row, source: costSource)
        if let apiEquivalentUSD = row.apiEquivalentUSD {
            let apiTitle = row.apiEquivalentCoveragePercent > 0 && row.apiEquivalentCoveragePercent < 99.5
                ? "\(t(.apiEquivalent)) \(String(format: "%.0f%%", row.apiEquivalentCoveragePercent))"
                : t(.apiEquivalent)
            let apiIndex = max(0, lines.count - 1)
            lines.insert((apiTitle, displayAPIMoney(apiEquivalentUSD, source: costSource), accentTeal), at: apiIndex)
        }

        let width: CGFloat = costSource == .all ? 354 : 326
        let titleHeight: CGFloat = row.subtitle == nil ? 24 : 38
        let rowHeight: CGFloat = 20
        let height: CGFloat = titleHeight + 18 + CGFloat(lines.count) * rowHeight
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.minY - height - 12)
        var rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        if visibleCostControlFrames.contains(where: { $0.intersects(rect) }) {
            origin.y = anchorRect.maxY + 12
            rect.origin = origin
        }
        if origin.y < bounds.minY + 12 {
            origin.y = anchorRect.maxY + 12
        }
        origin.x = max(bounds.minX + 12, min(origin.x, bounds.maxX - width - 12))
        origin.y = max(bounds.minY + 12, min(origin.y, bounds.maxY - height - 12))

        rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(row.title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), color: .white)
        if let subtitle = row.subtitle {
            drawText(subtitle, rect: NSRect(x: rect.minX + 12, y: rect.minY + 26, width: rect.width - 24, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.45))
        }

        let startY = rect.minY + titleHeight + 6
        let labelWidth: CGFloat = costSource == .all ? 128 : 108
        let valueX = rect.minX + labelWidth + 30
        let valueWidth = rect.maxX - valueX - 14
        for (index, line) in lines.enumerated() {
            let y = startY + CGFloat(index) * rowHeight
            drawText(line.0, rect: NSRect(x: rect.minX + 12, y: y, width: labelWidth, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.62))
            drawRight(line.1, rect: NSRect(x: valueX, y: y, width: valueWidth, height: 16), color: line.2, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
    }

    private func costHistoryTooltipLines(for row: CostPeriodRow, source: QuotaViewOption) -> [(String, String, NSColor)] {
        guard source == .all, let snapshot else {
            return [
                (t(.used), displayMoney(row.usedValue, source: source), costUsedColor(for: row)),
                (t(.remaining), displayMoney(row.remainingValue, source: source), costRemainingColor(for: row)),
                (t(.budget), displayMoney(row.budgetValue, source: source), .white),
                (t(.usageRate), String(format: "%.1f%%", row.usedPercent), NSColor.white.withAlphaComponent(0.82))
            ]
        }

        let codex = platformCostHistoryValues(matching: row, source: .codex, snapshot: snapshot)
        let claude = platformCostHistoryValues(matching: row, source: .claude, snapshot: snapshot)
        return [
            (platformCostHistoryLabel(source: .codex, remaining: false), displayMoney(codex.usedValue, source: .codex), costUsedColor),
            (platformCostHistoryLabel(source: .codex, remaining: true), displayMoney(codex.remainingValue, source: .codex), costRemainingColor),
            (platformCostHistoryLabel(source: .claude, remaining: false), displayMoney(claude.usedValue, source: .claude), accentAmber),
            (platformCostHistoryLabel(source: .claude, remaining: true), displayMoney(claude.remainingValue, source: .claude), costRemainingColor.withAlphaComponent(0.78)),
            (t(.budget), displayMoney(row.budgetValue, source: source), .white),
            (t(.usageRate), String(format: "%.1f%%", row.usedPercent), NSColor.white.withAlphaComponent(0.82))
        ]
    }

    private func platformCostHistoryValues(matching row: CostPeriodRow, source: QuotaViewOption, snapshot: DetailsSnapshot) -> (usedValue: Double, remainingValue: Double) {
        let rows = weeklySpendRows(
            report: sourceReport(for: snapshot, source: source),
            limit: source == .claude ? nil : costEstimateLimit(from: snapshot.liveLimits),
            year: selectedCostYear,
            quotaReferenceReport: source == .claude ? nil : snapshot.costReferenceReport,
            monthlyCost: AppSettings.monthlyPlanCost(for: source),
            paymentStartDay: AppSettings.paymentStartDay(for: source)
        )
        let match = rows.first { $0.label == row.label && $0.cycleIndex == row.cycleIndex && $0.title == row.title }
            ?? rows.first { $0.label == row.label && $0.cycleIndex == row.cycleIndex }
            ?? rows.first { $0.label == row.label && $0.cycleIndex == 0 }
            ?? rows.first { $0.label == row.label }
        if let match {
            return (match.usedValue, match.remainingValue)
        }
        return (0, AppSettings.monthlyPlanCost(for: source) * 12 / 52)
    }

    private func platformCostHistoryLabel(source: QuotaViewOption, remaining: Bool) -> String {
        let name = source == .codex ? "Codex" : "Claude"
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "\(name) \(remaining ? "剩余" : "花费")"
        default:
            return "\(name) \(remaining ? "remaining" : "spent")"
        }
    }

    private func drawCostOverviewInfoTooltip() {
        guard let info = hoveredCostOverviewInfo,
              let anchorRect = costOverviewInfoRects[info] else {
            return
        }
        let width: CGFloat = 330
        let height: CGFloat = 86
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.maxY + 10)
        if origin.y + height > bounds.maxY - 12 {
            origin.y = anchorRect.minY - height - 10
        }
        origin.x = max(bounds.minX + 12, min(origin.x, bounds.maxX - width - 12))
        origin.y = max(bounds.minY + 12, min(origin.y, bounds.maxY - height - 12))

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(info.title, rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        drawMultilineText(info.hint, rect: NSRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 42), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.62))
    }

    private func drawDayValueInfoTooltip() {
        guard isHoveringDayValueInfo, let anchorRect = dayValueInfoRect else { return }
        let width: CGFloat = 300
        let height: CGFloat = 74
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.maxY + 8)
        if origin.x < bounds.minX + 12 {
            origin.x = bounds.minX + 12
        }
        if origin.x + width > bounds.maxX - 12 {
            origin.x = bounds.maxX - width - 12
        }
        if origin.y + height > bounds.maxY - 12 {
            origin.y = anchorRect.minY - height - 8
        }
        origin.y = max(bounds.minY + 12, origin.y)

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(t(.dayValue), rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        drawMultilineText(t(.dayValueHint), rect: NSRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 34), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
    }

    private func drawProfileAPIInfoTooltip() {
        guard isHoveringProfileAPIInfo, let anchorRect = profileAPIInfoRect else { return }
        let width: CGFloat = 340
        let height: CGFloat = 82
        var origin = CGPoint(x: anchorRect.midX - width / 2, y: anchorRect.maxY + 8)
        if origin.x < bounds.minX + 12 {
            origin.x = bounds.minX + 12
        }
        if origin.x + width > bounds.maxX - 12 {
            origin.x = bounds.maxX - width - 12
        }
        if origin.y + height > bounds.maxY - 12 {
            origin.y = anchorRect.minY - height - 8
        }
        origin.y = max(bounds.minY + 12, origin.y)

        let rect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        border.lineWidth = 1
        border.stroke()

        drawText(t(.profileAPITotals), rect: NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .white)
        drawMultilineText(t(.profileAPITotalsHint), rect: NSRect(x: rect.minX + 12, y: rect.minY + 30, width: rect.width - 24, height: 42), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
    }

    private func drawAboutPage(content: NSRect) {
        let rect = NSRect(x: content.minX, y: content.minY + 78, width: content.width, height: 208)
        drawPanel(rect)
        drawText(t(.definitions), rect: NSRect(x: rect.minX + 16, y: rect.minY + 16, width: rect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        let rows = [
            (t(.all), t(.allDescription)),
            (t(.codex), t(.codexDescription)),
            (t(.claude), t(.claudeDescription)),
            (t(.cacheHit), t(.cacheHitDescription))
        ]
        for (index, row) in rows.enumerated() {
            let y = rect.minY + 52 + CGFloat(index) * 38
            drawText(row.0, rect: NSRect(x: rect.minX + 16, y: y, width: 92, height: 20), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(row.1, rect: NSRect(x: rect.minX + 116, y: y, width: rect.width - 132, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.56))
        }

        let sourceRect = NSRect(x: content.minX, y: rect.maxY + 16, width: content.width, height: 196)
        drawPanel(sourceRect)
        drawText(t(.dataSource), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 16, width: sourceRect.width - 32, height: 22), font: .systemFont(ofSize: 16, weight: .bold), color: .white)
        drawText(t(.dataSourceLine1), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 52, width: sourceRect.width - 32, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.58))
        drawMultilineText(t(.dataSourceLine2), rect: NSRect(x: sourceRect.minX + 16, y: sourceRect.minY + 80, width: sourceRect.width - 32, height: 104), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.6))
    }

    /// Pads sparse "past year" day data to a full 53-week range ending at the
    /// current calendar week's last slot, so the grid keeps fixed weekday rows
    /// while future dates stay blank.
    private func paddedContributionDays(_ days: [DayUsage]) -> [DayUsage] {
        let totalDays = 53 * 7
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        let windowEnd = contributionWeekEnd(for: today, calendar: calendar)
        guard let windowStart = calendar.date(byAdding: .day, value: -(totalDays - 1), to: windowEnd) else {
            return days
        }
        var byKey: [String: DayUsage] = [:]
        for day in days {
            guard let date = formatter.date(from: day.day),
                  date >= windowStart,
                  date <= windowEnd else { continue }
            byKey[day.day] = day
        }
        var padded: [DayUsage] = []
        padded.reserveCapacity(totalDays)
        for offset in stride(from: totalDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: windowEnd) else { continue }
            let key = formatter.string(from: date)
            padded.append(byKey[key] ?? DayUsage(day: key, usage: Usage(), turns: 0))
        }
        return padded
    }

    private func contributionWeekEnd(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return day
        }
        return weekEnd
    }

    private func isFutureContributionDay(_ day: String, formatter: DateFormatter, calendar: Calendar, today: Date) -> Bool {
        guard let date = formatter.date(from: day) else { return false }
        return calendar.compare(date, to: today, toGranularity: .day) == .orderedDescending
    }

    /// Aggregates the padded contribution days into the same 7-day columns the
    /// grid renders, so week selection maps 1:1 to what the user clicked.
    private func contributionWeekColumns(in report: TokenReport) -> [ContributionWeekSummary] {
        let days = paddedContributionDays(report.byDay)
        guard !days.isEmpty else { return [] }
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        var result: [ContributionWeekSummary] = []
        var index = 0
        while index < days.count {
            let slice = Array(days[index..<min(index + 7, days.count)])
            let visibleDays = slice.filter { !isFutureContributionDay($0.day, formatter: formatter, calendar: calendar, today: today) }
            guard !visibleDays.isEmpty else {
                index += 7
                continue
            }
            var usage = Usage()
            var turns = 0
            var activeDays = 0
            var total: Int64 = 0
            for day in visibleDays {
                usage.add(day.usage)
                turns += day.turns
                total += day.usage.total
                if day.usage.total > 0 {
                    activeDays += 1
                }
            }
            result.append(ContributionWeekSummary(
                key: visibleDays.first?.day ?? "",
                startDay: visibleDays.first?.day ?? "",
                endDay: visibleDays.last?.day ?? "",
                usage: usage,
                total: total,
                activeDays: activeDays,
                turns: turns,
                days: visibleDays,
                hitRect: .zero,
                cellRects: []
            ))
            index += 7
        }
        return result
    }

    private func selectedCalendarWeekSummary() -> ContributionWeekSummary? {
        guard let snapshot, let selectedWeekStartDay else { return nil }
        let report = calendarReport(for: snapshot)
        return contributionWeekColumns(in: report).first { $0.startDay == selectedWeekStartDay && $0.total > 0 }
    }

    private func drawContributionGrid(report: TokenReport, rect: NSRect, title: String, compact: Bool) {
        drawPanel(rect)
        drawText(title, rect: NSRect(x: rect.minX + 16, y: rect.minY + 12, width: rect.width - 32, height: 20), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        guard !report.byDay.isEmpty else {
            drawText(t(.noDailyTokenData), rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }
        let days = paddedContributionDays(report.byDay)

        let maxTotal = max(days.map { $0.usage.total }.max() ?? 1, 1)
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        let useCalendarGrid = !compact || days.count > 90
        let enableDayHover = selectedSection == .overview && compact
        let enableWeekSelection = selectedSection == .calendar && !compact && useCalendarGrid
        let columns = useCalendarGrid ? Int(ceil(Double(days.count) / 7.0)) : min(days.count, 15)
        let rows = useCalendarGrid ? 7 : Int(ceil(Double(days.count) / Double(max(columns, 1))))
        let gap: CGFloat = useCalendarGrid ? (compact ? 2 : 3) : 6
        let left: CGFloat = compact ? 18 : 26
        let right: CGFloat = compact ? 18 : 26
        let top: CGFloat = compact ? 42 : 58
        let bottom: CGFloat = compact ? 44 : 50
        let availableW = max(40, rect.width - left - right)
        let availableH = max(40, rect.height - top - bottom)
        let square = min(
            compact ? 16 : 18,
            floor(min((availableW - gap * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)), (availableH - gap * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))))
        )
        let gridH = CGFloat(rows) * square + CGFloat(max(rows - 1, 0)) * gap
        let startX = rect.minX + left
        let startY = rect.minY + top
        var cells: [(day: DayUsage, rect: NSRect, column: Int)] = []
        var weekCells: [Int: [NSRect]] = [:]
        var weekStartDays: [Int: String] = [:]
        var weekEndDays: [Int: String] = [:]
        var weekUsages: [Int: Usage] = [:]
        var weekTotals: [Int: Int64] = [:]
        var weekActiveDays: [Int: Int] = [:]
        var weekTurns: [Int: Int] = [:]
        var weekDays: [Int: [DayUsage]] = [:]

        for (index, day) in days.enumerated() {
            let col = useCalendarGrid ? index / 7 : index % columns
            let row = useCalendarGrid ? index % 7 : index / columns
            let isFuture = isFutureContributionDay(day.day, formatter: formatter, calendar: calendar, today: today)
            guard !isFuture else { continue }
            let cell = NSRect(x: startX + CGFloat(col) * (square + gap), y: startY + CGFloat(row) * (square + gap), width: square, height: square)
            cells.append((day: day, rect: cell, column: col))
            if day.usage.total > 0 || day.turns > 0 {
                contributionDayRects[day.day] = cell
                if enableDayHover {
                    contributionDaySummaries[day.day] = ContributionDaySummary(day: day, hitRect: cell)
                }
            }
            if enableWeekSelection {
                weekCells[col, default: []].append(cell)
                if weekStartDays[col] == nil {
                    weekStartDays[col] = day.day
                }
                weekEndDays[col] = day.day
                if weekUsages[col] == nil {
                    weekUsages[col] = Usage()
                }
                weekUsages[col]?.add(day.usage)
                weekTotals[col, default: 0] += day.usage.total
                weekTurns[col, default: 0] += day.turns
                weekDays[col, default: []].append(day)
                if day.usage.total > 0 {
                    weekActiveDays[col, default: 0] += 1
                }
            }
        }

        if enableWeekSelection {
            var summaries: [String: ContributionWeekSummary] = [:]
            for column in 0..<columns {
                guard let rects = weekCells[column], !rects.isEmpty,
                      (weekTotals[column] ?? 0) > 0 else { continue }
                let key = weekStartDays[column] ?? ""
                let unionRect = rects.dropFirst().reduce(rects[0]) { partial, cell in
                    partial.union(cell)
                }.insetBy(dx: -gap / 2, dy: -gap / 2)
                summaries[key] = ContributionWeekSummary(
                    key: key,
                    startDay: weekStartDays[column] ?? "",
                    endDay: weekEndDays[column] ?? "",
                    usage: weekUsages[column] ?? Usage(total: weekTotals[column] ?? 0),
                    total: weekTotals[column] ?? 0,
                    activeDays: weekActiveDays[column] ?? 0,
                    turns: weekTurns[column] ?? 0,
                    days: weekDays[column] ?? [],
                    hitRect: unionRect,
                    cellRects: rects
                )
            }
            contributionWeekSummaries = summaries
            if let selectedWeekStartDay,
               let summary = summaries[selectedWeekStartDay] {
                drawContributionWeekHighlight(summary, emphasized: true)
            }
            if let hoveredContributionWeekKey,
               hoveredContributionWeekKey != selectedWeekStartDay,
               let summary = summaries[hoveredContributionWeekKey] {
                drawContributionWeekHighlight(summary, emphasized: false)
            }
            for (key, summary) in summaries {
                let center = CGPoint(x: summary.hitRect.midX, y: startY - 11)
                let isSelected = key == selectedWeekStartDay
                let isHovered = key == hoveredContributionWeekKey
                let radius: CGFloat = isSelected ? 3.5 : 3
                let dotRect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                if isSelected {
                    accentTeal.setFill()
                } else if isHovered {
                    NSColor.white.withAlphaComponent(0.85).setFill()
                } else {
                    NSColor.white.withAlphaComponent(0.32).setFill()
                }
                NSBezierPath(ovalIn: dotRect).fill()
                if isSelected {
                    accentTeal.withAlphaComponent(0.40).setStroke()
                    let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -2.5, dy: -2.5))
                    ring.lineWidth = 1.5
                    ring.stroke()
                }
                contributionWeekDotRects[key] = NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
            }
        }

        for cellData in cells {
            let day = cellData.day
            let cell = cellData.rect
            let intensity = Double(day.usage.total) / Double(maxTotal)
            contributionColor(intensity).setFill()
            NSBezierPath(roundedRect: cell, xRadius: 3, yRadius: 3).fill()
            if day.day == selectedDay {
                NSColor.white.withAlphaComponent(0.92).setStroke()
                let path = NSBezierPath(roundedRect: cell.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
                path.lineWidth = 2
                path.stroke()
            } else if enableDayHover && day.day == hoveredContributionDay {
                NSColor.white.withAlphaComponent(0.72).setStroke()
                let path = NSBezierPath(roundedRect: cell.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5)
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        let labelY = min(startY + gridH + 10, rect.maxY - 38)
        let hintY = min(labelY + 18, rect.maxY - 20)
        drawContributionMonthLabels(days: days, useCalendarGrid: useCalendarGrid, columns: columns, square: square, gap: gap, startX: startX, y: labelY, compact: compact)
        drawText(t(.usageIntensityHint), rect: NSRect(x: startX, y: hintY, width: min(320, rect.maxX - startX - right), height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
        if enableDayHover,
           let hoveredContributionDay,
           let summary = contributionDaySummaries[hoveredContributionDay] {
            drawContributionDayTooltip(summary, container: rect)
        }
    }

    private func drawContributionDayTooltip(_ summary: ContributionDaySummary, container: NSRect) {
        let width: CGFloat = 214
        let height: CGFloat = 92
        let gap: CGFloat = 12
        var origin = CGPoint(x: summary.hitRect.maxX + gap, y: summary.hitRect.midY - height / 2)
        if origin.x + width > container.maxX - 12 {
            origin.x = summary.hitRect.minX - gap - width
        }
        if origin.x < container.minX + 12 {
            origin.x = summary.hitRect.midX - width / 2
            origin.y = summary.hitRect.minY - height - gap
        }
        if origin.y < container.minY + 10 {
            origin.y = summary.hitRect.maxY + gap
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        let day = summary.day
        let planValue = contributionDayPlanValue(day)
        let apiEstimate = contributionDayAPIEstimate(day)
        let rows: [(String, String)] = [
            ("Token", compactDashboardTotal(day.usage.total)),
            (contributionPlanAmountLabel(), planValue.map { displayMoney($0, source: selectedDetailsSource) } ?? "--"),
            (contributionAPIAmountLabel(), apiEstimate.hasPricedUsage ? displayAPIMoney(apiEstimate.usdValue, source: selectedDetailsSource) : "--")
        ]
        drawText(localizedContributionDate(day.day), rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.minY + 8, width: tooltipRect.width - 20, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.82))
        for (index, row) in rows.enumerated() {
            let y = tooltipRect.minY + 27 + CGFloat(index) * 16
            drawText(row.0, rect: NSRect(x: tooltipRect.minX + 10, y: y, width: 84, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.52))
            drawRight(row.1, rect: NSRect(x: tooltipRect.minX + 92, y: y - 1, width: tooltipRect.width - 102, height: 15), color: NSColor.white.withAlphaComponent(0.86), font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold))
        }
        drawText(t(.clickForDetails), rect: NSRect(x: tooltipRect.minX + 10, y: tooltipRect.maxY - 18, width: tooltipRect.width - 20, height: 13), font: .systemFont(ofSize: 9, weight: .medium), color: accentTeal.withAlphaComponent(0.74))
    }

    private func contributionDayPlanValue(_ day: DayUsage) -> Double? {
        guard let snapshot else { return nil }
        let report = calendarReport(for: snapshot)
        let reportDay = report.byDay.first { $0.day == day.day } ?? day
        return planCostEstimate(
            report: report,
            selectedDay: reportDay,
            limit: sourceCostLimit(for: snapshot),
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        )?.selectedDayValue
    }

    private func contributionDayAPIEstimate(_ day: DayUsage) -> APICostEstimate {
        guard let snapshot, usesProfileAPIReport(for: snapshot) else {
            return APICostEstimator.estimate(day: day)
        }
        let localDay = snapshot.codex.byDay.first { $0.day == day.day }
        return profileAPIDayEstimate(profileDay: day, localDay: localDay)
    }

    private func contributionPlanAmountLabel() -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "对应金额"
        case .japanese:
            return "対応金額"
        default:
            return "Plan value"
        }
    }

    private func contributionAPIAmountLabel() -> String {
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            return "API 金额"
        case .japanese:
            return "API 金額"
        default:
            return "API cost"
        }
    }

    private func drawContributionWeekHighlight(_ summary: ContributionWeekSummary, emphasized: Bool) {
        let rect = summary.hitRect.insetBy(dx: -4, dy: -4)
        accentTeal.withAlphaComponent(emphasized ? 0.14 : 0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        accentTeal.withAlphaComponent(emphasized ? 0.70 : 0.40).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        border.lineWidth = emphasized ? 1.5 : 1
        border.stroke()
    }

    private func contributionWeekRangeLabel(_ summary: ContributionWeekSummary) -> String {
        "\(localizedContributionDate(summary.startDay)) - \(localizedContributionDate(summary.endDay))"
    }

    private enum ContributionWeekMetric {
        case tokens
        case activeDays
        case average
        case inputOutput
        case cache
        case turns
    }

    private func contributionWeekLabel(_ metric: ContributionWeekMetric) -> String {
        switch (metric, AppLanguage.current) {
        case (.tokens, .chinese), (.tokens, .traditionalChinese): return "Token"
        case (.tokens, .japanese): return "Token"
        case (.tokens, _): return "Tokens"
        case (.activeDays, .chinese), (.activeDays, .traditionalChinese): return "活跃天数"
        case (.activeDays, .japanese): return "利用日数"
        case (.activeDays, _): return "Active days"
        case (.average, .chinese), (.average, .traditionalChinese): return "日均"
        case (.average, .japanese): return "日平均"
        case (.average, _): return "Daily avg"
        case (.inputOutput, .chinese), (.inputOutput, .traditionalChinese): return "输入/输出"
        case (.inputOutput, .japanese): return "入力/出力"
        case (.inputOutput, _): return "Input/output"
        case (.cache, .chinese), (.cache, .traditionalChinese): return "缓存命中"
        case (.cache, .japanese): return "キャッシュ"
        case (.cache, _): return "Cache hit"
        case (.turns, .chinese), (.turns, .traditionalChinese): return "轮次"
        case (.turns, .japanese): return "ターン"
        case (.turns, _): return "Turns"
        }
    }

    private func contributionWeekPlanValue(_ summary: ContributionWeekSummary) -> Double? {
        guard let snapshot,
              let date = dayFormatter().date(from: summary.startDay),
              let weekStart = appCalendar().dateInterval(of: .weekOfYear, for: date)?.start else {
            return nil
        }
        let report = calendarReport(for: snapshot)
        guard let estimator = CostEstimator(
            report: report,
            limit: sourceCostLimit(for: snapshot),
            quotaReferenceReport: sourceCostReferenceReport(for: snapshot),
            monthlyCost: AppSettings.monthlyPlanCost(for: selectedDetailsSource),
            paymentStartDay: AppSettings.paymentStartDay(for: selectedDetailsSource)
        ) else {
            return nil
        }
        return estimator.weeklyUsedValue(forWeekStart: weekStart, total: summary.total)
    }

    private func contributionWeekAPIEstimate(_ summary: ContributionWeekSummary) -> APICostEstimate {
        var estimate = APICostEstimate()
        if summary.days.isEmpty {
            estimate.add(APICostEstimator.estimate(day: DayUsage(day: summary.startDay, usage: summary.usage, turns: summary.turns)))
            return estimate
        }
        for day in summary.days {
            estimate.add(contributionDayAPIEstimate(day))
        }
        return estimate
    }

    private func localizedContributionDate(_ day: String) -> String {
        guard let date = dayFormatter().date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.timeZone = appTimeZone()
        switch AppLanguage.current {
        case .chinese, .traditionalChinese:
            formatter.locale = Locale(identifier: "zh_Hans_CN")
            formatter.dateFormat = "yyyy年M月d日"
        case .japanese:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy年M月d日"
        default:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private func contributionGridPreferredHeight(report: TokenReport, width: CGFloat, compact: Bool) -> CGFloat {
        guard !report.byDay.isEmpty else {
            return compact ? 112 : 128
        }
        let days = paddedContributionDays(report.byDay)
        let useCalendarGrid = !compact || days.count > 90
        let columns = useCalendarGrid ? Int(ceil(Double(days.count) / 7.0)) : min(days.count, 15)
        let rows = useCalendarGrid ? 7 : Int(ceil(Double(days.count) / Double(max(columns, 1))))
        let gap: CGFloat = useCalendarGrid ? (compact ? 2 : 3) : 6
        let left: CGFloat = compact ? 18 : 26
        let right: CGFloat = compact ? 18 : 26
        let top: CGFloat = compact ? 42 : 58
        let availableW = max(40, width - left - right)
        let square = min(
            compact ? 16 : 18,
            floor((availableW - gap * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)))
        )
        let gridH = CGFloat(rows) * max(6, square) + CGFloat(max(rows - 1, 0)) * gap
        let labelAndHintHeight: CGFloat = compact ? 48 : 54
        return ceil(top + gridH + labelAndHintHeight)
    }

    private func drawContributionMonthLabels(days: [DayUsage], useCalendarGrid: Bool, columns: Int, square: CGFloat, gap: CGFloat, startX: CGFloat, y: CGFloat, compact: Bool) {
        var lastMonth: String?
        var lastLabelX = -CGFloat.greatestFiniteMagnitude
        let minimumGap: CGFloat = compact ? 42 : 50
        let formatter = dayFormatter()
        let calendar = appCalendar()
        let today = calendar.startOfDay(for: Date())
        for (index, day) in days.enumerated() {
            guard !isFutureContributionDay(day.day, formatter: formatter, calendar: calendar, today: today) else { continue }
            let month = String(day.day.prefix(7))
            guard month != lastMonth else { continue }
            lastMonth = month
            let col = useCalendarGrid ? index / 7 : index % columns
            let x = startX + CGFloat(col) * (square + gap)
            guard x - lastLabelX >= minimumGap else { continue }
            let label = contributionMonthLabel(for: day.day)
            drawText(label, rect: NSRect(x: x, y: y, width: 44, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.44))
            lastLabelX = x
        }
    }

    private func contributionMonthLabel(for day: String) -> String {
        guard let date = dayFormatter().date(from: day) else {
            return String(day.dropFirst(5).prefix(2))
        }
        let formatter = DateFormatter()
        formatter.timeZone = appTimeZone()
        switch AppLanguage.current {
        case .english:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM"
        case .chinese:
            formatter.locale = Locale(identifier: "zh_Hans_CN")
            formatter.dateFormat = "M月"
        case .japanese:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月"
        default:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }

    // MARK: - Storage page

    private struct StoragePageLayout {
        var banner: NSRect?
        var toolbar: NSRect
        var cards: NSRect
        var source: NSRect
        var projects: NSRect
        var growth: NSRect
        var risk: NSRect
        var footer: NSRect
        var totalHeight: CGFloat
    }

    private func storagePageLayout(content: NSRect) -> StoragePageLayout {
        let wide = content.width >= 900
        var y = content.minY + 78
        var banner: NSRect?
        if isStorageScanning, storageSnapshot != nil {
            banner = NSRect(x: content.minX, y: y, width: content.width, height: 34)
            y += 44
        }
        let toolbar = NSRect(x: content.minX, y: y, width: content.width, height: 28)
        y = toolbar.maxY + 12
        let cards = NSRect(x: content.minX, y: y, width: content.width, height: 84)
        y = cards.maxY + 14

        let sourceRows = CGFloat(max(1, storageVisibleCategories().count))
        let sourceHeight = 46 + sourceRows * 52 + 14
        let source: NSRect
        let projects: NSRect
        if wide {
            let sourceW = floor((content.width - 16) * 0.52)
            let middleH = max(sourceHeight, 420)
            source = NSRect(x: content.minX, y: y, width: sourceW, height: middleH)
            projects = NSRect(x: source.maxX + 16, y: y, width: content.width - sourceW - 16, height: middleH)
            y = source.maxY + 16
        } else {
            source = NSRect(x: content.minX, y: y, width: content.width, height: sourceHeight)
            projects = NSRect(x: content.minX, y: source.maxY + 16, width: content.width, height: 420)
            y = projects.maxY + 16
        }

        let growth: NSRect
        let risk: NSRect
        if wide {
            let growthW = floor((content.width - 16) * 0.62)
            growth = NSRect(x: content.minX, y: y, width: growthW, height: 244)
            risk = NSRect(x: growth.maxX + 16, y: y, width: content.width - growthW - 16, height: 244)
            y = growth.maxY + 16
        } else {
            growth = NSRect(x: content.minX, y: y, width: content.width, height: 244)
            risk = NSRect(x: content.minX, y: growth.maxY + 16, width: content.width, height: 230)
            y = risk.maxY + 16
        }
        let footer = NSRect(x: content.minX, y: y, width: content.width, height: 36)
        return StoragePageLayout(
            banner: banner,
            toolbar: toolbar,
            cards: cards,
            source: source,
            projects: projects,
            growth: growth,
            risk: risk,
            footer: footer,
            totalHeight: footer.maxY + 44
        )
    }

    private func storagePlatformCategories() -> [StorageCategoryUsage] {
        guard let snap = storageSnapshot else { return [] }
        return snap.categories
            .filter { category in
                (selectedDetailsSource == .all || category.id.platform == selectedDetailsSource)
                    && (category.bytes > 0 || category.fileCount > 0)
            }
            .sorted { $0.bytes > $1.bytes }
    }

    private func storageVisibleCategories() -> [StorageCategoryUsage] {
        let base = storagePlatformCategories()
        guard let filter = storageFilterCategory, base.contains(where: { $0.id == filter }) else { return base }
        return base.filter { $0.id == filter }
    }

    private func selectedStorageUsage() -> StorageCategoryUsage? {
        let visible = storagePlatformCategories()
        if let id = selectedStorageCategoryID, let match = visible.first(where: { $0.id == id }) {
            return match
        }
        return visible.first
    }

    private func storageDayTotal(_ day: String, snap: StorageSnapshot) -> Int64 {
        let ids = Set(storageVisibleCategories().map { $0.id.rawValue })
        guard let perCategory = snap.dailyGrowth[day] else { return 0 }
        return perCategory.reduce(Int64(0)) { partial, entry in
            ids.contains(entry.key) ? partial + entry.value : partial
        }
    }

    private func storageGrowthBreakdown(days: [String], snap: StorageSnapshot) -> [(StorageCategoryID, Int64)] {
        let ids = Set(storageVisibleCategories().map { $0.id })
        var totals: [StorageCategoryID: Int64] = [:]
        for day in days {
            guard let perCategory = snap.dailyGrowth[day] else { continue }
            for (raw, bytes) in perCategory {
                guard let id = StorageCategoryID(rawValue: raw), ids.contains(id) else { continue }
                totals[id, default: 0] += bytes
            }
        }
        return totals.sorted { $0.value > $1.value }
    }

    private func storageFilteredProjects() -> [StorageProjectUsage] {
        guard let snap = storageSnapshot else { return [] }
        var rows = snap.projects.filter { project in
            selectedDetailsSource == .all || project.platform == selectedDetailsSource
        }
        let query = storageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            rows = rows.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
            }
        }
        switch storageSortOption {
        case .size:
            rows.sort { $0.bytes > $1.bytes }
        case .recent:
            rows.sort { ($0.newestModified ?? .distantPast) > ($1.newestModified ?? .distantPast) }
        case .name:
            rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return rows
    }

    private func storageInsight(for project: StorageProjectUsage) -> RepoInsight? {
        guard let snapshot else { return nil }
        let report: RepoInsightsReport
        switch project.platform {
        case .claude:
            report = snapshot.claudeRepoInsights
        case .codex:
            report = snapshot.codexRepoInsights
        case .all:
            report = snapshot.repoInsights
        }
        return report.rows.first { $0.folders.contains(project.path) }
            ?? report.rows.first { $0.primaryFolder == project.path }
            ?? report.rows.first { $0.displayName.caseInsensitiveCompare(project.name) == .orderedSame }
    }

    private func storageProjectNeedsReview(_ project: StorageProjectUsage) -> Bool {
        guard project.bytes > 300 * 1_048_576 else { return false }
        guard let newest = project.newestModified else { return true }
        return newest < Date().addingTimeInterval(-30 * 86_400)
    }

    private func storageCategoryColor(_ id: StorageCategoryID) -> NSColor {
        switch id {
        case .codexSessions: return .systemGreen
        case .codexWorktrees: return accentBlue
        case .codexBackups: return accentAmber
        case .codexDatabase: return .systemPurple
        case .codexImages: return .systemPink
        case .codexPlugins: return .systemTeal
        case .codexOther: return .systemGray
        case .claudeProjects: return .systemOrange
        case .claudeOther: return .systemBrown
        }
    }

    private func storageRiskColor(_ risk: StorageRisk) -> NSColor {
        switch risk {
        case .safeToClear: return accentTeal
        case .reviewFirst: return accentAmber
        case .doNotClean: return accentRose
        }
    }

    private func storageSymbolName(_ id: StorageCategoryID) -> String {
        switch id {
        case .codexSessions: return "doc.text"
        case .codexWorktrees: return "folder"
        case .codexBackups: return "archivebox"
        case .codexDatabase: return "externaldrive"
        case .codexImages: return "photo"
        case .codexPlugins: return "puzzlepiece"
        case .codexOther: return "shippingbox"
        case .claudeProjects: return "cube"
        case .claudeOther: return "tray.full"
        }
    }

    private func drawStorageIcon(_ id: StorageCategoryID, in rect: NSRect) {
        let color = storageCategoryColor(id)
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        if let base = NSImage(systemSymbolName: storageSymbolName(id), accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)) {
            let tinted = NSImage(size: base.size)
            tinted.lockFocus()
            base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.set()
            NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let target = NSRect(
                x: rect.midX - base.size.width / 2,
                y: rect.midY - base.size.height / 2,
                width: base.size.width,
                height: base.size.height
            )
            tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8)).fill()
        }
    }

    private func handleStorageMouseDown(at point: CGPoint) -> Bool {
        if let rect = storageRefreshRect, rect.contains(point) {
            if !isStorageScanning {
                isStorageScanning = true
                onStorageScanRequested?()
            }
            return true
        }
        if let rect = storageExportRect, rect.contains(point) {
            exportStorageReport()
            return true
        }
        if let rect = storageOpenFinderRect, rect.contains(point) {
            if let path = selectedStorageUsage()?.roots.first {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            return true
        }
        for (id, rect) in storageSourceMenuRects where rect.insetBy(dx: -4, dy: -4).contains(point) {
            showStorageCategoryMenu(id, at: point)
            return true
        }
        for (id, rect) in storageSourceRowRects where rect.contains(point) {
            selectedStorageCategoryID = id
            needsDisplay = true
            return true
        }
        return false
    }

    private func showStorageCategoryMenu(_ id: StorageCategoryID, at point: CGPoint) {
        let copy = AppLanguage.current.storageCopy
        let menu = NSMenu()
        let reveal = NSMenuItem(title: copy.revealInFinder, action: #selector(storageMenuReveal(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = id.rawValue
        menu.addItem(reveal)
        let copyItem = NSMenuItem(title: copy.copyPath, action: #selector(storageMenuCopyPath(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = id.rawValue
        menu.addItem(copyItem)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func storageMenuCategory(_ sender: NSMenuItem) -> StorageCategoryUsage? {
        guard let raw = sender.representedObject as? String,
              let id = StorageCategoryID(rawValue: raw) else { return nil }
        return storageSnapshot?.category(id)
    }

    @objc private func storageMenuReveal(_ sender: NSMenuItem) {
        guard let path = storageMenuCategory(sender)?.roots.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func storageMenuCopyPath(_ sender: NSMenuItem) {
        guard let usage = storageMenuCategory(sender), !usage.roots.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(usage.roots.joined(separator: "\n"), forType: .string)
    }

    @objc private func storageFilterPopupChanged() {
        let index = storageFilterPopup.indexOfSelectedItem
        let cats = storagePlatformCategories()
        if index <= 0 || index > cats.count {
            storageFilterCategory = nil
        } else {
            storageFilterCategory = cats[index - 1].id
        }
        onPreferredHeightChanged?()
        needsDisplay = true
        needsLayout = true
    }

    @objc private func storageSortPopupChanged() {
        let options: [StorageSortOption] = [.size, .recent, .name]
        let index = storageSortPopup.indexOfSelectedItem
        if index >= 0 && index < options.count {
            storageSortOption = options[index]
        }
        needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField, field === storageSearchField else { return }
        storageSearchText = field.stringValue
        needsDisplay = true
    }

    private func layoutStorageControls() {
        let visible = selectedSection == .storage && storageSnapshot != nil
        storageFilterPopup.isHidden = !visible
        storageSortPopup.isHidden = !visible
        storageSearchField.isHidden = !visible
        guard visible else { return }
        let content = NSRect(x: detailsSidebarWidth + 28, y: 28, width: bounds.width - detailsSidebarWidth - 56, height: bounds.height - 56)
        let bar = storagePageLayout(content: content).toolbar
        let searchW = min(240, max(160, bar.width * 0.26))
        storageSearchField.frame = NSRect(x: bar.maxX - searchW, y: bar.minY + 1, width: searchW, height: 26)
        let sortW: CGFloat = 148
        storageSortPopup.frame = NSRect(x: storageSearchField.frame.minX - 10 - sortW, y: bar.minY, width: sortW, height: 28)
        let filterW: CGFloat = 148
        storageFilterPopup.frame = NSRect(x: storageSortPopup.frame.minX - 10 - filterW, y: bar.minY, width: filterW, height: 28)
        updateStoragePopupItems()
    }

    private func updateStoragePopupItems() {
        let copy = AppLanguage.current.storageCopy
        let cats = storagePlatformCategories()
        let filterTitles = [copy.filterAll] + cats.map { copy.categories($0.id).name }
        if storageFilterPopup.itemArray.map(\.title) != filterTitles {
            storageFilterPopup.removeAllItems()
            storageFilterPopup.addItems(withTitles: filterTitles)
        }
        let filterIndex = storageFilterCategory.flatMap { id in cats.firstIndex { $0.id == id }.map { $0 + 1 } } ?? 0
        if storageFilterPopup.indexOfSelectedItem != filterIndex, filterIndex < storageFilterPopup.numberOfItems {
            storageFilterPopup.selectItem(at: filterIndex)
        }
        let sortTitles = [copy.sortBySize, copy.sortByRecent, copy.sortByName]
        if storageSortPopup.itemArray.map(\.title) != sortTitles {
            storageSortPopup.removeAllItems()
            storageSortPopup.addItems(withTitles: sortTitles)
        }
        let sortIndex = [StorageSortOption.size, .recent, .name].firstIndex(of: storageSortOption) ?? 0
        if storageSortPopup.indexOfSelectedItem != sortIndex {
            storageSortPopup.selectItem(at: sortIndex)
        }
        if storageSearchField.placeholderString != copy.searchPlaceholder {
            storageSearchField.placeholderString = copy.searchPlaceholder
        }
    }

    private func exportStorageReport() {
        guard let snap = storageSnapshot, let window else { return }
        let copy = AppLanguage.current.storageCopy
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ai-token-meter-storage-report.md"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            var lines: [String] = []
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            lines.append("# AI Token Meter · \(copy.headerTitle)")
            lines.append("")
            lines.append(String(format: copy.scannedAtFormat, formatter.string(from: snap.scannedAt)))
            lines.append("")
            lines.append("| \(copy.sourceTitle) | \(copy.colSize) | \(copy.colAdvice) |")
            lines.append("| --- | ---: | --- |")
            for usage in snap.categories.sorted(by: { $0.bytes > $1.bytes }) where usage.bytes > 0 {
                let name = copy.categories(usage.id).name
                lines.append("| \(name) (\(usage.roots.joined(separator: ", "))) | \(storageByteText(usage.bytes)) | \(copy.riskLabel(usage.id.risk)) |")
            }
            lines.append("")
            lines.append("| \(copy.colProject) | \(copy.colApp) | \(copy.colSize) |")
            lines.append("| --- | --- | ---: |")
            for project in snap.projects.prefix(20) {
                lines.append("| \(project.path) | \(project.platform == .claude ? "Claude" : "Codex") | \(storageByteText(project.bytes)) |")
            }
            lines.append("")
            lines.append("> \(copy.caveat)")
            do {
                try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url, options: [.atomic])
                NSWorkspace.shared.open(url)
            } catch {
                NSSound.beep()
            }
        }
    }

    private func drawStoragePage(content: NSRect) {
        let copy = AppLanguage.current.storageCopy
        guard let snap = storageSnapshot else {
            drawText(copy.scanningLabel, rect: NSRect(x: content.minX, y: content.minY + 92, width: content.width, height: 24), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor.white.withAlphaComponent(0.56))
            return
        }
        let layout = storagePageLayout(content: content)
        if let banner = layout.banner {
            drawStorageBanner(snap: snap, copy: copy, rect: banner)
        }
        drawStorageStatCards(snap: snap, copy: copy, rect: layout.cards)
        drawStorageSourcePanel(snap: snap, copy: copy, rect: layout.source)
        drawStorageProjectsPanel(snap: snap, copy: copy, rect: layout.projects)
        drawStorageGrowthChart(snap: snap, copy: copy, rect: layout.growth)
        drawStorageRiskPanel(snap: snap, copy: copy, rect: layout.risk)
        drawStorageFooter(snap: snap, copy: copy, rect: layout.footer)
    }

    private func drawStorageBanner(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        accentBlue.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        accentBlue.withAlphaComponent(0.32).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        let dot = NSRect(x: rect.minX + 14, y: rect.midY - 4, width: 8, height: 8)
        accentBlue.setFill()
        NSBezierPath(ovalIn: dot).fill()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let text = String(format: copy.rescanBannerFormat, formatter.string(from: snap.scannedAt))
        drawText(text, rect: NSRect(x: rect.minX + 32, y: rect.midY - 8, width: rect.width - 48, height: 16), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.78))
    }

    private func drawStorageStatCards(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        let totalBytes = snap.totalBytes(platform: .all)
        let codexBytes = snap.totalBytes(platform: .codex)
        let claudeBytes = snap.totalBytes(platform: .claude)
        let fileCount = snap.totalFileCount(platform: selectedDetailsSource)
        let recentBytes = snap.recentGrowthBytes(platform: selectedDetailsSource)
        func share(_ value: Int64) -> String {
            guard totalBytes > 0 else { return "--" }
            return String(format: copy.shareFormat, String(format: "%.1f%%", Double(value) / Double(totalBytes) * 100))
        }
        let cards: [(String, String, String, NSColor)] = [
            (copy.totalCard, storageByteText(totalBytes), "\(format(totalBytes)) \(copy.bytesSuffix)", .systemGreen),
            ("Codex", storageByteText(codexBytes), share(codexBytes), .systemCyan),
            ("Claude", storageByteText(claudeBytes), share(claudeBytes), .systemOrange),
            (copy.fileCountCard, format(Int64(fileCount)), copy.fileCountHint, NSColor.white.withAlphaComponent(0.92)),
            (copy.recentCard, storageGrowthText(recentBytes), String(format: copy.filesFormat, format(Int64(snap.recentGrowthFiles(platform: selectedDetailsSource)))), accentTeal)
        ]
        let gap: CGFloat = 12
        let cardW = (rect.width - gap * CGFloat(cards.count - 1)) / CGFloat(cards.count)
        let valueFontSize: CGFloat = cardW < 158 ? 15 : (cardW < 200 ? 17 : 19)
        for (index, card) in cards.enumerated() {
            let cardRect = NSRect(x: rect.minX + CGFloat(index) * (cardW + gap), y: rect.minY, width: cardW, height: rect.height)
            drawPanel(cardRect)
            drawTruncatedText(card.0, rect: NSRect(x: cardRect.minX + 14, y: cardRect.minY + 11, width: cardRect.width - 28, height: 15), font: .systemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.5))
            drawTruncatedText(card.1, rect: NSRect(x: cardRect.minX + 14, y: cardRect.minY + 29, width: cardRect.width - 28, height: 24), font: .monospacedDigitSystemFont(ofSize: valueFontSize, weight: .bold), color: card.3)
            drawTruncatedText(card.2, rect: NSRect(x: cardRect.minX + 14, y: cardRect.minY + 58, width: cardRect.width - 28, height: 14), font: .systemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))
        }
    }

    private func drawStorageSourcePanel(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.sourceTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 170, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)
        let visible = storageVisibleCategories()
        let visibleTotal = visible.reduce(Int64(0)) { $0 + $1.bytes }
        drawRight(String(format: copy.totalFormat, storageByteText(visibleTotal)), rect: NSRect(x: rect.maxX - 166, y: rect.minY + 16, width: 150, height: 15), color: NSColor.white.withAlphaComponent(0.44), font: .systemFont(ofSize: 10.5, weight: .semibold))

        guard !visible.isEmpty else {
            drawText(copy.emptyCategoriesHint, rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let maxBytes = max(visible.map { $0.bytes }.max() ?? 1, 1)
        let selectedUsage = selectedStorageUsage()
        let rowH: CGFloat = 52
        let maxRows = max(1, Int((rect.height - 46 - 12) / rowH))
        for (index, usage) in visible.prefix(maxRows).enumerated() {
            let row = NSRect(x: rect.minX + 10, y: rect.minY + 46 + CGFloat(index) * rowH, width: rect.width - 20, height: rowH - 4)
            storageSourceRowRects[usage.id] = row
            if usage.id == selectedUsage?.id {
                accentBlue.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: row, xRadius: 7, yRadius: 7).fill()
            } else if usage.id == hoveredStorageSourceID {
                NSColor.white.withAlphaComponent(0.05).setFill()
                NSBezierPath(roundedRect: row, xRadius: 7, yRadius: 7).fill()
            }
            drawStorageIcon(usage.id, in: NSRect(x: row.minX + 8, y: row.minY + 8, width: 32, height: 32))

            let nameX = row.minX + 52
            let sizeX = row.maxX - 128
            let name = copy.categories(usage.id).name
            let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
            let nameW = min(measuredTextWidth(name, font: nameFont), sizeX - nameX - 92)
            drawTruncatedText(name, rect: NSRect(x: nameX, y: row.minY + 6, width: nameW + 4, height: 17), font: nameFont, color: .white)
            let chipText = copy.riskLabel(usage.id.risk)
            let chipW = measuredTextWidth(chipText, font: .systemFont(ofSize: 8.5, weight: .semibold)) + 14
            drawStorageRiskChip(chipText, color: storageRiskColor(usage.id.risk), rect: NSRect(x: nameX + nameW + 10, y: row.minY + 8, width: chipW, height: 15), fontSize: 8.5)

            let home = NSHomeDirectory()
            let pathText = usage.roots
                .map { $0.hasPrefix(home) ? "~" + $0.dropFirst(home.count) : $0 }
                .joined(separator: ", ")
            drawTruncatedText(pathText, rect: NSRect(x: nameX, y: row.minY + 26, width: max(40, sizeX - nameX - 10), height: 13), font: .systemFont(ofSize: 9.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))

            drawRight(storageByteText(usage.bytes), rect: NSRect(x: sizeX, y: row.minY + 7, width: 86, height: 16), color: .white, font: .monospacedDigitSystemFont(ofSize: 12.5, weight: .bold))
            let pct = visibleTotal > 0 ? Double(usage.bytes) / Double(visibleTotal) * 100 : 0
            drawRight(String(format: "%.1f%%", pct), rect: NSRect(x: sizeX, y: row.minY + 26, width: 86, height: 13), color: NSColor.white.withAlphaComponent(0.45), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold))

            let menuRect = NSRect(x: row.maxX - 30, y: row.minY + 14, width: 22, height: 20)
            storageSourceMenuRects[usage.id] = menuRect
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: menuRect, xRadius: 5, yRadius: 5).fill()
            drawCentered("⋯", rect: menuRect, font: .systemFont(ofSize: 12, weight: .bold), color: NSColor.white.withAlphaComponent(0.6))

            let barTrack = NSRect(x: nameX, y: row.minY + 42, width: max(30, sizeX - nameX - 10), height: 3)
            NSColor.white.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: barTrack, xRadius: 1.5, yRadius: 1.5).fill()
            let fraction = CGFloat(Double(usage.bytes) / Double(maxBytes))
            let fill = NSRect(x: barTrack.minX, y: barTrack.minY, width: max(2, barTrack.width * fraction), height: barTrack.height)
            storageCategoryColor(usage.id).withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func drawStorageProjectsPanel(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.projectsTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)

        let rows = storageFilteredProjects()
        guard !rows.isEmpty else {
            drawText(copy.noProjectsHint, rect: NSRect(x: rect.minX + 16, y: rect.minY + 52, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 12, weight: .medium), color: NSColor.white.withAlphaComponent(0.48))
            return
        }

        let compactColumns = rect.width < 470
        let adviceW: CGFloat = 58
        let turnsW: CGFloat = compactColumns ? 0 : 46
        let tokensW: CGFloat = compactColumns ? 0 : 62
        let sizeW: CGFloat = 74
        let appW: CGFloat = compactColumns ? 0 : 52
        let gap: CGFloat = 10
        let adviceX = rect.maxX - 14 - adviceW
        let turnsX = adviceX - (turnsW > 0 ? gap + turnsW : 0)
        let tokensX = turnsX - (tokensW > 0 ? gap + tokensW : 0)
        let sizeX = tokensX - gap - sizeW
        let appX = sizeX - (appW > 0 ? gap + appW : 0)
        let nameMaxX = (appW > 0 ? appX : sizeX) - 12

        let headerFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        let headerColor = NSColor.white.withAlphaComponent(0.38)
        let headerY = rect.minY + 42
        drawText(copy.colProject, rect: NSRect(x: rect.minX + 16, y: headerY, width: nameMaxX - rect.minX - 16, height: 13), font: headerFont, color: headerColor)
        if appW > 0 {
            drawRight(copy.colApp, rect: NSRect(x: appX, y: headerY, width: appW, height: 13), color: headerColor, font: headerFont)
        }
        drawRight(copy.colSize, rect: NSRect(x: sizeX, y: headerY, width: sizeW, height: 13), color: headerColor, font: headerFont)
        if tokensW > 0 {
            drawRight(copy.colTokens, rect: NSRect(x: tokensX, y: headerY, width: tokensW, height: 13), color: headerColor, font: headerFont)
        }
        if turnsW > 0 {
            drawRight(copy.colTurns, rect: NSRect(x: turnsX, y: headerY, width: turnsW, height: 13), color: headerColor, font: headerFont)
        }
        drawRight(copy.colAdvice, rect: NSRect(x: adviceX, y: headerY, width: adviceW, height: 13), color: headerColor, font: headerFont)

        let rowH: CGFloat = 44
        let maxRows = max(1, Int((rect.height - 62 - 8) / rowH))
        let home = NSHomeDirectory()
        for (index, project) in rows.prefix(maxRows).enumerated() {
            let y = rect.minY + 60 + CGFloat(index) * rowH
            if index > 0 {
                NSColor.white.withAlphaComponent(0.045).setFill()
                NSRect(x: rect.minX + 16, y: y - 2, width: rect.width - 32, height: 1).fill()
            }
            drawTruncatedText(project.name, rect: NSRect(x: rect.minX + 16, y: y + 4, width: max(40, nameMaxX - rect.minX - 16), height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: .white)
            let displayPath = project.path.hasPrefix(home) ? "~" + project.path.dropFirst(home.count) : project.path
            drawTruncatedText(displayPath, rect: NSRect(x: rect.minX + 16, y: y + 22, width: max(40, nameMaxX - rect.minX - 16), height: 13), font: .systemFont(ofSize: 9, weight: .medium), color: NSColor.white.withAlphaComponent(0.38))
            if appW > 0 {
                drawRight(project.platform == .claude ? "Claude" : "Codex", rect: NSRect(x: appX, y: y + 6, width: appW, height: 15), color: NSColor.white.withAlphaComponent(0.6), font: .systemFont(ofSize: 10.5, weight: .semibold))
            }
            drawRight(storageByteText(project.bytes), rect: NSRect(x: sizeX, y: y + 6, width: sizeW, height: 15), color: .white, font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .bold))
            let insight = storageInsight(for: project)
            if tokensW > 0 {
                drawRight(insight.map { compact($0.tokens) } ?? "—", rect: NSRect(x: tokensX, y: y + 6, width: tokensW, height: 15), color: NSColor.white.withAlphaComponent(0.62), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
            }
            if turnsW > 0 {
                drawRight(insight.map { format(Int64($0.turns)) } ?? "—", rect: NSRect(x: turnsX, y: y + 6, width: turnsW, height: 15), color: NSColor.white.withAlphaComponent(0.62), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
            }
            let needsReview = storageProjectNeedsReview(project)
            drawRight(needsReview ? copy.adviceReview : copy.adviceKeep, rect: NSRect(x: adviceX, y: y + 6, width: adviceW, height: 15), color: needsReview ? accentAmber : accentTeal, font: .systemFont(ofSize: 10.5, weight: .bold))
        }
    }

    private func drawStorageGrowthChart(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.growthTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)

        let days = snap.recentDays
        guard !days.isEmpty else { return }
        let visible = storageVisibleCategories()
        let recentTotals = storageGrowthBreakdown(days: days, snap: snap)
        let topIDs = Array(recentTotals.prefix(3).map { $0.0 })
        var series: [(String, NSColor, StorageCategoryID?)] = topIDs.map {
            (copy.categories($0).name, storageCategoryColor($0), $0)
        }
        let hasOther = visible.count > topIDs.count
        if hasOther {
            series.append((copy.otherSeries, NSColor.systemGray, nil))
        }

        var legendX = rect.maxX - 16
        let legendFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        for entry in series.reversed() {
            let labelW = measuredTextWidth(entry.0, font: legendFont)
            legendX -= labelW
            drawText(entry.0, rect: NSRect(x: legendX, y: rect.minY + 17, width: labelW + 4, height: 13), font: legendFont, color: NSColor.white.withAlphaComponent(0.55))
            legendX -= 12
            entry.1.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: rect.minY + 20, width: 7, height: 7)).fill()
            legendX -= 14
        }

        let plot = NSRect(x: rect.minX + 58, y: rect.minY + 46, width: rect.width - 58 - 18, height: rect.height - 46 - 34)
        let dayTotals = days.map { storageDayTotal($0, snap: snap) }
        let maxTotal = max(dayTotals.max() ?? 1, 1)

        let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
        let axisColor = NSColor.white.withAlphaComponent(0.35)
        for step in 0...2 {
            let value = Int64(Double(maxTotal) * Double(step) / 2.0)
            let y = plot.maxY - plot.height * CGFloat(step) / 2
            NSColor.white.withAlphaComponent(step == 0 ? 0.12 : 0.05).setFill()
            NSRect(x: plot.minX, y: y - 0.5, width: plot.width, height: 1).fill()
            drawRight(storageByteText(value), rect: NSRect(x: rect.minX + 8, y: y - 6, width: 46, height: 12), color: axisColor, font: axisFont)
        }

        let slotW = plot.width / CGFloat(days.count)
        let barW = max(6, slotW * 0.52)
        let enabledIDs = Set(visible.map { $0.id })
        for (index, day) in days.enumerated() {
            let total = dayTotals[index]
            let slotX = plot.minX + CGFloat(index) * slotW
            let barX = slotX + (slotW - barW) / 2
            var stackY = plot.maxY
            if total > 0 {
                let perCategory = snap.dailyGrowth[day] ?? [:]
                var seriesValues: [(NSColor, Int64)] = []
                var accounted: Int64 = 0
                for id in topIDs {
                    let value = perCategory[id.rawValue] ?? 0
                    accounted += value
                    if value > 0 {
                        seriesValues.append((storageCategoryColor(id), value))
                    }
                }
                if hasOther {
                    let otherValue = perCategory.reduce(Int64(0)) { partial, entry in
                        guard let id = StorageCategoryID(rawValue: entry.key), enabledIDs.contains(id), !topIDs.contains(id) else { return partial }
                        return partial + entry.value
                    }
                    if otherValue > 0 {
                        seriesValues.append((NSColor.systemGray, otherValue))
                    }
                }
                let totalHeight = max(3, plot.height * CGFloat(Double(total) / Double(maxTotal)))
                for (color, value) in seriesValues {
                    let segment = max(1.5, totalHeight * CGFloat(Double(value) / Double(total)))
                    let segmentRect = NSRect(x: barX, y: stackY - segment, width: barW, height: segment)
                    let hovered = hoveredStorageCellKey == "day-\(day)"
                    color.withAlphaComponent(hovered ? 1.0 : 0.82).setFill()
                    NSBezierPath(roundedRect: segmentRect, xRadius: 1.5, yRadius: 1.5).fill()
                    stackY -= segment
                }
                storageGrowthCells.append(StorageGrowthCell(
                    key: "day-\(day)",
                    rect: NSRect(x: slotX, y: plot.minY, width: slotW, height: plot.height),
                    title: localizedContributionDate(day),
                    rows: storageGrowthBreakdown(days: [day], snap: snap),
                    total: total
                ))
            } else {
                NSColor.white.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: NSRect(x: barX, y: plot.maxY - 2, width: barW, height: 2), xRadius: 1, yRadius: 1).fill()
            }
            if index % 2 == days.count % 2 {
                let parts = day.split(separator: "-")
                let label = parts.count == 3 ? "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)" : String(day.suffix(5))
                drawCentered(label, rect: NSRect(x: slotX - 6, y: plot.maxY + 6, width: slotW + 12, height: 12), font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.4))
            }
        }
    }

    private func drawStorageRiskPanel(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        drawPanel(rect)
        drawText(copy.riskTitle, rect: NSRect(x: rect.minX + 16, y: rect.minY + 14, width: rect.width - 32, height: 18), font: .systemFont(ofSize: 13.5, weight: .bold), color: .white)
        let categories = storagePlatformCategories()
        let totalBytes = categories.reduce(Int64(0)) { $0 + $1.bytes }
        let riskOrder: [StorageRisk] = [.safeToClear, .reviewFirst, .doNotClean]
        let riskTotals = riskOrder.map { risk in
            (risk, categories.filter { $0.id.risk == risk }.reduce(Int64(0)) { $0 + $1.bytes })
        }

        let diameter = min(rect.height - 76, 136)
        let thickness = max(13, diameter * 0.13)
        let center = CGPoint(x: rect.minX + 26 + diameter / 2, y: rect.minY + 42 + (rect.height - 58) / 2)
        let outerRect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        if totalBytes <= 0 {
            fillDonut(in: outerRect, thickness: thickness, color: NSColor.white.withAlphaComponent(0.1))
        } else {
            var angle = -CGFloat.pi / 2
            for (risk, bytes) in riskTotals where bytes > 0 {
                let sweep = CGFloat(Double(bytes) / Double(totalBytes)) * .pi * 2
                fillDonutSegment(center: center, outerRadius: diameter / 2, thickness: thickness, startAngle: angle, endAngle: angle + sweep, color: storageRiskColor(risk).withAlphaComponent(0.92))
                angle += sweep
            }
        }
        drawCentered(storageByteText(totalBytes), rect: NSRect(x: outerRect.minX + 6, y: center.y - 14, width: outerRect.width - 12, height: 17), font: .monospacedDigitSystemFont(ofSize: 13.5, weight: .bold), color: .white)
        drawCentered(detailsSourceTitle(selectedDetailsSource), rect: NSRect(x: outerRect.minX + 6, y: center.y + 4, width: outerRect.width - 12, height: 13), font: .systemFont(ofSize: 9.5, weight: .semibold), color: NSColor.white.withAlphaComponent(0.48))

        let legendX = outerRect.maxX + 20
        for (index, entry) in riskTotals.enumerated() {
            let y = center.y - 44 + CGFloat(index) * 30
            let dimmed = entry.1 <= 0
            let dot = NSRect(x: legendX, y: y + 4, width: 9, height: 9)
            storageRiskColor(entry.0).withAlphaComponent(dimmed ? 0.32 : 1.0).setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawText(copy.riskLabel(entry.0), rect: NSRect(x: legendX + 16, y: y, width: max(40, rect.maxX - legendX - 110), height: 16), font: .systemFont(ofSize: 11.5, weight: .semibold), color: NSColor.white.withAlphaComponent(dimmed ? 0.3 : 0.85))
            let pct = totalBytes > 0 ? Double(entry.1) / Double(totalBytes) * 100 : 0
            let valueText = dimmed ? storageByteText(entry.1) : "\(storageByteText(entry.1)) (\(String(format: "%.1f%%", pct)))"
            drawRight(valueText, rect: NSRect(x: rect.maxX - 16 - 132, y: y, width: 132, height: 16), color: NSColor.white.withAlphaComponent(dimmed ? 0.3 : 0.92), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold))
        }
    }

    private func drawStorageFooter(snap: StorageSnapshot, copy: StorageCopy, rect: NSRect) {
        let buttonFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        var x = rect.maxX
        func placeButton(_ title: String, emphasized: Bool = false) -> NSRect {
            let width = max(72, measuredTextWidth(title, font: buttonFont) + 26)
            x -= width
            let buttonRect = NSRect(x: x, y: rect.minY + 4, width: width, height: 28)
            drawSmallButton(title, rect: buttonRect, emphasized: emphasized)
            x -= 10
            return buttonRect
        }
        storageRefreshRect = placeButton(copy.refreshButton)
        storageExportRect = placeButton(copy.exportReport)
        storageOpenFinderRect = placeButton(copy.openInFinder, emphasized: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let status = isStorageScanning
            ? copy.scanningLabel
            : String(format: copy.scannedAtFormat, formatter.string(from: snap.scannedAt))
        let caveatText = "⚠︎ \(copy.caveat)  ·  \(status)"
        drawTruncatedText(caveatText, rect: NSRect(x: rect.minX, y: rect.minY + 10, width: max(60, x - rect.minX - 12), height: 16), font: .systemFont(ofSize: 10.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.42))
    }

    private func drawStorageRiskChip(_ title: String, color: NSColor, rect: NSRect, fontSize: CGFloat = 10, dimmed: Bool = false) {
        let alpha: CGFloat = dimmed ? 0.4 : 1.0
        color.withAlphaComponent(0.14 * alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        color.withAlphaComponent(0.55 * alpha).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 2, dy: 0), font: .systemFont(ofSize: fontSize, weight: .semibold), color: color.withAlphaComponent(alpha))
    }

    private func measuredTextHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 600),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        return ceil(bounding.height)
    }

    private func drawStorageSourceTooltip(container: NSRect) {
        guard let hoveredStorageSourceID,
              let row = storageSourceRowRects[hoveredStorageSourceID] else {
            return
        }
        let copy = AppLanguage.current.storageCopy
        let categoryCopy = copy.categories(hoveredStorageSourceID)
        let width: CGFloat = 270
        let bodyFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let body = categoryCopy.purpose
        let impact = categoryCopy.impact
        let bodyH = measuredTextHeight(body, font: bodyFont, width: width - 24)
        let impactH = measuredTextHeight(impact, font: bodyFont, width: width - 24)
        let height = 12 + 18 + 6 + bodyH + 8 + impactH + 12
        var origin = CGPoint(x: row.maxX - width - 40, y: row.maxY + 8)
        if origin.y + height > container.maxY - 8 {
            origin.y = row.minY - height - 8
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, origin.y)
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()

        drawText(categoryCopy.name, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 10, width: width - 24, height: 15), font: .systemFont(ofSize: 11, weight: .bold), color: NSColor.white.withAlphaComponent(0.92))
        drawMultilineText(body, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 34, width: width - 24, height: bodyH + 2), font: bodyFont, color: NSColor.white.withAlphaComponent(0.78))
        drawMultilineText(impact, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 34 + bodyH + 8, width: width - 24, height: impactH + 2), font: bodyFont, color: NSColor.white.withAlphaComponent(0.5))
    }

    private func drawStorageGrowthTooltip(container: NSRect) {
        guard let hoveredStorageCellKey,
              let cell = storageGrowthCells.first(where: { $0.key == hoveredStorageCellKey }) else {
            return
        }
        let copy = AppLanguage.current.storageCopy
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let titleFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let rows: [(NSColor, String, Int64)] = cell.rows.prefix(5).map {
            (storageCategoryColor($0.0), copy.categories($0.0).name, $0.1)
        }
        let labelWidth = min(130, max(60, (rows.map { measuredTextWidth($0.1, font: labelFont) }.max() ?? 0) + 16))
        let valueWidth = max(70, (rows.map { measuredTextWidth(storageGrowthText($0.2), font: valueFont) }.max() ?? 0) + 4)
        let titleWidth = measuredTextWidth(cell.title, font: titleFont) + 24
        let width = min(max(max(titleWidth, labelWidth + valueWidth + 56), 200), 320)
        let height = CGFloat(34 + rows.count * 16 + 24)
        let anchor = cell.rect
        let gap: CGFloat = 12
        var origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - height / 2)
        if origin.x + width > container.maxX - 12 {
            origin.x = anchor.minX - gap - width
        }
        if origin.x < container.minX + 12 {
            origin.x = anchor.midX - width / 2
            origin.y = anchor.minY - height - gap
        }
        origin.x = max(container.minX + 12, min(origin.x, container.maxX - width - 12))
        origin.y = max(container.minY + 10, min(origin.y, container.maxY - height - 10))
        let tooltipRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        NSColor(calibratedWhite: 0.055, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: tooltipRect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let border = NSBezierPath(roundedRect: tooltipRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        border.lineWidth = 1
        border.stroke()

        drawText(cell.title, rect: NSRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 8, width: tooltipRect.width - 24, height: 14), font: titleFont, color: NSColor.white.withAlphaComponent(0.82))
        for (index, row) in rows.enumerated() {
            let y = tooltipRect.minY + 28 + CGFloat(index) * 16
            let dot = NSRect(x: tooltipRect.minX + 12, y: y + 3, width: 7, height: 7)
            row.0.setFill()
            NSBezierPath(ovalIn: dot).fill()
            drawText(row.1, rect: NSRect(x: tooltipRect.minX + 25, y: y, width: labelWidth + 20, height: 14), font: labelFont, color: NSColor.white.withAlphaComponent(0.62))
            drawRight(storageGrowthText(row.2), rect: NSRect(x: tooltipRect.maxX - 12 - valueWidth - 20, y: y - 1, width: valueWidth + 20, height: 15), color: NSColor.white.withAlphaComponent(0.88), font: valueFont)
        }
        let separatorY = tooltipRect.minY + 28 + CGFloat(rows.count) * 16 + 3
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSRect(x: tooltipRect.minX + 12, y: separatorY, width: tooltipRect.width - 24, height: 1).fill()
        drawText(copy.totalLabel, rect: NSRect(x: tooltipRect.minX + 12, y: separatorY + 6, width: labelWidth + 20, height: 14), font: .systemFont(ofSize: 10, weight: .semibold), color: NSColor.white.withAlphaComponent(0.78))
        drawRight(storageGrowthText(cell.total), rect: NSRect(x: tooltipRect.maxX - 12 - valueWidth - 20, y: separatorY + 5, width: valueWidth + 20, height: 15), color: .white, font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold))
    }

    private func drawPanel(_ rect: NSRect) {
        panelSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.white.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(1.5, rect.height)), xRadius: 0, yRadius: 0).fill()
        borderColor.setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    private func drawInputFieldBackground(_ rect: NSRect) {
        guard selectedSection == .costs, !rect.isEmpty else { return }
        inputSurfaceColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let focused = costAmountField.currentEditor() != nil && rect == costAmountField.frame
            || paymentStartDayField.currentEditor() != nil && rect == paymentStartDayField.frame
        (focused ? accentBlue.withAlphaComponent(0.72) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    private func drawSmallButton(_ title: String, rect: NSRect, emphasized: Bool = false) {
        (emphasized ? accentBlue.withAlphaComponent(0.72) : NSColor.white.withAlphaComponent(0.12)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        (emphasized ? accentTeal.withAlphaComponent(0.34) : NSColor.white.withAlphaComponent(0.09)).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 6, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: NSColor.white.withAlphaComponent(emphasized ? 0.96 : 0.78))
    }

    private func drawInfoMark(rect: NSRect, highlighted: Bool) {
        (highlighted ? accentTeal.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.10)).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        (highlighted ? accentTeal.withAlphaComponent(0.74) : NSColor.white.withAlphaComponent(0.18)).setStroke()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).stroke()
        drawCentered("?", rect: rect.offsetBy(dx: 0, dy: -0.5), font: .systemFont(ofSize: 10, weight: .bold), color: highlighted ? accentTeal : NSColor.white.withAlphaComponent(0.58))
    }

    private func drawSelectablePill(_ title: String, rect: NSRect, selected: Bool) {
        if selected {
            accentBlue.withAlphaComponent(0.72).setFill()
        } else {
            inputSurfaceColor.withAlphaComponent(0.82).setFill()
        }
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (selected ? accentTeal.withAlphaComponent(0.38) : borderColor).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        drawCentered(title, rect: rect.insetBy(dx: 8, dy: 0), font: .systemFont(ofSize: 12, weight: .semibold), color: .white)
    }

    private func contributionColor(_ intensity: Double) -> NSColor {
        if intensity <= 0 { return NSColor.white.withAlphaComponent(0.08) }
        if intensity < 0.25 { return accentTeal.withAlphaComponent(0.30) }
        if intensity < 0.50 { return accentTeal.withAlphaComponent(0.52) }
        if intensity < 0.75 { return accentTeal.withAlphaComponent(0.74) }
        return accentTeal
    }

    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawTruncatedText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func drawMultilineText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func fillDonut(in outerRect: NSRect, thickness: CGFloat, color: NSColor) {
        let innerRect = outerRect.insetBy(dx: thickness, dy: thickness)
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.appendOval(in: outerRect)
        path.appendOval(in: innerRect)
        color.setFill()
        path.fill()
    }

    private func fillDonutSegment(center: CGPoint, outerRadius: CGFloat, thickness: CGFloat, startAngle: CGFloat, endAngle: CGFloat, color: NSColor) {
        let innerRadius = max(0, outerRadius - thickness)
        let path = NSBezierPath()
        let startDegrees = startAngle * 180 / .pi
        let endDegrees = endAngle * 180 / .pi
        path.appendArc(withCenter: center, radius: outerRadius, startAngle: startDegrees, endAngle: endDegrees, clockwise: false)
        path.appendArc(withCenter: center, radius: innerRadius, startAngle: endDegrees, endAngle: startDegrees, clockwise: true)
        path.close()
        color.setFill()
        path.fill()
    }

    private func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func drawCentered(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.minX,
            y: rect.midY - ceil(size.height) / 2,
            width: rect.width,
            height: ceil(size.height)
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func drawRight(_ text: String, rect: NSRect, color: NSColor, font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
