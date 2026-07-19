import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

/// Writes the item's native representation and then asks the current
/// application to paste it. The caller is expected to live in a
/// non-activating panel so the destination application remains frontmost.
@MainActor
enum PasteInjector {
  enum Result {
    case pasted
    case copiedWithoutAccessibility
    case failed
  }

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Clp",
    category: "PasteInjector"
  )

  @discardableResult
  static func paste(item: ClipItem) -> Result {
    guard copy(item: item) else { return .failed }
    guard AccessibilityPermission.isTrusted else {
      logger.notice(
        "Accessibility permission is missing; item was copied without automatic Cmd+V"
      )
      AccessibilityPermission.promptIfNeeded()
      return .copiedWithoutAccessibility
    }

    return synthesizePasteKeystroke() ? .pasted : .failed
  }

  @discardableResult
  static func copy(item: ClipItem) -> Bool {
    writeToPasteboard(item)
  }

  @discardableResult
  private static func writeToPasteboard(_ item: ClipItem) -> Bool {
    let pasteboard = NSPasteboard.general
    let wroteContent: Bool

    switch item.contentType {
    case .text:
      guard let text = item.textContent else {
        logger.error("Text clip has no text payload")
        return false
      }
      pasteboard.clearContents()
      wroteContent = pasteboard.setString(text, forType: .string)

    case .url:
      guard let text = item.textContent, !text.isEmpty else {
        logger.error("URL clip has no URL payload")
        return false
      }
      pasteboard.clearContents()
      let wroteURL = pasteboard.setString(text, forType: .URL)
      let wroteFallback = pasteboard.setString(text, forType: .string)
      wroteContent = wroteURL || wroteFallback

    case .rtf:
      guard let text = item.textContent else {
        logger.error("RTF clip has no text payload")
        return false
      }
      pasteboard.clearContents()
      let wroteFallback = pasteboard.setString(text, forType: .string)
      if let rtfData = makeRTFData(from: text) {
        wroteContent = pasteboard.setData(rtfData, forType: .rtf) || wroteFallback
      } else {
        wroteContent = wroteFallback
      }

    case .image:
      guard let data = item.imageData, !data.isEmpty else {
        logger.error("Image clip has no image payload")
        return false
      }
      guard let typeIdentifier = ImagePayloadSupport.typeIdentifier(for: data) else {
        logger.error("Image clip uses an unrecognized image container")
        return false
      }
      pasteboard.clearContents()
      wroteContent = pasteboard.setData(
        data,
        forType: NSPasteboard.PasteboardType(typeIdentifier)
      )

    case .file:
      guard let bookmarkData = item.fileBookmarkData else {
        logger.error("File clip has no bookmark payload")
        return false
      }

      let resolved: ResolvedSecurityScopedBookmark
      do {
        resolved = try SecurityScopedBookmark.resolve(bookmarkData)
      } catch {
        logger.error(
          "Could not resolve file bookmark: \(String(describing: error), privacy: .public)"
        )
        return false
      }

      if resolved.isStale {
        logger.notice("Pasting a file from a stale security-scoped bookmark")
      }

      let accessed = resolved.url.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          resolved.url.stopAccessingSecurityScopedResource()
        }
      }

      pasteboard.clearContents()
      wroteContent = pasteboard.writeObjects([resolved.url as NSURL])
    }

    guard wroteContent else {
      logger.error("NSPasteboard rejected the clip payload")
      return false
    }

    if !pasteboard.setString(UUID().uuidString, forType: ClpPasteboardTypes.selfWrite) {
      // Pasting should still work. The engine may capture this one write,
      // but a marker failure must not destroy an otherwise valid payload.
      logger.error("Could not add the self-write pasteboard marker")
    }
    return true
  }

  private static func makeRTFData(from text: String) -> Data? {
    let attributedString = NSAttributedString(string: text)
    let range = NSRange(location: 0, length: (text as NSString).length)
    do {
      return try attributedString.data(
        from: range,
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
      )
    } catch {
      logger.error(
        "Could not encode RTF payload: \(String(describing: error), privacy: .public)"
      )
      return nil
    }
  }

  private static func synthesizePasteKeystroke() -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
      logger.error("Could not create a CGEventSource for Cmd+V")
      return false
    }

    let keyCode = CGKeyCode(kVK_ANSI_V)
    guard
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: keyCode,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: keyCode,
        keyDown: false
      )
    else {
      logger.error("Could not create Cmd+V keyboard events")
      return false
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }
}
