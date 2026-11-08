import SwiftUI

struct OverlaySettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("Show Quick Access overlay after capture", isOn: $settings.showOverlay)
            // Everything about the overlay is moot while it is off.
            Group {
                Picker("Position", selection: $settings.overlayCorner) {
                    ForEach(OverlayCorner.allCases) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
                Stepper(value: $settings.overlayAutoCloseSeconds, in: 0...60, step: 1) {
                    Text(settings.overlayAutoCloseSeconds == 0
                         ? "Auto-close: never"
                         : "Auto-close after \(Int(settings.overlayAutoCloseSeconds)) s")
                }
                Picker("Show on", selection: $settings.overlayDisplay) {
                    ForEach(OverlayDisplayChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                Stepper(value: $settings.overlayMaxCards, in: AppSettings.overlayMaxCardsRange) {
                    Text(settings.overlayMaxCards == 1 ? "Show up to 1 overlay" : "Show up to \(settings.overlayMaxCards) overlays")
                }
                Toggle("Close after dragging out", isOn: $settings.overlayCloseAfterDrag)
            }
            .disabled(!settings.showOverlay)
            Stepper("Keep history for \(settings.historyRetentionDays) days", value: $settings.historyRetentionDays, in: 1...365)
        }
        .formStyle(.grouped)
    }
}
