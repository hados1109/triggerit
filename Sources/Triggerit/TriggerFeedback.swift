import AudioToolbox
import AppKit
import SwiftUI

/// Central “trigger fired” presentation: flash + short system sound.
final class TriggerFeedback: ObservableObject {
    @Published var flashVisible = false
    @Published var flashLabel = ""
    @Published var flashTint: Color = .green
    @Published var lastMessage = "Idle"

    private var hideFlashWorkItem: DispatchWorkItem?

    func fire(source: String, tint: Color = .green) {
        let schedule = { [weak self] in
            guard let self else { return }
            self.hideFlashWorkItem?.cancel()

            self.flashLabel = source
            self.flashTint = tint
            self.flashVisible = true
            self.lastMessage = "\(source) — \(Self.formattedNow())"
            AudioServicesPlaySystemSound(1104)

            let work = DispatchWorkItem { [weak self] in
                self?.flashVisible = false
            }
            self.hideFlashWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
        if Thread.isMainThread {
            schedule()
        } else {
            DispatchQueue.main.async(execute: schedule)
        }
    }

    private static func formattedNow() -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f.string(from: Date())
    }
}
