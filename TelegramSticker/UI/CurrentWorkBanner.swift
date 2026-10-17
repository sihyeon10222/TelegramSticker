import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Lives above the tab bar, alongside the library's selection actions.
struct CurrentWorkBanner: View {
    var body: some View {
        if let title = BackgroundWork.shared.title {
            HStack(spacing: 12) {
                Button {
                    if ImportActivity.shared.current?.busy == true { ImportActivity.shared.presentCurrent() }
                    else { OptimizationCenter.shared.presentCurrent() }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(title).font(.caption.bold())
                            Spacer()
                        }
                        ProgressView(value: BackgroundWork.shared.fraction)
                            .tint(ImportActivity.shared.current?.busy == true ? ImportActivity.shared.current?.progressColor ?? .blue : .blue)
                        Text(BackgroundWork.shared.subtitle)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(ImportActivity.shared.current?.busy == true && (ImportActivity.shared.current?.failedCount ?? 0) > 0 ? Color.red : Color.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(ImportActivity.shared.current?.busy != true && OptimizationCenter.shared.current?.running != true)
                .accessibilityLabel("진행 중인 작업 열기")
                .accessibilityIdentifier("backgroundWorkDetails")
                Button("중단") { BackgroundWork.shared.cancelCurrent() }
                    .appGlassButton().font(.caption)
            }
            .padding(12)
            .appGlassPanel(cornerRadius: 20)
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }
}
