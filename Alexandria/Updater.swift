import SwiftUI
import Sparkle

/// Sparkle auto-update wiring. The controller owns the update lifecycle
/// (scheduled checks, download, install, relaunch); the feed URL and EdDSA
/// public key live in Info.plist (SUFeedURL / SUPublicEDKey). Updates are
/// EdDSA-signed by Scripts/package.sh, so they verify even though the app
/// itself is only ad-hoc signed.
@MainActor
final class UpdaterModel: ObservableObject {
    let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// "Check for Updates…" menu item, enabled whenever Sparkle can check.
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Button("Check for Updates…") {
            updater.controller.updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
