import Foundation

// MARK: - Local Storage Usage Scanner

extension QuotaViewOption: Codable {}

enum StorageRisk: String, Codable {
    case safeToClear
    case reviewFirst
    case doNotClean
}

enum StorageCategoryID: String, CaseIterable, Codable {
    case codexSessions = "codex-sessions"
    case codexWorktrees = "codex-worktrees"
    case codexBackups = "codex-backups"
    case codexDatabase = "codex-database"
    case codexImages = "codex-images"
    case codexPlugins = "codex-plugins"
    case codexOther = "codex-other"
    case claudeProjects = "claude-projects"
    case claudeOther = "claude-other"

    var platform: QuotaViewOption {
        switch self {
        case .claudeProjects, .claudeOther:
            return .claude
        default:
            return .codex
        }
    }

    var risk: StorageRisk {
        switch self {
        case .codexSessions, .codexWorktrees, .codexBackups, .claudeProjects:
            return .reviewFirst
        case .codexDatabase, .codexImages, .codexPlugins, .codexOther, .claudeOther:
            return .doNotClean
        }
    }
}

struct StorageCategoryUsage: Codable {
    let id: StorageCategoryID
    var bytes: Int64 = 0
    var fileCount: Int = 0
    var newestModified: Date?
    var roots: [String] = []
}

struct StorageProjectUsage: Codable {
    let name: String
    let path: String
    let platform: QuotaViewOption
    var bytes: Int64 = 0
    var fileCount: Int = 0
    var newestModified: Date?
}

struct StorageSnapshot: Codable {
    let scannedAt: Date
    var categories: [StorageCategoryUsage]
    /// day (yyyy-MM-dd, app timezone) -> category raw id -> bytes modified that day
    var dailyGrowth: [String: [String: Int64]]
    /// day (yyyy-MM-dd, app timezone) -> category raw id -> files modified that day
    var dailyGrowthFiles: [String: [String: Int]] = [:]
    var growthDays: [String] = []
    var projects: [StorageProjectUsage] = []

    func category(_ id: StorageCategoryID) -> StorageCategoryUsage? {
        categories.first { $0.id == id }
    }

    func totalBytes(platform: QuotaViewOption) -> Int64 {
        categories
            .filter { platform == .all || $0.id.platform == platform }
            .reduce(0) { $0 + $1.bytes }
    }

    func totalFileCount(platform: QuotaViewOption) -> Int {
        categories
            .filter { platform == .all || $0.id.platform == platform }
            .reduce(0) { $0 + $1.fileCount }
    }

    var recentDays: [String] {
        Array(growthDays.suffix(14))
    }

    func recentGrowthBytes(platform: QuotaViewOption) -> Int64 {
        var total: Int64 = 0
        for day in recentDays {
            guard let perCategory = dailyGrowth[day] else { continue }
            for (raw, bytes) in perCategory {
                guard let id = StorageCategoryID(rawValue: raw),
                      platform == .all || id.platform == platform else { continue }
                total += bytes
            }
        }
        return total
    }

    func recentGrowthFiles(platform: QuotaViewOption) -> Int {
        var total = 0
        for day in recentDays {
            guard let perCategory = dailyGrowthFiles[day] else { continue }
            for (raw, files) in perCategory {
                guard let id = StorageCategoryID(rawValue: raw),
                      platform == .all || id.platform == platform else { continue }
                total += files
            }
        }
        return total
    }
}

enum StorageSnapshotCacheStore {
    static var cacheURL: URL {
        AppSettings.appSupportDirectoryURL.appendingPathComponent("storage-snapshot-cache.json")
    }

    static func read() -> StorageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StorageSnapshot.self, from: data)
    }

    static func write(_ snapshot: StorageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: AppSettings.appSupportDirectoryURL, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: [.atomic])
    }
}

enum StorageScanner {
    static let growthWindowDays = 90

