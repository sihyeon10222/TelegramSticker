import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PackImportRequest: Identifiable { let id = UUID(); let name: String?; let updating: Bool; var links: [String] = []; var title: String? = nil }
