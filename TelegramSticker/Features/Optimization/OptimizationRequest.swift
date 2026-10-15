import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OptimizationRequest: Identifiable {
    let id = UUID()
    var packIDs: Set<String>? = nil
    var stickerIDs: Set<String>? = nil
}
