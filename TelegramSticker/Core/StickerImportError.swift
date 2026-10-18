import Foundation

nonisolated enum StickerImportError: Error, LocalizedError {
    case invalidLink, invalidConfiguration, invalidResponse, unsupportedFormat, tooLarge, noStaticStickers
    case server(code: String, retryable: Bool, retryAfter: Int)
    case partial(completed: Int, total: Int)
    case network
    case conversionTimeout, updateFailed, refreshUnsupported
    case importInProgress
    var errorDescription: String? {
        switch self {
        case .invalidLink: "https://t.me/addstickers/팩이름 형식의 공개 링크를 입력해 주세요."
        case .invalidConfiguration: "가져오기 서비스에 연결할 수 없어요. 잠시 후 다시 시도해 주세요."
        case .invalidResponse: "서버 응답을 읽을 수 없어요. 서버 버전과 팩 상태를 확인해 주세요."
        case .unsupportedFormat: "지원 범위 밖이거나 손상된 스티커예요. PNG·WebP, 벡터 TGS, 10초 이하 VP9 WebM을 지원해요."
        case .tooLarge: "외부 서비스의 파일 한도 또는 안전한 디코딩 범위를 초과했어요."
        case .conversionTimeout: "애니메이션 처리 시간이 초과됐어요. 낮은 해상도로 다시 시도할 수 있어요."
        case .updateFailed: "업데이트 중 일부 항목을 준비하지 못했어요. 기존 팩을 유지했어요. 실패 항목을 확인해 주세요."
        case .refreshUnsupported: "서버가 새로 조회를 지원하지 않아요. 최신 버전의 서버가 필요해요."
        case .noStaticStickers: "설치 가능한 일반 스티커가 없는 팩이에요."
        case .partial(let completed, let total): "\(total)개 중 \(completed)개를 준비했어요. 설치 가능한 항목이 없어 팩을 추가하지 못했어요. 다시 시도해 주세요."
        case .network: "네트워크에 연결할 수 없어요. 연결 상태를 확인한 뒤 다시 시도해 주세요."
        case .importInProgress: "이전 가져오기를 정리하고 있어요. 잠시 후 다시 시도해 주세요."
        case .server(let code, _, _):
            switch code {
            case "unauthorized": "가져오기 서비스 인증이 만료됐어요. 다시 시도해 주세요."
            case "pack_unavailable", "asset_unavailable": "공개 팩이나 파일에 접근할 수 없어요. 링크를 확인해 주세요."
            case "server_not_configured": "가져오기 서버 설정이 아직 준비되지 않았어요."
            case "rate_limited", "upstream_rate_limited": "요청이 많아 잠시 기다려야 해요. 잠시 후 다시 시도해 주세요."
            case "file_too_large": "파일이 다운로드 한도를 초과했어요."
            case "unsupported_format": "지원하지 않는 스티커 형식이에요."
            default: "가져오기 서버에서 응답하지 않아요. 잠시 후 다시 시도해 주세요."
            }
        }
    }
}
