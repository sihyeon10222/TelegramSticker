import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

struct AdditionalPackLink: Identifiable {
    let id: UUID
    var value: String
    init(id: UUID = UUID(), value: String = "") { self.id = id; self.value = value }
}
struct BatchPackStatus: Identifiable {
    let id: UUID
    let link: String
    var title: String
    var status = "대기 중"
}
