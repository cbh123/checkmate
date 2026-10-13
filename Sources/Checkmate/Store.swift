import AppKit
import Foundation
import ServiceManagement

struct StatusDisplay {
    let image: NSImage
    let title: String
}

@MainActor
final class Store: ObservableObject {
    @Published var token: String {
        didSet { debounce("token") { await self.tokenChanged() } }
    }
    @Published var repo: String {
        didSet {
            UserDefaults.standard.set(repo, forKey: "repo")
            runs = []
            defaultBranch = nil
            debounce("repo") { await self.loadWorkflows() }
        }
    }
    @Published var workflowID: Int? {
        didSet {
            UserDefaults.standard.set(workflowID, forKey: "workflowID")
            if let name = workflows.first(where: { $0.id == workflowID })?.name { workflowName = name }
            filtersChanged()
        }
    }
    @Published var branch: String {
        didSet {
            UserDefaults.standard.set(branch, forKey: "branch")
            filtersChanged()
        }
    }
    @Published var onlyMine: Bool {
        didSet {
            UserDefaults.standard.set(onlyMine, forKey: "onlyMine")
            filtersChanged()
        }
    }
    @Published private(set) var workflowName: String {
        didSet { UserDefaults.standard.set(workflowName, forKey: "workflowName") }
    }

    @Published private(set) var repos: [Repo] = []
    @Published private(set) var workflows: [Workflow] = []
    @Published private(set) var runs: [WorkflowRun] = []
    /// Rows hide the branch name when it's this one.
    @Published private(set) var defaultBranch: String?
    @Published private(set) var error: String?
    @Published private(set) var lastUpdated: Date?
    /// Ticks every second while a run is active so elapsed times stay live.
    @Published private(set) var now = Date()

    private var viewer: String?
    private var debounced: [String: Task<Void, Never>] = [:]

    init() {
        let defaults = UserDefaults.standard
        token = Keychain.read() ?? ""
        repo = defaults.string(forKey: "repo") ?? ""
        workflowID = defaults.object(forKey: "workflowID") as? Int
        workflowName = defaults.string(forKey: "workflowName") ?? ""
        branch = defaults.string(forKey: "branch") ?? ""
        onlyMine = defaults.bool(forKey: "onlyMine")
    }

    var isConfigured: Bool { !apiToken.isEmpty && trimmedRepo.contains("/") && workflowID != nil }
    var latest: WorkflowRun? { runs.first }

    /// Median wall-clock time of the last 10 successful runs.
    var estimate: TimeInterval? {
        let durations = runs.filter { $0.state == .success }.prefix(10).map { $0.duration(at: now) }.sorted()
        return durations.isEmpty ? nil : durations[durations.count / 2]
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private var apiToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedRepo: String { repo.trimmingCharacters(in: .whitespaces) }
    private var trimmedBranch: String { branch.trimmingCharacters(in: .whitespaces) }
    private var client: GitHub { GitHub(token: apiToken) }
    private var queryKey: String { "\(trimmedRepo)|\(workflowID ?? 0)|\(trimmedBranch)|\(onlyMine)" }

    // MARK: - Loading

    func start() {
        Task {
            while true {
                await refresh()
                let seconds: UInt64 = latest?.isActive == true ? 10 : 30
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if latest?.isActive == true { now = Date() }
            }
        }
    }

    func refresh() async {
        guard isConfigured, let workflowID else { return }
        let key = queryKey
        do {
            if onlyMine, viewer == nil { viewer = try await client.viewer() }
            var branchName = defaultBranch
            if branchName == nil { branchName = try? await client.defaultBranch(repo: trimmedRepo) }
            let fetched = try await client.runs(
                repo: trimmedRepo,
                workflowID: workflowID,
                branch: trimmedBranch,
                actor: onlyMine ? viewer : nil
            )
            // Drop responses for settings that changed while the request was in flight.
            guard key == queryKey else { return }
            defaultBranch = branchName
            runs = fetched
            error = nil
            lastUpdated = Date()
            now = Date()
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
    }

    func loadRepos() async {
        guard !apiToken.isEmpty else { return }
        do {
            repos = try await client.repos()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadWorkflows() async {
        guard !apiToken.isEmpty, trimmedRepo.contains("/") else {
            workflows = []
            return
        }
        do {
            workflows = try await client.workflows(repo: trimmedRepo).filter { $0.state == "active" }
            if let workflowID, !workflows.contains(where: { $0.id == workflowID }) { self.workflowID = nil }
            error = nil
        } catch {
            workflows = []
            self.error = error.localizedDescription
        }
    }

    private func tokenChanged() async {
        Keychain.save(apiToken)
        viewer = nil
        repos = []
        await loadRepos()
        await loadWorkflows()
        await refresh()
    }

    private func filtersChanged() {
        runs = []
        debounce("filters") { await self.refresh() }
    }

    private func debounce(_ key: String, _ action: @escaping @MainActor () async -> Void) {
        debounced[key]?.cancel()
        debounced[key] = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    // MARK: - Presentation

    var statusDisplay: StatusDisplay {
        guard isConfigured, let latest else {
            let symbol = error == nil ? "chart.bar.fill" : "exclamationmark.triangle"
            return StatusDisplay(image: StatusGlyph.symbol(symbol), title: "")
        }
        return StatusDisplay(
            image: StatusGlyph.progress(progress(of: latest), color: color(of: latest)),
            title: shortStatus(of: latest)
        )
    }

    /// Elapsed time as a fraction of the estimate. Exceeds 1 when a run is slower than usual.
    func progress(of run: WorkflowRun) -> Double {
        switch run.state {
        case .queued: return 0
        case .running:
            guard let estimate, estimate > 0 else { return 0 }
            return run.duration(at: now) / estimate
        case .success, .failure, .cancelled: return 1
        }
    }

    func color(of run: WorkflowRun) -> NSColor {
        switch run.state {
        case .queued, .cancelled: return .systemGray
        case .running: return progress(of: run) > 1 ? .systemOrange : .systemBlue
        case .success: return .systemGreen
        case .failure: return .systemRed
        }
    }

    /// Text next to the menu bar glyph.
    func shortStatus(of run: WorkflowRun) -> String {
        switch run.state {
        case .queued: return "queued"
        case .running:
            let elapsed = run.duration(at: now)
            guard let estimate else { return formatDuration(elapsed) }
            return elapsed <= estimate ? "\(Int(elapsed / estimate * 100))%" : "+" + formatDuration(elapsed - estimate)
        case .success: return "✓"
        case .failure: return "✗"
        case .cancelled: return ""
        }
    }

    /// Right-hand text on a popover row.
    func rowDetail(of run: WorkflowRun) -> String {
        switch run.state {
        case .queued: return "queued"
        case .running:
            let elapsed = run.duration(at: now)
            guard let estimate else { return formatDuration(elapsed) }
            if elapsed > estimate { return "+\(formatDuration(elapsed - estimate)) over" }
            return "\(Int(elapsed / estimate * 100))% · \(formatDuration(estimate - elapsed)) left"
        case .success, .failure, .cancelled: return formatDuration(run.duration(at: now))
        }
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
