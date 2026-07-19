import SwiftUI

/// Ponte entre `EnvironmentValues.openSettings`, disponível em uma `View`,
/// e as ações AppKit do item da barra de menus.
@MainActor
enum SettingsOpener {
  static var action: OpenSettingsAction?

  @discardableResult
  static func open() -> Bool {
    guard let action else { return false }
    action()
    return true
  }
}
