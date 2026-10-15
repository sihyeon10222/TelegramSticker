import Foundation

nonisolated extension Sticker {
    static let all: [Sticker] = [
        .init(id: "sample-smile", name: "웃는 얼굴", detail: "투명한 바깥 배경"),
        .init(id: "sample-hearts", name: "겹친 하트", detail: "반투명한 작은 하트"),
        .init(id: "sample-sparkle", name: "반짝 별", detail: "반투명한 빛 테두리")
    ]
}
