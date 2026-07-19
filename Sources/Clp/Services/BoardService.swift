import Foundation
import OSLog
import SwiftData

@MainActor
enum BoardService {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Clp",
    category: "BoardService"
  )

  static func pin(
    _ item: ClipItem,
    to board: Board,
    in context: ModelContext
  ) {
    item.isPinned = true
    item.pinnedAt = .now
    item.board = board
    save(context)
  }

  static func unpin(_ item: ClipItem, in context: ModelContext) {
    item.isPinned = false
    item.pinnedAt = nil
    item.board = nil
    save(context)
  }

  static func delete(_ board: Board, in context: ModelContext) {
    for item in Array(board.items) {
      item.isPinned = false
      item.pinnedAt = nil
      item.board = nil
    }

    context.delete(board)
    save(context)
  }

  private static func save(_ context: ModelContext) {
    do {
      try context.save()
    } catch {
      context.rollback()
      logger.error(
        "Could not persist board change: \(String(describing: error), privacy: .public)"
      )
    }
  }
}
