import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var statusMenu: NSMenu?
  private let cleanupService = CleanupService()
  private var hourlyCleanupTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    setupStatusItem()
    setupHotkey()

    // Monta o painel sem exibi-lo para reduzir a latência do primeiro uso.
    PanelController.shared.preload()

    Task {
      await ClipboardEngine.shared.start()
    }

    runCleanup()
    scheduleHourlyCleanup()

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(handleWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    runCleanup()
  }

  func applicationWillTerminate(_ notification: Notification) {
    hourlyCleanupTask?.cancel()
    hourlyCleanupTask = nil
    HotkeyManager.shared.unregister()
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    PanelController.shared.show()
    return true
  }

  @objc private func handleWake() {
    runCleanup()
  }

  // MARK: - Limpeza

  private func runCleanup() {
    cleanupService.run(
      context: PersistenceStore.shared.mainContext,
      policy: AppSettings.shared.retentionPolicy
    )
  }

  private func scheduleHourlyCleanup() {
    hourlyCleanupTask?.cancel()
    hourlyCleanupTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(3_600))
        } catch {
          return
        }

        self?.runCleanup()
      }
    }
  }

  // MARK: - Barra de menus

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = item.button else { return }

    let image = NSImage(
      systemSymbolName: "clipboard",
      accessibilityDescription: AppMetadata.displayName
    )
    image?.isTemplate = true
    button.image = image
    button.imagePosition = .imageOnly
    button.toolTip = AppMetadata.displayName
    button.target = self
    button.action = #selector(handleStatusItemClick(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])

    let menu = NSMenu()

    let openItem = NSMenuItem(
      title: "Abrir painel",
      action: #selector(openPanel),
      keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)

    let settingsItem = NSMenuItem(
      title: "Configurações…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Sair",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    menu.addItem(quitItem)

    statusMenu = menu
    statusItem = item
  }

  @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      statusMenu?.popUp(
        positioning: nil,
        at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY),
        in: sender
      )
    } else {
      openPanel()
    }
  }

  private func setupHotkey() {
    HotkeyManager.shared.onTrigger = {
      PanelController.shared.toggle()
    }
    HotkeyManager.shared.register()
  }

  @objc private func openPanel() {
    PanelController.shared.toggle()
  }

  @objc private func openSettings() {
    NSApp.activate(ignoringOtherApps: true)

    guard !SettingsOpener.open() else { return }

    // O NSHostingView da ponte pode ainda não ter concluído o `onAppear`.
    Task { @MainActor in
      await Task.yield()
      _ = SettingsOpener.open()
    }
  }
}
