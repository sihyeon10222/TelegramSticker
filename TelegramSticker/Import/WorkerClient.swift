import Foundation

nonisolated final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// Shared across previews, batch downloads and updates; concurrent callers reuse one handshake.
private actor ImportServiceSession {
    static let shared = ImportServiceSession()
    private struct Credential: Decodable, Sendable { let token: String; let expiresAt: Double }
    private var credentials: [URL: Credential] = [:]
    private var pending: [URL: Task<Credential, Error>] = [:]

    func token(origin: URL, session: URLSession) async throws -> String {
        if let credential = credentials[origin], credential.expiresAt > Date().timeIntervalSince1970 + 60 {
            return credential.token
        }
        let task: Task<Credential, Error>
        if let existing = pending[origin] { task = existing }
        else {
            task = Task {
                var request = URLRequest(url: origin.appendingPathComponent("v1/session"))
                request.httpMethod = "POST"
                let (file, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: file) }
                guard let response = response as? HTTPURLResponse else { throw StickerImportError.invalidResponse }
                guard response.statusCode == 200 else {
                    throw StickerImportError.server(code: "http_\(response.statusCode)",
                        retryable: response.statusCode == 429 || response.statusCode >= 500,
                        retryAfter: Int(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2)
                }
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4096 else {
                    throw StickerImportError.invalidResponse
                }
                let credential = try JSONDecoder().decode(Credential.self, from: Data(contentsOf: file))
                let remaining = credential.expiresAt - Date().timeIntervalSince1970
                guard credential.token.hasPrefix("sb1."), credential.token.utf8.count < 256,
                      credential.token.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }),
                      remaining > 0, remaining <= 3700 else { throw StickerImportError.invalidResponse }
                return credential
            }
            pending[origin] = task
        }
        do {
            let credential = try await task.value
            credentials[origin] = credential
            pending[origin] = nil
            return credential.token
        } catch { pending[origin] = nil; throw error }
    }
    func reset() {
        for task in pending.values { task.cancel() }
        pending.removeAll(); credentials.removeAll()
    }
    func invalidate(origin: URL, token: String) {
        if credentials[origin]?.token == token { credentials[origin] = nil }
    }
}

