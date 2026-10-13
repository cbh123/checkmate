import Foundation

struct Repo: Decodable, Identifiable, Hashable {
    let id: Int
    let fullName: String
}

struct Workflow: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let state: String
}

struct WorkflowRun: Decodable, Identifiable, Equatable {
    struct User: Decodable, Equatable {
        let login: String
    }

    enum State {
        case queued, running, success, failure, cancelled
    }

    let id: Int
    let runNumber: Int
    let displayTitle: String
    let headBranch: String?
    let event: String
    let status: String
    let conclusion: String?
    let htmlUrl: URL
    let createdAt: Date
    let updatedAt: Date
    let runStartedAt: Date?
    let actor: User?

    var state: State {
        switch status {
        case "completed":
            switch conclusion ?? "" {
            case "success": return .success
            case "failure", "timed_out", "startup_failure": return .failure
            default: return .cancelled
            }
        case "in_progress": return .running
        default: return .queued
        }
    }

    var isActive: Bool { status != "completed" }

    /// Wall-clock time. GitHub has no end timestamp for runs, so completed runs use `updated_at`.
    func duration(at now: Date) -> TimeInterval {
        (isActive ? now : updatedAt).timeIntervalSince(runStartedAt ?? createdAt)
    }
}

struct GitHubError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct APIError: Decodable {
    let message: String
}

struct GitHub {
    let token: String

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func viewer() async throws -> String {
        struct User: Decodable { let login: String }
        let user: User = try await get("/user")
        return user.login
    }

    func repos() async throws -> [Repo] {
        try await get("/user/repos", query: ["per_page": "100", "sort": "pushed"])
    }

    func defaultBranch(repo: String) async throws -> String {
        struct Response: Decodable { let defaultBranch: String }
        let response: Response = try await get("/repos/\(repo)")
        return response.defaultBranch
    }

    func workflows(repo: String) async throws -> [Workflow] {
        struct Response: Decodable { let workflows: [Workflow] }
        let response: Response = try await get("/repos/\(repo)/actions/workflows", query: ["per_page": "100"])
        return response.workflows
    }

    func runs(repo: String, workflowID: Int, branch: String, actor: String?) async throws -> [WorkflowRun] {
        struct Response: Decodable { let workflowRuns: [WorkflowRun] }
        var query = ["per_page": "20", "exclude_pull_requests": "true"]
        if !branch.isEmpty { query["branch"] = branch }
        if let actor { query["actor"] = actor }
        let response: Response = try await get("/repos/\(repo)/actions/workflows/\(workflowID)/runs", query: query)
        return response.workflowRuns
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        guard var components = URLComponents(string: "https://api.github.com" + path) else {
            throw GitHubError(message: "Invalid path \(path)")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw GitHubError(message: "Invalid path \(path)") }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.message ?? "Request failed"
            throw GitHubError(message: "GitHub \(status): \(message)")
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
