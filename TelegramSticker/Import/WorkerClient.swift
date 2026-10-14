import Foundation

nonisolated final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor WorkerClient {
    let configuration: WorkerConfiguration
    private let session: URLSession
    private let gate = RequestGate()
    init(configuration: WorkerConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session { self.session = session } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 45
            config.timeoutIntervalForResource = 120
            config.httpShouldSetCookies = false
            config.urlCache = nil
            self.session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        }
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
        if !thumbnail && (sticker.fileSize ?? 0) > 20 * 1024 * 1024 { throw StickerImportError.tooLarge }
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
        try await gate.acquire()
        defer { Task { await gate.release() } }
        try Task.checkCancellation()
        var components = URLComponents(url: configuration.origin, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = refresh ? [URLQueryItem(name: "refresh", value: "1")] : variant.map { [URLQueryItem(name: "variant", value: $0)] }
        guard let url = components.url else { throw StickerImportError.invalidConfiguration }
        for attempt in 0..<3 {
            do { return try await perform(url) }
            catch is CancellationError { throw CancellationError() }
            catch let error as StickerImportError {
                if case .server(_, let retryable, let delay) = error, retryable, attempt < 2 {
                    try await Task.sleep(for: .seconds(max(1, min(60, delay))))
                } else { throw error }
            } catch let error as URLError {
                if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
                guard attempt < 2, [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) else {
                    throw StickerImportError.network
                }
                try await Task.sleep(for: .seconds(attempt + 1))
            } catch { throw error }
        }
        throw StickerImportError.network
    }
    private func perform(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.accessKey)", forHTTPHeaderField: "Authorization")
        let (file, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: file); throw StickerImportError.invalidResponse
        }
        let limit = url.path.contains("/assets/") ? 20 * 1024 * 1024 : 2 * 1024 * 1024
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= limit else {
            try? FileManager.default.removeItem(at: file); throw StickerImportError.tooLarge
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
