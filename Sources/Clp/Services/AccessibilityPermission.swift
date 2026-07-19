import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermission {
  private static var didPromptThisRun = false

  static var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  static func promptIfNeeded() -> Bool {
    guard !isTrusted else { return true }
    guard !didPromptThisRun else { return false }

    didPromptThisRun = true
    return requestAccess()
  }

  @discardableResult
  static func requestAccess() -> Bool {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
