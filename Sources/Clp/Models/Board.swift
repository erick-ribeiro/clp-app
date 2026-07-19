import Foundation
import SwiftData

@Model
final class Board {
  @Attribute(.unique) var id: UUID
  var name: String
  var colorHex: String
  var createdAt: Date

  /// Excluir um board apenas solta seus clips de volta no histórico.
  @Relationship(deleteRule: .nullify, inverse: \ClipItem.board)
  var items: [ClipItem] = []

  init(
    id: UUID = UUID(),
    name: String,
    colorHex: String = "#8E8E93",
    createdAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.colorHex = colorHex
    self.createdAt = createdAt
  }
}