    static func scan() -> StorageSnapshot {
        var usages: [StorageCategoryID: StorageCategoryUsage] = [:]
        for id in StorageCategoryID.allCases {
            usages[id] = StorageCategoryUsage(id: id)
        }
        var dailyGrowth: [String: [String: Int64]] = [:]
        var dailyGrowthFiles: [String: [String: Int]] = [:]

        let formatter = dayFormatter()
        let now = Date()
        let growthCutoff = now.addingTimeInterval(-TimeInterval(growthWindowDays) * 86_400)

        for root in codexRootURLs() {
            scanPlatformRoot(
                root,
                classify: classifyCodexEntry,
                usages: &usages,
                dailyGrowth: &dailyGrowth,
                dailyGrowthFiles: &dailyGrowthFiles,
                growthCutoff: growthCutoff,
                formatter: formatter
            )
        }

        for root in claudeRootURLs() {
            scanPlatformRoot(
                root,
                classify: classifyClaudeEntry,
                usages: &usages,
                dailyGrowth: &dailyGrowth,
                dailyGrowthFiles: &dailyGrowthFiles,
                growthCutoff: growthCutoff,
                formatter: formatter
            )
        }

        // Claude projects roots configured outside the Claude home (CLAUDE_CONFIG_DIR / XDG)
        // are scanned separately when they were not covered above.
        let claudeHomes = claudeRootURLs().map { $0.standardizedFileURL.path }
        for projects in AppSettings.claudeLogFolderURLs {
            let path = projects.standardizedFileURL.path
            let coveredByHome = claudeHomes.contains { path.hasPrefix($0 + "/") }
            guard !coveredByHome, FileManager.default.fileExists(atPath: path) else { continue }
            accumulate(
                entry: projects,
                into: .claudeProjects,
                usages: &usages,
                dailyGrowth: &dailyGrowth,
                dailyGrowthFiles: &dailyGrowthFiles,
                growthCutoff: growthCutoff,
                formatter: formatter
            )
        }

        var days: [String] = []
        var cursor = growthCutoff
        while cursor <= now {
            days.append(formatter.string(from: cursor))
            cursor = cursor.addingTimeInterval(86_400)
        }

        let categories = StorageCategoryID.allCases.compactMap { usages[$0] }
        return StorageSnapshot(
            scannedAt: now,
            categories: categories,
            dailyGrowth: dailyGrowth,
            dailyGrowthFiles: dailyGrowthFiles,
            growthDays: days,
            projects: scanProjects()
        )
    }

    static func codexRootURLs() -> [URL] {
        var roots = [AppSettings.defaultCodexHomeURL]
        if let custom = AppSettings.environmentCodexHomeURL {
            roots.append(custom)
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func claudeRootURLs() -> [URL] {
        [AppSettings.defaultClaudeHomeURL]
    }

    private static func scanPlatformRoot(
        _ root: URL,
        classify: (URL) -> StorageCategoryID,
        usages: inout [StorageCategoryID: StorageCategoryUsage],
        dailyGrowth: inout [String: [String: Int64]],
        dailyGrowthFiles: inout [String: [String: Int]],
        growthCutoff: Date,
        formatter: DateFormatter
    ) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return
        }
        for entry in entries {
            accumulate(
                entry: entry,
                into: classify(entry),
                usages: &usages,
                dailyGrowth: &dailyGrowth,
                dailyGrowthFiles: &dailyGrowthFiles,
                growthCutoff: growthCutoff,
                formatter: formatter
            )
        }
    }

    private static func accumulate(
        entry: URL,
        into id: StorageCategoryID,
        usages: inout [StorageCategoryID: StorageCategoryUsage],
        dailyGrowth: inout [String: [String: Int64]],
        dailyGrowthFiles: inout [String: [String: Int]],
        growthCutoff: Date,
        formatter: DateFormatter
    ) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        let fileManager = FileManager.default
        var bytes: Int64 = 0
        var fileCount = 0
        var newest: Date?

        func addFile(_ url: URL) {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return
            }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            bytes += size
            fileCount += 1
            if let modified = values.contentModificationDate {
                if newest.map({ modified > $0 }) ?? true {
                    newest = modified
                }
                if modified >= growthCutoff, size > 0 {
                    let day = formatter.string(from: modified)
                    dailyGrowth[day, default: [:]][id.rawValue, default: 0] += size
                    dailyGrowthFiles[day, default: [:]][id.rawValue, default: 0] += 1
                }
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            if let enumerator = fileManager.enumerator(at: entry, includingPropertiesForKeys: Array(keys), options: []) {
                for case let url as URL in enumerator {
                    addFile(url)
                }
            }
        } else {
            addFile(entry)
        }

