import AppKit
import OSLog
import SwiftUI

/// Shelf não ativante: pode receber teclado sem transformar o Clp no
/// aplicativo frontmost. Isso preserva o destino do paste-back.
@MainActor
final class FloatingPanel: NSPanel {
  init(contentRect: NSRect, contentView: some View) {
    super.init(
      contentRect: contentRect,
      styleMask: [.nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    level = .statusBar
    collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .ignoresCycle,
      .stationary,
    ]

    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = false
    hidesOnDeactivate = false
    isMovableByWindowBackground = false
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    animationBehavior = .utilityWindow
    acceptsMouseMovedEvents = true

    let hostingView = ClpHostingView(rootView: contentView)
    hostingView.frame = NSRect(origin: .zero, size: contentRect.size)
    self.contentView = hostingView
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override var acceptsFirstResponder: Bool { true }
}

/// `NSHostingView` precisa aceitar first responder para o field editor do
/// `NSTextField` funcionar dentro do painel não-ativante.
private final class ClpHostingView<Content: View>: NSHostingView<Content> {
  override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class PanelController {
  static let shared = PanelController()

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Clp",
    category: "PanelController"
  )
  private static let regularHeight: CGFloat = 276
  private static let compactHeight: CGFloat = 206

  private let uiState = PanelUIState()
  private var panel: FloatingPanel?
  private var resignKeyObserver: NSObjectProtocol?
  private var pasteTargetApplication: NSRunningApplication?

  private init() {}

  func preload() {
    guard panel == nil else { return }
    panel = makePanel()
  }

  func toggle() {
    if panel?.isVisible == true {
      close()
    } else {
      show()
    }
  }

  func show() {
    let panel = panel ?? makePanel()
    self.panel = panel

    rememberPasteTarget()
    uiState.prepareForPresentation()
    position(panel)
    panel.makeKeyAndOrderFront(nil)
  }

  func close() {
    uiState.didDismiss()
    panel?.orderOut(nil)
  }

  private func makePanel() -> FloatingPanel {
    let panel = FloatingPanel(
      contentRect: initialFrame,
      contentView: ClipboardPanelView(
        onSelect: { [weak self] item in
          self?.select(item)
        },
        onClose: { [weak self] in
          self?.close()
        }
      )
      .modelContainer(PersistenceStore.shared.container)
      .environmentObject(uiState)
    )

    resignKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: panel,
      queue: .main
    ) { [weak self, weak panel] _ in
      Task { @MainActor [weak self, weak panel] in
        guard panel?.isVisible == true else { return }
        self?.close()
      }
    }

    return panel
  }

  private func select(_ item: ClipItem) {
    let destination = pasteTargetApplication
    pasteTargetApplication = nil
    close()

    guard let destination, !destination.isTerminated else {
      Self.logger.notice(
        "No valid paste target; selected item was copied without Cmd+V"
      )
      PasteInjector.copy(item: item)
      return
    }

    Task { @MainActor in
      await paste(item, into: destination)
    }
  }

  private func rememberPasteTarget() {
    pasteTargetApplication = nil
    guard let application = NSWorkspace.shared.frontmostApplication,
      application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return }

    pasteTargetApplication = application
  }

  private func paste(
    _ item: ClipItem,
    into destination: NSRunningApplication
  ) async {
    guard !destination.isTerminated else {
      PasteInjector.copy(item: item)
      return
    }

    if NSWorkspace.shared.frontmostApplication?.processIdentifier
      != destination.processIdentifier
    {
      guard destination.activate(options: []) else {
        Self.logger.error(
          "Could not reactivate paste target; skipped automatic Cmd+V"
        )
        PasteInjector.copy(item: item)
        return
      }
    }

    for _ in 0..<20 {
      if NSWorkspace.shared.frontmostApplication?.processIdentifier
        == destination.processIdentifier
      {
        PasteInjector.paste(item: item)
        return
      }

      do {
        try await Task.sleep(for: .milliseconds(25))
      } catch {
        PasteInjector.copy(item: item)
        return
      }
    }

    Self.logger.error(
      "Paste target did not become frontmost; skipped automatic Cmd+V"
    )
    PasteInjector.copy(item: item)
  }

  private var shelfHeight: CGFloat {
    AppSettings.shared.isCompactPanelEnabled
      ? Self.compactHeight
      : Self.regularHeight
  }

  private var targetScreen: NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { screen in
      NSMouseInRect(mouseLocation, screen.frame, false)
    }) ?? NSScreen.main
  }

  private var initialFrame: NSRect {
    guard let screen = targetScreen else {
      return NSRect(x: 0, y: 0, width: 900, height: shelfHeight)
    }
    return NSRect(
      x: screen.frame.minX,
      y: screen.frame.minY,
      width: screen.frame.width,
      height: shelfHeight
    )
  }

  private func position(_ panel: NSPanel) {
    guard let screen = targetScreen else { return }

    panel.setFrame(
      NSRect(
        x: screen.frame.minX,
        y: screen.frame.minY,
        width: screen.frame.width,
        height: shelfHeight
      ),
      display: false
    )
  }
}
