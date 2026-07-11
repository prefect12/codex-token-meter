import Foundation

struct InsightRecommendationText {
    let title: String
    let body: String
}
struct InsightCopy {
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

extension AppLanguage {
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