actor WorkerClient {
    let configuration: WorkerConfiguration
    private let session: URLSession
    private let requests = RequestGate(limit: 6)
    init(configuration: WorkerConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session { self.session = session } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 45
            config.timeoutIntervalForResource = 600
            config.httpShouldSetCookies = false
            config.urlCache = nil
            self.session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        }
    }
    static func resetServiceSession() async { await ImportServiceSession.shared.reset() }
    func gallery() async throws -> RemoteGallery {
        let data = try await request(path: "/v1/gallery")
        let catalog = try JSONDecoder().decode(RemoteGallery.self, from: data)
        try catalog.validate()
        return catalog
    }
    func pack(name: String, refresh: Bool = false) async throws -> RemotePack {
        guard StickerLink.validName(name) else { throw StickerImportError.invalidLink }
        let data = try await request(path: "/v1/packs/\(name)", refresh: refresh)
        let result: RemotePack
        do { result = try JSONDecoder().decode(RemotePack.self, from: data) }
        catch { throw StickerImportError.invalidResponse }
        try result.validate(requestedName: name)
        if refresh, result.refreshed != true || result.fetchedAt == nil { throw StickerImportError.refreshUnsupported }
        return result
    }
    func asset(pack: String, sticker: RemoteSticker, thumbnail: Bool = false) async throws -> Data {
        guard StickerLink.validName(pack), sticker.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw StickerImportError.invalidResponse
        }
        if !thumbnail && (sticker.fileSize ?? 0) > 20 * 1024 * 1024 { throw ImportLimitFailure(check: "telegram_declared_bytes", actual: String(sticker.fileSize ?? 0), limit: "20971520 bytes") }
        return try await request(path: "/v1/packs/\(pack)/assets/\(sticker.id)", variant: thumbnail ? "thumbnail" : "original")
    }
    func assetFile(pack: String, sticker: RemoteSticker, destination: URL) async throws -> URL {
        guard StickerLink.validName(pack), sticker.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw StickerImportError.invalidResponse }
        let file = try await requestFile(path: "/v1/packs/\(pack)/assets/\(sticker.id)", variant: "original")
        defer { try? FileManager.default.removeItem(at: file) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }
    private func request(path: String, variant: String? = nil, refresh: Bool = false) async throws -> Data {
        let file = try await requestFile(path: path, variant: variant, refresh: refresh)
        defer { try? FileManager.default.removeItem(at: file) }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }
    private func requestFile(path: String, variant: String? = nil, refresh: Bool = false) async throws -> URL {
        try Task.checkCancellation()
        var components = URLComponents(url: configuration.origin, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = refresh ? [URLQueryItem(name: "refresh", value: "1")] : variant.map { [URLQueryItem(name: "variant", value: $0)] }
        guard let url = components.url else { throw StickerImportError.invalidConfiguration }
        // Asset retry ownership belongs to ImportCoordinator, covering download
        // and conversion together. Avoid multiplying five retries at both levels.
        let maximumRetries = path.contains("/assets/") ? 0 : 5
        for attempt in 0...maximumRetries {
            try await BackgroundWork.shared.waitForExecution()
            try await requests.acquire()
            do {
                try await DownloadRequestBudget.shared.wait(asset: path.contains("/assets/"))
                let file = try await perform(url)
                await requests.release()
                return file
            } catch {
                await requests.release()
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                let description: String
                var delay: Double?
                if case let StickerImportError.server(code, retryable, retryAfter) = error {
                    description = "서버 \(code) · 재시도 가능 \(retryable)"
                    if retryable {
                        await DownloadRequestBudget.shared.backOff(seconds: retryAfter)
                        if attempt < maximumRetries {
                            delay = Double(max(1, retryAfter)) + Double.random(in: 0.2...1.5)
                        }
                    }
                } else if let network = error as? URLError {
                    description = "네트워크 \(network.code.rawValue)"
                    if attempt < maximumRetries, [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet].contains(network.code) {
                        delay = min(30, pow(2, Double(attempt + 1))) + Double.random(in: 0.2...1.5)
                    }
                } else { description = error.localizedDescription }
                let action = delay.map { " · \(Int(ceil($0)))초 뒤 자동 재시도 (\(attempt + 1)/5)" } ?? (maximumRetries == 0 ? " · 항목 재시도 처리로 전달" : (attempt == maximumRetries ? " · 5회 재시도 종료" : " · 재시도 불가"))
                await DownloadDiagnostics.shared.record(path + " · " + description + action + " · " + DownloadDiagnostics.errorDetails(error))
                guard let delay else {
                    if error is URLError { throw StickerImportError.network }
                    throw error
                }
                try await Task.sleep(for: .seconds(delay))
            }
        }
        throw StickerImportError.network
    }
    private func perform(_ url: URL, renewSession: Bool = true) async throws -> URL {
        try await BackgroundWork.shared.waitForExecution()
        var request = URLRequest(url: url)
        let token = configuration.accessKey.isEmpty
            ? try await ImportServiceSession.shared.token(origin: configuration.origin, session: session)
            : configuration.accessKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let started = ContinuousClock.now
        let (file, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: file); throw StickerImportError.invalidResponse
        }
        if response.statusCode == 401, configuration.accessKey.isEmpty, renewSession {
            try? FileManager.default.removeItem(at: file)
            await ImportServiceSession.shared.invalidate(origin: configuration.origin, token: token)
            return try await perform(url, renewSession: false)
        }
        let limit = url.path.contains("/assets/") ? 20 * 1024 * 1024 : 2 * 1024 * 1024
        let actualSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        await DownloadDiagnostics.shared.record("HTTP path=\(url.path) variant=\(url.query ?? "none") status=\(response.statusCode) contentType=\(response.value(forHTTPHeaderField: "Content-Type") ?? "unknown") declaredBytes=\(response.value(forHTTPHeaderField: "Content-Length") ?? "unknown") receivedBytes=\(actualSize) limitBytes=\(limit) elapsed=\(started.duration(to: .now)) retryAfter=\(response.value(forHTTPHeaderField: "Retry-After") ?? "none") cfRay=\(response.value(forHTTPHeaderField: "CF-Ray") ?? "none")")
        guard actualSize <= limit else {
            try? FileManager.default.removeItem(at: file)
            throw ImportLimitFailure(check: url.path.contains("/assets/") ? "download_asset_bytes" : "download_metadata_bytes", actual: String(actualSize), limit: "\(limit) bytes")
        }
        guard response.statusCode == 200 else {
            defer { try? FileManager.default.removeItem(at: file) }
            let data = try Data(contentsOf: file)
            struct Envelope: Decodable { struct Failure: Decodable { let code: String; let retryable: Bool }; let error: Failure }
            let body = try? JSONDecoder().decode(Envelope.self, from: data)
            let status = response.statusCode
            throw StickerImportError.server(code: body?.error.code ?? "http_\(status)",
                retryable: (status == 429 || (500...599).contains(status)) && (body?.error.retryable ?? true),
                retryAfter: Int(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2)
        }
        return file
    }
}
