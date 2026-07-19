import SwiftUI

@main
struct ClpApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // O painel principal é um NSPanel gerenciado pelo PanelController.
    // Não há WindowGroup para que o Clp permaneça um app de menu bar.
    Settings {
      SettingsView()
    }
  }
}
