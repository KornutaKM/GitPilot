import SwiftUI

/// Temporary native build harness for the existing RC3 migration.
/// The full GitPilot SwiftUI application is not yet present in this repository.
@main
struct GitPilotCoreSmokeApp: App {
    var body: some Scene {
        WindowGroup {
            GitPilotCoreSmokeView()
                .preferredColorScheme(.dark)
        }
    }
}
