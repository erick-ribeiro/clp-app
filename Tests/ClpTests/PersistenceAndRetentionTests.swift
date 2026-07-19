import Foundation
import SwiftData
import Testing

@testable import Clp

@MainActor
@Suite("Persistência e retenção")
struct PersistenceAndRetentionTests {
  @Test("Nunca não produz data de corte")
  func neverHasNoCutoff() {
    #expect(RetentionPolicy.never.cutoffDate == nil)
  }

  @Test("Políticas produzem cortes no passado")
  func policiesProducePastCutoffs() {
    let now = Date.now
    #expect(RetentionPolicy.hours24.cutoffDate.map { $0 < now } == true)
    #expect(RetentionPolicy.days7.cutoffDate.map { $0 < now } == true)
    #expect(RetentionPolicy.days30.cutoffDate.map { $0 < now } == true)
  }

  @Test("Paleta escolhe uma cor ainda não usada")
  func boardPaletteAvoidsUsedColors() {
    let boards = BoardColorPalette.hexValues.prefix(3).enumerated().map {
      index,
      color in
      Board(
        name: "Board \(index)",
        colorHex: color,
        createdAt: Date(timeIntervalSince1970: TimeInterval(index))
      )
    }

    let next = BoardColorPalette.nextColor(existingBoards: boards)
    #expect(!Set(boards.map(\.colorHex)).contains(next))
    #expect(next.hasPrefix("#"))
    #expect(next.count == 7)
  }

  @Test("Cleanup remove somente item expirado e desprotegido")
  func cleanupEligibility() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let board = Board(name: "Importantes")
    let oldDate = Calendar.current.date(
      byAdding: .day,
      value: -2,
      to: .now
    )!

    let expired = makeItem(createdAt: oldDate, suffix: "expired")
    let pinned = makeItem(createdAt: oldDate, suffix: "pinned")
    pinned.isPinned = true
    pinned.pinnedAt = oldDate

    let boarded = makeItem(createdAt: oldDate, suffix: "boarded")
    boarded.isPinned = true
    boarded.pinnedAt = oldDate
    boarded.board = board

    let recent = makeItem(createdAt: .now, suffix: "recent")

    context.insert(board)
    [expired, pinned, boarded, recent].forEach(context.insert)
    try context.save()

    CleanupService().run(context: context, policy: .hours24)

    let remaining = try context.fetch(FetchDescriptor<ClipItem>())
    let remainingIDs = Set(remaining.map(\.id))

    #expect(!remainingIDs.contains(expired.id))
    #expect(remainingIDs.contains(pinned.id))
    #expect(remainingIDs.contains(boarded.id))
    #expect(remainingIDs.contains(recent.id))
  }

  @Test("Excluir board preserva o clip e anula a relação")
  func deletingBoardNullifiesRelationship() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let board = Board(name: "Temporário")
    let item = makeItem(createdAt: .now, suffix: "kept")

    context.insert(board)
    context.insert(item)
    try context.save()

    BoardService.pin(item, to: board, in: context)
    #expect(item.isPinned)
    #expect(item.board?.id == board.id)

    BoardService.delete(board, in: context)

    let remaining = try context.fetch(FetchDescriptor<ClipItem>())
    #expect(remaining.count == 1)
    #expect(remaining.first?.id == item.id)
    #expect(remaining.first?.board == nil)
    #expect(remaining.first?.isPinned == false)
    #expect(remaining.first?.pinnedAt == nil)
  }

  private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
      ClipItem.self,
      Board.self,
    ])
    let configuration = ModelConfiguration(
      "ClpTests",
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(
      for: schema,
      configurations: [configuration]
    )
  }

  private func makeItem(createdAt: Date, suffix: String) -> ClipItem {
    ClipItem(
      createdAt: createdAt,
      contentType: .text,
      textContent: suffix,
      contentHash: suffix
    )
  }
}
