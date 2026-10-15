import SwiftUI

/// Transitional app entry point. Unlike the original compilation-only smoke
/// screen, this now uses the RC3 four-tab navigation for live, PUBLIC read-only
/// GitHub browsing. Production OAuth/private workflows are intentionally absent.
struct GitPilotCoreSmokeView: View {
    var body: some View {
        PublicWorkspaceRoot()
    }
}
