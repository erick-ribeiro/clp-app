import Foundation
import OSLog
import SwiftData

/// Deletes only unpinned, unboarded clips that are older than the active
/// retention window. Board membership is intentionally checked separately
/// from `isPinned` to protect data if those fields are temporarily inconsistent.
@MainActor
struct CleanupService {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Clp",
    category: "CleanupService"
  )

  func run(context: ModelContext, policy: RetentionPolicy) {
    guard let cutoff = policy.cutoffDate else { return }

    let predicate = #Predicate<ClipItem> { item in
      item.isPinned == false
        && item.board == nil
        && item.createdAt < cutoff
    }
    let descriptor = FetchDescriptor<ClipItem>(predicate: predicate)

    do {
      let expiredItems = try context.fetch(descriptor)
      guard !expiredItems.isEmpty else { return }

      for item in expiredItems {
        context.delete(item)
      }
      try context.save()
      Self.logger.info(
        "Deleted \(expiredItems.count, privacy: .public) expired clipboard items"
      )
    } catch {
      Self.logger.error(
        "Clipboard cleanup failed: \(String(describing: error), privacy: .public)"
      )
    }
  }
}
