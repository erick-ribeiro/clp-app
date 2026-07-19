import Foundation
import OSLog
import SwiftData

extension ModelContext {
  @MainActor
  @discardableResult
  func saveLogged(category: String) -> Bool {
    do {
      try save()
      return true
    } catch {
      rollback()
      Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Clp",
        category: category
      ).error(
        "SwiftData save failed: \(String(describing: error), privacy: .public)"
      )
      return false
    }
  }
}
