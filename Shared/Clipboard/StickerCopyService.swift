import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum StickerCopyResult: Equatable {
    case copied
    case fullAccessRequired
    case fileUnavailable
    case invalidPNG

    var message: String {
        switch self {
        case .copied:
            "복사됨 · 채팅창에서 붙여넣기"
        case .fullAccessRequired:
            "복사하려면 설정 → 일반 → 키보드 → 키보드 → StickerBridge에서 전체 접근을 허용해 주세요."
        case .fileUnavailable:
            "이미지 파일을 열 수 없어요. 다른 스티커를 선택해 주세요."
        case .invalidPNG:
            "이미지 파일이 손상되었거나 지원하지 않는 PNG·GIF예요."
        }
    }
}

/// A write-only boundary: never reads the pasteboard's existing contents or document context.
@MainActor
struct StickerCopyService {
    private let loadData: (URL) throws -> Data
    private let writePNG: (Data) -> Void
    private let writeGIF: @MainActor (Data) throws -> Void

    #if targetEnvironment(macCatalyst)
    static var macGIFWriter: ((Data) throws -> Void)?
    #endif

    init(
        loadData: @escaping (URL) throws -> Data = {
            try Data(contentsOf: $0, options: .mappedIfSafe)
        },
        writePNG: @escaping (Data) -> Void = { data in
            UIPasteboard.general.setItems(
                [[UTType.png.identifier: data]],
                options: [.localOnly: true]
            )
        },
        writeGIF: @escaping @MainActor (Data) throws -> Void = { data in
            #if targetEnvironment(macCatalyst)
            guard let writer = StickerCopyService.macGIFWriter else {
                throw CocoaError(.featureUnsupported)
            }
            try writer(data)
            #else
            UIPasteboard.general.setItems([[UTType.gif.identifier: data]], options: [.localOnly: true])
            #endif
        }
    ) {
        self.loadData = loadData
        self.writePNG = writePNG
        self.writeGIF = writeGIF
    }

    func copy(_ sticker: Sticker, isAllowed: Bool, asPNG: Bool = false) -> StickerCopyResult {
        guard !asPNG, let url = sticker.animationURL else {
            return copyPNG(at: sticker.fileURL(), isAllowed: isAllowed)
        }
        guard isAllowed else { return .fullAccessRequired }
        guard url.isFileURL else { return .fileUnavailable }
        guard let data = try? loadData(url) else { return .fileUnavailable }
        guard GIFValidation.isValid(data) else { return .invalidPNG }
        do { try writeGIF(data) } catch { return .fileUnavailable }
        return .copied
    }

    func copyPNG(at url: URL?, isAllowed: Bool) -> StickerCopyResult {
        // Check before file I/O or any access to UIPasteboard, including obtaining .general.
        guard isAllowed else { return .fullAccessRequired }
        guard let url, url.isFileURL else { return .fileUnavailable }
        let data: Data
        do { data = try loadData(url) } catch { return .fileUnavailable }
        guard PNGValidation.isValid(data) else { return .invalidPNG }
        writePNG(data)
        // setItems has no completion result. This acknowledges the write, not a host app's paste/send.
        return .copied
    }

}
