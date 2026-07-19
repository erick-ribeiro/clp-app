import Carbon.HIToolbox
import Foundation
import OSLog

private let clpHotKeySignature: OSType = 0x434C_5048  // "CLPH"
private let clpHotKeyIdentifier: UInt32 = 1
private let hotKeyLogger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "Clp",
  category: "HotkeyManager"
)

private func clpHotKeyEventHandler(
  _ nextHandler: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event, let userData else {
    return OSStatus(eventNotHandledErr)
  }

  var eventHotKeyID = EventHotKeyID()
  let parameterStatus = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &eventHotKeyID
  )
  guard parameterStatus == noErr else {
    hotKeyLogger.error(
      "Could not read Carbon hotkey event: \(parameterStatus, privacy: .public)"
    )
    return parameterStatus
  }

  guard
    eventHotKeyID.signature == clpHotKeySignature,
    eventHotKeyID.id == clpHotKeyIdentifier
  else {
    return OSStatus(eventNotHandledErr)
  }

  let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
  Task { @MainActor in
    manager.handleTrigger()
  }
  return noErr
}

/// Carbon remains the system API that can consume a global keyboard shortcut;
/// NSEvent's global monitor can only observe one.
@MainActor
final class HotkeyManager {
  static let shared = HotkeyManager()

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?

  var onTrigger: (() -> Void)?

  private init() {}

  @discardableResult
  func register(
    keyCode: UInt32 = UInt32(kVK_ANSI_V),
    modifiers: UInt32 = UInt32(cmdKey | shiftKey)
  ) -> Bool {
    unregister()

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: OSType(kEventHotKeyPressed)
    )
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      clpHotKeyEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandlerRef
    )
    guard installStatus == noErr else {
      hotKeyLogger.error(
        "Could not install Carbon event handler: \(installStatus, privacy: .public)"
      )
      eventHandlerRef = nil
      return false
    }

    let identifier = EventHotKeyID(
      signature: clpHotKeySignature,
      id: clpHotKeyIdentifier
    )
    let registerStatus = RegisterEventHotKey(
      keyCode,
      modifiers,
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    guard registerStatus == noErr else {
      hotKeyLogger.error(
        "Could not register Cmd+Shift+V: \(registerStatus, privacy: .public)"
      )
      hotKeyRef = nil
      removeEventHandler()
      return false
    }

    return true
  }

  func unregister() {
    if let hotKeyRef {
      let status = UnregisterEventHotKey(hotKeyRef)
      if status != noErr {
        hotKeyLogger.error(
          "Could not unregister Carbon hotkey: \(status, privacy: .public)"
        )
      }
      self.hotKeyRef = nil
    }

    removeEventHandler()
  }

  fileprivate func handleTrigger() {
    onTrigger?()
  }

  private func removeEventHandler() {
    guard let eventHandlerRef else { return }
    let status = RemoveEventHandler(eventHandlerRef)
    if status != noErr {
      hotKeyLogger.error(
        "Could not remove Carbon event handler: \(status, privacy: .public)"
      )
    }
    self.eventHandlerRef = nil
  }
}
