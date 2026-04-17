import SwiftUI

/// Observes `TriggerFeedback` directly so SwiftUI invalidates when flash state changes
/// (nested `ObservableObject` on `TriggerHub` alone does not reliably refresh the window).
struct TriggerFlashOverlay: View {
    @ObservedObject var feedback: TriggerFeedback

    var body: some View {
        Group {
            if feedback.flashVisible {
                ZStack {
                    feedback.flashTint.opacity(0.35)
                        .ignoresSafeArea()
                    Text(feedback.flashLabel)
                        .font(.largeTitle.weight(.heavy))
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                // Let clicks reach the ScrollView underneath so the UI doesn’t feel “stuck”.
                .allowsHitTesting(false)
            }
        }
    }
}
