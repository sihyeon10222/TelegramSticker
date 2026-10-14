#if DEBUG
import Foundation

/// Explicit UI-test launch only; never contacts a server or changes saved credentials.
nonisolated final class ImportPreviewFixture: URLProtocol, @unchecked Sendable {
    static func client() throws -> WorkerClient {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [ImportPreviewFixture.self]
        return WorkerClient(configuration: try WorkerConfiguration(address: "https://ui-fixture.invalid",
            accessKey: "local-ui-fixture-access-key"), session: URLSession(configuration: session))
    }
    /// Self-authored packs for keyboard interaction tests; no sample-creation UI in the app.
    static func prepareKeyboardLibrary(writer: LibraryWriter) async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for (pack, count) in [("keyboard-ui-a", 60), ("keyboard-ui-b", 45)] {
            let installed = try await writer.pack(id: pack)
            let animated = pack == "keyboard-ui-b"
            guard installed == nil || (animated && installed?.stickers.first?.animationPath == nil) else { continue }
            var animationURL: URL?
            if animated {
                guard let source = Bundle.main.url(forResource: "moving-circle", withExtension: "tgs") else {
                    throw LibraryError.invalidImage
                }
                let converted = try await TGSConverter.convert(Data(contentsOf: source))
                defer { try? FileManager.default.removeItem(at: converted.file) }
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                let gif = temporary.appendingPathComponent("test-animation.gif")
                try converted.gif.write(to: gif)
                animationURL = gif
            }
            let names = ["sample-smile", "sample-hearts", "sample-sparkle"]
            let inputs = try (1...count).map { index in
                guard let url = Bundle.main.url(forResource: names[index % 3], withExtension: "png") else {
                    throw LibraryError.invalidImage
                }
                return LocalStickerInput(id: "item-\(index)", name: "스티커 \(index)", url: url,
                                         sourceFormat: animated ? "tgs" : "png", animationURL: animationURL)
            }
            try await writer.install(id: pack, title: animated ? "테스트 팩 B" : "테스트 팩 A", stickers: inputs,
                                     replacingRevision: installed?.revision)
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data: Data
            if request.url!.path.contains("/assets/") {
                let sampleNames = ["sample-smile", "sample-hearts", "sample-sparkle"]
                let sampleIndex = request.url!.path.contains("ui_dense_fixture")
                    ? (Int(String(request.url!.lastPathComponent.suffix(4)), radix: 16) ?? 1) % 3 : 1
                guard let url = Bundle.main.url(forResource: sampleNames[sampleIndex], withExtension: "png") else {
                    throw URLError(.fileDoesNotExist)
                }
                data = try Data(contentsOf: url)
                if ProcessInfo.processInfo.arguments.contains("--partial-import-ui-fixture"),
                   request.url!.lastPathComponent == String(repeating: "b", count: 64),
                   URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "variant" })?.value == "original" {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocol(self, didLoad: Data("broken fixture".utf8))
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }
            } else {
                let dense = request.url!.path.contains("ui_dense_fixture")
                let name = dense ? "ui_dense_fixture" : request.url!.path.contains("ui_partial_fixture") ? "ui_partial_fixture" : "ui_fixture"
                let stickers = dense ? (1...30).map { index in
                    RemoteSticker(id: String(format: "%064x", index), format: "static", width: 512, height: 512,
                        emoji: ["웃는 얼굴", "하트", "별"][index % 3], fileSize: nil, hasThumbnail: true)
                } : [
                    RemoteSticker(id: String(repeating: "a", count: 64), format: "static", width: 512, height: 512,
                                  emoji: "하트", fileSize: nil, hasThumbnail: true),
                    RemoteSticker(id: String(repeating: "b", count: 64), format: "static", width: 512, height: 512,
                                  emoji: nil, fileSize: nil, hasThumbnail: false)
                ]
                data = try JSONEncoder().encode(RemotePack(name: name, title: dense ? "매일 쓰는 스티커" : "로컬 가져오기 테스트",
                    stickerType: "regular", stickers: stickers, fetchedAt: Date().timeIntervalSince1970,
                    refreshed: request.url?.query?.contains("refresh=1") == true))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
