import Foundation
import SwiftData

@Model
final class ClipItem {
  @Attribute(.unique) var id: UUID
  var createdAt: Date
  var contentType: ClipContentType
  var textContent: String?
  var title: String?

  @Attribute(.externalStorage) var imageData: Data?

  /// Bookmark com escopo de segurança do arquivo original; caminhos simples
  /// não sobrevivem com segurança a mudanças e novos ciclos do processo.
  var fileBookmarkData: Data?

  var sourceAppBundleID: String?
  var sourceAppName: String?
  var isPinned: Bool
  var pinnedAt: Date?

  /// SHA-256 (em hexadecimal) calculado pela camada de captura.
  var contentHash: String

  var board: Board?

  init(
    id: UUID = UUID(),
    createdAt: Date = .now,
    contentType: ClipContentType,
    textContent: String? = nil,
    title: String? = nil,
    imageData: Data? = nil,
    fileBookmarkData: Data? = nil,
    sourceAppBundleID: String? = nil,
    sourceAppName: String? = nil,
    isPinned: Bool = false,
    pinnedAt: Date? = nil,
    contentHash: String,
    board: Board? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.contentType = contentType
    self.textContent = textContent
    self.title = title
    self.imageData = imageData
    self.fileBookmarkData = fileBookmarkData
    self.sourceAppBundleID = sourceAppBundleID
    self.sourceAppName = sourceAppName
    self.isPinned = isPinned
    self.pinnedAt = pinnedAt
    self.contentHash = contentHash
    self.board = board
  }

  /// Resolve o bookmark no momento do uso. `nil` indica bookmark inválido
  /// ou arquivo que já não pode ser localizado.
  var resolvedFileURL: URL? {
    guard let fileBookmarkData else { return nil }

    var isStale = false
    return try? URL(
      resolvingBookmarkData: fileBookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
  }
}
