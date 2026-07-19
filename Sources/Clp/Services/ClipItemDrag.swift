import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Builds providers that work both outside Clp and for the app's internal
/// board drop. Every provider carries the real payload plus the ClipItem UUID.
@MainActor
enum ClipItemDrag {
  static let idTypeIdentifier = "\(AppMetadata.bundleID).clip-item-id"
  static let idType = UTType(exportedAs: idTypeIdentifier, conformingTo: .data)

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Clp",
    category: "ClipItemDrag"
  )

  /// Compatibility bridge for the synchronous SwiftUI DropDelegate used by
  /// the board bar. The provider also carries the serialized UUID, so the
  /// drag remains self-describing.
  static var currentDraggedItemID: UUID?

  static func itemProvider(for item: ClipItem) -> NSItemProvider {
    currentDraggedItemID = item.id

    let provider = NSItemProvider()
    let lifetime = DragLifetime(itemID: item.id)
    registerInternalID(item.id, lifetime: lifetime, on: provider)

    switch item.contentType {
    case .text:
      registerText(item.textContent, on: provider)

    case .url:
      registerURL(item.textContent, on: provider)

    case .rtf:
      registerRTF(item.textContent, on: provider)

    case .image:
      registerImage(item.imageData, on: provider)

    case .file:
      registerFile(item.fileBookmarkData, on: provider)
    }

    return provider
  }

  fileprivate static func clearCurrentItemID(ifMatching itemID: UUID) {
    guard currentDraggedItemID == itemID else { return }
    currentDraggedItemID = nil
  }

  private static func registerInternalID(
    _ itemID: UUID,
    lifetime: DragLifetime,
    on provider: NSItemProvider
  ) {
    let data = Data(itemID.uuidString.utf8)
    provider.registerDataRepresentation(
      forTypeIdentifier: idTypeIdentifier,
      visibility: .all
    ) { completion in
      _ = lifetime
      completion(data, nil)
      return nil
    }
  }

  private static func registerText(_ text: String?, on provider: NSItemProvider) {
    guard let text else {
      logger.error("Text drag has no text payload")
      return
    }
    provider.registerObject(text as NSString, visibility: .all)
  }

  private static func registerURL(_ text: String?, on provider: NSItemProvider) {
    guard let text, let url = URL(string: text) else {
      logger.error("URL drag has an invalid URL payload")
      return
    }
    provider.registerObject(url as NSURL, visibility: .all)
    provider.registerObject(text as NSString, visibility: .all)
  }

  private static func registerRTF(_ text: String?, on provider: NSItemProvider) {
    guard let text else {
      logger.error("RTF drag has no text payload")
      return
    }

    provider.registerObject(text as NSString, visibility: .all)
    let attributedString = NSAttributedString(string: text)
    let range = NSRange(location: 0, length: (text as NSString).length)
    do {
      let data = try attributedString.data(
        from: range,
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
      )
      provider.registerDataRepresentation(
        forTypeIdentifier: UTType.rtf.identifier,
        visibility: .all
      ) { completion in
        completion(data, nil)
        return nil
      }
    } catch {
      logger.error(
        "Could not encode dragged RTF: \(String(describing: error), privacy: .public)"
      )
    }
  }

  private static func registerImage(_ data: Data?, on provider: NSItemProvider) {
    guard let data, !data.isEmpty else {
      logger.error("Image drag has no image payload")
      return
    }
    guard let typeIdentifier = ImagePayloadSupport.typeIdentifier(for: data) else {
      logger.error("Image drag uses an unrecognized image container")
      return
    }

    // Supplying bytes under their native UTI avoids NSImage(data:), which
    // would decode a potentially huge bitmap before the drop requests it.
    provider.registerDataRepresentation(
      forTypeIdentifier: typeIdentifier,
      visibility: .all
    ) { completion in
      completion(data, nil)
      return nil
    }
  }

  private static func registerFile(_ bookmarkData: Data?, on provider: NSItemProvider) {
    guard let bookmarkData else {
      logger.error("File drag has no bookmark payload")
      return
    }

    let resolved: ResolvedSecurityScopedBookmark
    do {
      resolved = try SecurityScopedBookmark.resolve(bookmarkData)
    } catch {
      logger.error(
        "Could not resolve dragged file bookmark: \(String(describing: error), privacy: .public)"
      )
      return
    }

    if resolved.isStale {
      logger.notice("Dragging a file from a stale security-scoped bookmark")
    }

    let lease = SecurityScopedURLLease(url: resolved.url)
    let typeIdentifier =
      UTType(filenameExtension: resolved.url.pathExtension)?.identifier
      ?? UTType.data.identifier

    provider.suggestedName = resolved.url.lastPathComponent
    provider.registerObject(resolved.url as NSURL, visibility: .all)
    provider.registerFileRepresentation(
      forTypeIdentifier: typeIdentifier,
      fileOptions: [.openInPlace],
      visibility: .all
    ) { completion in
      completion(lease.url, true, nil)
      return nil
    }
  }
}

private final class DragLifetime: @unchecked Sendable {
  private let itemID: UUID

  init(itemID: UUID) {
    self.itemID = itemID
  }

  deinit {
    let itemID = itemID
    Task { @MainActor in
      ClipItemDrag.clearCurrentItemID(ifMatching: itemID)
    }
  }
}

/// Keeps the security-scope lease alive for as long as NSItemProvider retains
/// its file representation loader (normally the duration of the drag).
private final class SecurityScopedURLLease: @unchecked Sendable {
  let url: URL
  private let didStartAccessing: Bool

  init(url: URL) {
    self.url = url
    didStartAccessing = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if didStartAccessing {
      url.stopAccessingSecurityScopedResource()
    }
  }
}