        guard var usage = usages[id] else { return }
        usage.bytes += bytes
        usage.fileCount += fileCount
        if let newest {
            if usage.newestModified.map({ newest > $0 }) ?? true {
                usage.newestModified = newest
            }
        }
        if !usage.roots.contains(entry.path) {
            usage.roots.append(entry.path)
        }
        usages[id] = usage
    }

    private static func classifyCodexEntry(_ url: URL) -> StorageCategoryID {
        let name = url.lastPathComponent.lowercased()
        if name == "sessions" || name == "archived_sessions" {
            return .codexSessions
        }
        if name.contains("worktree") {
            return .codexWorktrees
        }
        if name.contains("backup") || name.contains("recovery") {
            return .codexBackups
        }
        if name == "sqlite" || name.contains(".sqlite") || name.hasSuffix(".db") || name.hasSuffix(".wal") || name.hasSuffix(".shm") {
            return .codexDatabase
        }
        if name == "generated_images" || name == "images" {
            return .codexImages
        }
        if name == "plugins" || name == "vendor_imports" || name == "extensions" {
            return .codexPlugins
        }
        return .codexOther
    }

    private static func classifyClaudeEntry(_ url: URL) -> StorageCategoryID {
        url.lastPathComponent.lowercased() == "projects" ? .claudeProjects : .claudeOther
    }

    // MARK: Project attribution

    private static func scanProjects() -> [StorageProjectUsage] {
        var byPath: [String: StorageProjectUsage] = [:]

        func add(path: String, platform: QuotaViewOption, bytes: Int64, files: Int, modified: Date?) {
            let key = "\(platform.rawValue)|\(path)"
            var usage = byPath[key] ?? StorageProjectUsage(
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                platform: platform
            )
            usage.bytes += bytes
            usage.fileCount += files
            if let modified {
                if usage.newestModified.map({ modified > $0 }) ?? true {
                    usage.newestModified = modified
                }
            }
            byPath[key] = usage
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        let fileManager = FileManager.default

        for root in codexRootURLs() {
            for folder in ["sessions", "archived_sessions"] {
                let dir = root.appendingPathComponent(folder, isDirectory: true)
                guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: Array(keys), options: []) else { continue }
                for case let url as URL in enumerator {
                    guard url.pathExtension == "jsonl",
                          let values = try? url.resourceValues(forKeys: keys),
                          values.isRegularFile == true else { continue }
                    let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    guard let cwd = readSessionCwd(url) else { continue }
                    add(path: cwd, platform: .codex, bytes: size, files: 1, modified: values.contentModificationDate)
                }
            }
        }

        for projectsRoot in AppSettings.claudeLogFolderURLs {
            guard let subdirs = try? fileManager.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }
            for subdir in subdirs {
                guard (try? subdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                var bytes: Int64 = 0
                var files = 0
                var newest: Date?
                var cwd: String?
                if let enumerator = fileManager.enumerator(at: subdir, includingPropertiesForKeys: Array(keys), options: []) {
                    for case let url as URL in enumerator {
                        guard let values = try? url.resourceValues(forKeys: keys),
                              values.isRegularFile == true else { continue }
                        bytes += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                        files += 1
                        if let modified = values.contentModificationDate,
                           newest.map({ modified > $0 }) ?? true {
                            newest = modified
                        }
                        if cwd == nil, url.pathExtension == "jsonl" {
                            cwd = readSessionCwd(url)
                        }
                    }
                }
                guard bytes > 0 else { continue }
                let path = cwd ?? subdir.lastPathComponent
                add(path: path, platform: .claude, bytes: bytes, files: files, modified: newest)
            }
        }

        let all = byPath.values.sorted { $0.bytes > $1.bytes }
        let codexTop = all.filter { $0.platform == .codex }.prefix(30)
        let claudeTop = all.filter { $0.platform == .claude }.prefix(30)
        return (Array(codexTop) + Array(claudeTop)).sorted { $0.bytes > $1.bytes }
    }

    /// Reads the head of a session JSONL file and extracts the first "cwd" value.
    private static func readSessionCwd(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536), !data.isEmpty else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let marker = text.range(of: "\"cwd\":\"") else { return nil }
        var path = ""
        var escaped = false
        for character in text[marker.upperBound...] {
            if escaped {
                switch character {
                case "n": path.append("\n")
                case "t": path.append("\t")
                case "\\": path.append("\\")
                case "\"": path.append("\"")
                default: path.append(character)
                }
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "\"" {
                break
            }
            path.append(character)
        }
        return path.isEmpty ? nil : path
    }
}

func storageByteText(_ bytes: Int64) -> String {
    let absolute = Double(abs(bytes))
    let sign = bytes < 0 ? "-" : ""
    if absolute >= 1_073_741_824 {
        return String(format: "%@%.1f GB", sign, absolute / 1_073_741_824)
    }
    if absolute >= 1_048_576 {
        return String(format: "%@%.0f MB", sign, absolute / 1_048_576)
    }
    if absolute >= 1024 {
        return String(format: "%@%.0f KB", sign, absolute / 1024)
    }
    return "\(sign)\(Int(absolute)) B"
}

func storageGrowthText(_ bytes: Int64) -> String {
    bytes >= 0 ? "+\(storageByteText(bytes))" : storageByteText(bytes)
}
