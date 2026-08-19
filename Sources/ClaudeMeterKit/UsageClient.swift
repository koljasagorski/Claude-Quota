import Foundation

/// Talks to the undocumented `/api/oauth/usage` endpoint Claude Code uses.
public actor UsageClient {

    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// The beta header carries a date in its name. If Anthropic retires it the
    /// app fails loudly (visible error state) rather than showing stale numbers.
    public static let betaHeader = "oauth-2025-04-20"
    /// Used only when `claude --version` cannot be resolved.
    public static let fallbackClientVersion = "2.1.235"

    private let session: URLSession
    private let tokenProvider: TokenProvider
    private var cachedUserAgent: String?

    public init(tokenProvider: TokenProvider = TokenProvider(),
                session: URLSession? = nil) {
        self.tokenProvider = tokenProvider
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Fetches once. On 401 the token is re-resolved and exactly one retry is
    /// made — Claude Code may have rotated it moments ago.
    public func fetch() async throws -> UsageSnapshot {
        do {
            return try await performFetch()
        } catch FetchError.unauthorized {
            return try await performFetch()
        }
    }

    private func performFetch() async throws -> UsageSnapshot {
        let credential = try tokenProvider.resolve()
        let userAgent = await resolveUserAgent()

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        // Not optional: without a claude-code User-Agent the request lands in a
        // much harsher rate-limit bucket and returns 429 indefinitely.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw FetchError.transient(error.localizedDescription)
        } catch {
            throw FetchError.transient(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FetchError.transient("keine HTTP-Antwort")
        }

        switch http.statusCode {
        case 200:
            return try UsageParser.parse(data)
        case 401, 403:
            throw FetchError.unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw FetchError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw FetchError.transient("Server antwortete \(http.statusCode)")
        default:
            throw FetchError.transient("Unerwarteter Status \(http.statusCode)")
        }
    }

    // MARK: - User agent

    public func resolveUserAgent() async -> String {
        if let cachedUserAgent { return cachedUserAgent }
        let version = Self.detectClaudeVersion() ?? Self.fallbackClientVersion
        let agent = "claude-code/\(version)"
        cachedUserAgent = agent
        return agent
    }

    /// `claude --version` prints e.g. `2.1.235 (Claude Code)`.
    static func detectClaudeVersion() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.bun/bin/claude"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if let version = runVersion(at: path) { return version }
        }
        return nil
    }

    private static func runVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else { return nil }

        let first = output.split(separator: " ").first.map(String.init)
        guard let first, first.first?.isNumber == true else { return nil }
        return first
    }
}
