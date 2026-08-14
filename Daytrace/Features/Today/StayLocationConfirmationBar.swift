import SwiftUI

struct StayLocationConfirmationBar: View {
    let selectedPlaceName: String?
    let isAtOriginalLocation: Bool
    let restoreOriginal: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                selectedPlaceName ?? "地図の中央を選択中",
                systemImage: selectedPlaceName == nil ? "scope" : "mappin.circle.fill"
            )
            .font(.subheadline.bold())
            .lineLimit(2)

            Button(action: confirm) {
                Label("この位置を反映", systemImage: "checkmark")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.daytraceGlassProminent)

            Button("記録された元の位置に戻す", systemImage: "arrow.uturn.backward", action: restoreOriginal)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isAtOriginalLocation)
        }
        .padding(DS.cardPadding)
        .daytraceGlassSurface()
    }
}
