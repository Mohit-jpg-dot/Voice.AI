import Foundation

public enum TaskStatus: String, Codable, Sendable {
    case queued = "Queued"
    case running = "Running"
    case paused = "Paused"
    case done = "Done"
    case failed = "Failed"
    case awaitingApproval = "Awaiting Approval"
}

public struct TaskRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let prompt: String
    public let appName: String
    public let actionName: String
    public var status: TaskStatus
    public var progress: Double // 0.0 to 1.0
    public var elapsedSeconds: Double
    public let deepLinkURL: String
    public let timestamp: Date
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        prompt: String,
        appName: String,
        actionName: String,
        status: TaskStatus = .queued,
        progress: Double = 0.0,
        elapsedSeconds: Double = 0.0,
        deepLinkURL: String = "",
        timestamp: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.appName = appName
        self.actionName = actionName
        self.status = status
        self.progress = progress
        self.elapsedSeconds = elapsedSeconds
        self.deepLinkURL = deepLinkURL
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }
}

public struct DayGroupedTasks: Sendable {
    public let dayLabel: String // "Today", "Yesterday", "Earlier"
    public let tasks: [TaskRecord]

    public init(dayLabel: String, tasks: [TaskRecord]) {
        self.dayLabel = dayLabel
        self.tasks = tasks
    }
}

/// Actor/Class managing running background tasks, queue concurrency, mid-flight cancellation,
/// day-grouped history, search, export, and encrypted-at-rest persistence.
public final class PersistentTaskManager: @unchecked Sendable {
    public static let shared = PersistentTaskManager()

    private let lock = NSLock()
    private var tasks: [TaskRecord] = []
    private let storageURL: URL

    public init(storageURL: URL? = nil) {
        if let customURL = storageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent(AppBrand.appSupportFolderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("task_history_encrypted.json")
        }
        loadFromStorage()
    }

    // --- Active Queue Management ---

    @discardableResult
    public func enqueue(prompt: String, app: String, action: String, deepLink: String = "", status: TaskStatus = .queued) -> TaskRecord {
        lock.lock()
        defer {
            lock.unlock()
            saveToStorage()
        }

        let task = TaskRecord(
            prompt: prompt,
            appName: app,
            actionName: action,
            status: status,
            progress: status == .running ? 0.1 : 0.0,
            elapsedSeconds: 0.0,
            deepLinkURL: deepLink,
            timestamp: Date()
        )
        tasks.insert(task, at: 0)
        return task
    }

    public func updateProgress(id: UUID, progress: Double, elapsed: Double) {
        lock.lock()
        defer {
            lock.unlock()
            saveToStorage()
        }
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].progress = min(1.0, max(0.0, progress))
            tasks[idx].elapsedSeconds = elapsed
            if progress >= 1.0 {
                tasks[idx].status = .done
            }
        }
    }

    public func markDone(id: UUID, elapsed: Double) {
        lock.lock()
        defer {
            lock.unlock()
            saveToStorage()
        }
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].status = .done
            tasks[idx].progress = 1.0
            tasks[idx].elapsedSeconds = elapsed
        }
    }

    public func cancel(id: UUID) {
        lock.lock()
        defer {
            lock.unlock()
            saveToStorage()
        }
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].status = .failed
            tasks[idx].errorMessage = "Cancelled by user"
        }
    }

    public func pause(id: UUID) {
        lock.lock()
        defer {
            lock.unlock()
            saveToStorage()
        }
        if let idx = tasks.firstIndex(where: { $0.id == id && $0.status == .running }) {
            tasks[idx].status = .paused
        }
    }

    public func resume(id: UUID) {
        lock.lock()
        defer {
            lock.unlock()
            saveToStorage()
        }
        if let idx = tasks.firstIndex(where: { $0.id == id && $0.status == .paused }) {
            tasks[idx].status = .running
        }
    }

    public func retry(id: UUID) -> TaskRecord? {
        lock.lock()
        defer {
            lock.unlock()
            saveToStorage()
        }
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        tasks[idx].status = .running
        tasks[idx].progress = 0.0
        tasks[idx].errorMessage = nil
        return tasks[idx]
    }

    // --- Day Grouping & Search ---

    public func getRunningTasks() -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }
        return tasks.filter { $0.status == .running || $0.status == .queued || $0.status == .paused }
    }

    public func getAllTasks() -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }
        return tasks
    }

    public func getDayGroupedHistory(query: String = "") -> [DayGroupedTasks] {
        lock.lock()
        defer { lock.unlock() }

        let filtered: [TaskRecord]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = tasks
        } else {
            let q = query.lowercased()
            filtered = tasks.filter {
                $0.prompt.lowercased().contains(q) ||
                $0.appName.lowercased().contains(q) ||
                $0.actionName.lowercased().contains(q) ||
                ($0.errorMessage?.lowercased().contains(q) ?? false)
            }
        }

        let calendar = Calendar.current
        var today: [TaskRecord] = []
        var yesterday: [TaskRecord] = []
        var earlier: [TaskRecord] = []

        for task in filtered {
            if calendar.isDateInToday(task.timestamp) {
                today.append(task)
            } else if calendar.isDateInYesterday(task.timestamp) {
                yesterday.append(task)
            } else {
                earlier.append(task)
            }
        }

        var groups: [DayGroupedTasks] = []
        if !today.isEmpty { groups.append(DayGroupedTasks(dayLabel: "Today", tasks: today)) }
        if !yesterday.isEmpty { groups.append(DayGroupedTasks(dayLabel: "Yesterday", tasks: yesterday)) }
        if !earlier.isEmpty { groups.append(DayGroupedTasks(dayLabel: "Earlier", tasks: earlier)) }
        return groups
    }

    // --- Export ---

    public func exportJSON() -> String {
        lock.lock()
        defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tasks), let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    public func exportMarkdown() -> String {
        lock.lock()
        defer { lock.unlock() }
        var md = "# \(AppBrand.name) Task & Session History\n\n"
        md += "| Time | App | Prompt | Action | Status | Duration | Deep Link |\n"
        md += "| :--- | :--- | :--- | :--- | :--- | :--- | :--- |\n"

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short

        for t in tasks {
            let link = t.deepLinkURL.isEmpty ? "—" : "[Open](\(t.deepLinkURL))"
            let timeStr = df.string(from: t.timestamp)
            md += "| \(timeStr) | \(t.appName) | \(t.prompt.replacingOccurrences(of: "|", with: "\\|")) | \(t.actionName) | \(t.status.rawValue) | \(String(format: "%.1fs", t.elapsedSeconds)) | \(link) |\n"
        }
        return md
    }

    // --- Persistence (Encrypted-at-Rest Mock / Storage) ---

    private func saveToStorage() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tasks) {
            // XOR / lightweight obfuscation simulating encryption-at-rest key
            let obfuscated = Data(data.map { $0 ^ 0x5A })
            try? obfuscated.write(to: storageURL, options: .atomic)
        }
    }

    private func loadFromStorage() {
        guard let raw = try? Data(contentsOf: storageURL) else { return }
        let deobfuscated = Data(raw.map { $0 ^ 0x5A })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([TaskRecord].self, from: deobfuscated) {
            self.tasks = loaded
        }
    }
}

