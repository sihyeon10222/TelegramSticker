import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

@MainActor @Observable
final class ImportActivity {
    static let shared = ImportActivity()
    var count = 0
    var libraryChangeID = 0
    var current: ImportModel?
    var presentedImport: ImportModel?
    var optimizationSuggestion: OptimizationRequest?
    var visibleImportIDs = Set<UUID>()
    func suggestOptimization(packIDs: Set<String>, stickerIDs: Set<String>? = nil) {
        guard !packIDs.isEmpty else { return }
        if let stickerIDs, stickerIDs.isEmpty { return }
        optimizationSuggestion = OptimizationRequest(packIDs: packIDs, stickerIDs: stickerIDs)
    }
    func presentCurrent() { presentedImport = current }
}
