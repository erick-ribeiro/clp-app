import AppKit
import SwiftUI

/// Janela ativante separada do shelf para edição de texto livre.
@MainActor
final class TextEditWindowController {
  static let shared = TextEditWindowController()

  private var window: NSWindow?

  private init() {}

  func edit(_ item: ClipItem, onSave: @escaping (String) -> Void) {
    let editorWindow = window ?? makeWindow()
    window = editorWindow

    editorWindow.contentView = NSHostingView(
      rootView: EditTextView(
        initialText: item.textContent ?? "",
        onSave: { [weak self] text in
          onSave(text)
          self?.window?.orderOut(nil)
        },
        onCancel: { [weak self] in
          self?.window?.orderOut(nil)
        }
      )
    )

    NSApp.activate(ignoringOtherApps: true)
    editorWindow.center()
    editorWindow.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Editar texto"
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 420, height: 280)
    window.setFrameAutosaveName("ClpTextEditor")
    return window
  }
}
