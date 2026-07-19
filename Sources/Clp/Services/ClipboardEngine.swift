import AppKit
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Polls the system pasteboard because AppKit does not expose a notification
/// for arbitrary clipboard changes. AppKit objects never leave MainActor; the
/// engine receives immutable, Sendable snapshots and owns only polling state.
actor ClipboardEngine {
  static let shared = ClipboardEngine()

  enum SuspensionReason: Hashable, Sendable {
    case systemSleep
    case screenLock
  }

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Clp",
    category: "ClipboardEngine"
  )
  private static let pollingInterval: Duration = .milliseconds(800)

  private var lastChangeCount: Int?
  private var pollTask: Task<Void, Never>?
  private var pollingGeneration: UInt64 = 0
  private var suspensionReasons: Set<SuspensionReason> = []

  private init() {}

  func start() async {
    await ClipboardLifecycleObserver.shared.install(engine: self)

    guard pollTask == nil, suspensionReasons.isEmpty else { return }

    pollingGeneration &+= 1
    let generation = pollingGeneration
    let initialChangeCount = await ClipboardPasteboardSnapshotter.currentChangeCount()

    // `start()` is reentrant while waiting for MainActor. A pause or another
    // start may have superseded this request in the meantime.
    guard
      pollTask == nil,
      pollingGeneration == generation,
      suspensionReasons.isEmpty
    else { return }

    lastChangeCount = initialChangeCount
    let task = Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      await self.runPollingLoop(generation: generation)
      await self.pollingLoopFinished(generation: generation)
    }
    pollTask = task
  }

  func suspend(for reason: SuspensionReason) {
    suspensionReasons.insert(reason)
    pollingGeneration &+= 1
    pollTask?.cancel()
    pollTask = nil
  }

  func resume(from reason: SuspensionReason) async {
    suspensionReasons.remove(reason)
    guard suspensionReasons.isEmpty else { return }
    await start()
  }

  private func runPollingLoop(generation: UInt64) async {
    while !Task.isCancelled,
      generation == pollingGeneration,
      suspensionReasons.isEmpty
    {
      await pollOnce(generation: generation)

      do {
        try await Task.sleep(for: Self.pollingInterval)
      } catch is CancellationError {
        return
      } catch {
        Self.logger.error(
          "Clipboard polling sleep failed: \(String(describing: error), privacy: .public)"
        )
        return
      }
    }
  }

  private func pollingLoopFinished(generation: UInt64) {
    guard generation == pollingGeneration else { return }
    pollTask = nil
  }

  private func pollOnce(generation: UInt64) async {
    guard suspensionReasons.isEmpty, let lastChangeCount else { return }

    guard
      let snapshot = await ClipboardPasteboardSnapshotter.snapshot(
        ifChangedFrom: lastChangeCount
      ),
      generation == pollingGeneration,
      !Task.isCancelled
    else {
      return
    }

    // Advance even for ignored or unsupported payloads, otherwise the same
    // sensitive clipboard would be inspected every 800 ms.
    self.lastChangeCount = snapshot.changeCount

    switch snapshot.disposition {
    case .selfWrite:
      Self.logger.debug("Suppressed a Clp-authored pasteboard change")

    case .sensitive:
      Self.logger.notice("Skipped clipboard content marked as sensitive")

    case .ignored(let bundleID):
      Self.logger.debug(
        "Skipped clipboard content from ignored app \(bundleID, privacy: .public)"
      )

    case .unsupported:
      break

    case .content(let payload):
      let captured = await capture(payload)
      guard
        let captured,
        generation == pollingGeneration,
        suspensionReasons.isEmpty,
        !Task.isCancelled
      else {
        return
      }
      await Self.persist(captured, source: snapshot.source)
    }
  }

  private func capture(_ payload: PasteboardPayload) async -> CapturedContent? {
    switch payload {
    case .file(let bookmarkData, let displayName, let identity):
      let hash = await Task.detached(priority: .utility) {
        ClipboardContentRules.fileContentHash(
          bookmarkData: bookmarkData,
          fallbackIdentity: identity
        )
      }.value

      return CapturedContent(
        kind: .file,
        textContent: displayName,
        imageData: nil,
        fileBookmarkData: bookmarkData,
        hash: hash
      )

    case .image(let data):
      return CapturedContent(
        kind: .image,
        textContent: nil,
        imageData: data,
        fileBookmarkData: nil,
        hash: ClipboardContentRules.contentHash(
          domain: .image,
          data: data
        )
      )

    case .text(let text):
      if let wholeURL = ClipboardContentRules.wholeURL(in: text) {
        return CapturedContent(
          kind: .url,
          textContent: wholeURL,
          imageData: nil,
          fileBookmarkData: nil,
          hash: ClipboardContentRules.contentHash(
            domain: .url,
            data: Data(wholeURL.utf8)
          )
        )
      }

      guard !text.isEmpty else { return nil }
      return CapturedContent(
        kind: .text,
        textContent: text,
        imageData: nil,
        fileBookmarkData: nil,
        hash: ClipboardContentRules.contentHash(
          domain: .text,
          data: Data(text.utf8)
        )
      )
    }
  }

  @MainActor
  private static func persist(_ captured: CapturedContent, source: SourceApplication) {
    let context = PersistenceStore.shared.mainContext
    var descriptor = FetchDescriptor<ClipItem>(
      sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 1

    do {
      let mostRecent = try context.fetch(descriptor).first

      if let mostRecent,
        ClipboardContentRules.isDuplicateOfMostRecent(
          capturedHash: captured.hash,
          mostRecentHash: mostRecent.contentHash
        )
      {
        mostRecent.createdAt = .now
        try context.save()
        return
      }

      let item = ClipItem(
        contentType: modelContentType(for: captured.kind),
        textContent: captured.textContent,
        imageData: captured.imageData,
        fileBookmarkData: captured.fileBookmarkData,
        sourceAppBundleID: source.bundleIdentifier,
        sourceAppName: source.localizedName,
        contentHash: captured.hash
      )
      context.insert(item)
      try context.save()
    } catch {
      logger.error(
        "Could not persist clipboard item: \(String(describing: error), privacy: .public)"
      )
    }
  }

  @MainActor
  private static func modelContentType(for kind: CapturedContent.Kind) -> ClipContentType {
    switch kind {
    case .text: .text
    case .url: .url
    case .image: .image
    case .file: .file
    }
  }
}

private struct CapturedContent: Sendable {
  enum Kind: Sendable {
    case text
    case url
    case image
    case file
  }

  let kind: Kind
  let textContent: String?
  let imageData: Data?
  let fileBookmarkData: Data?
  let hash: String
}

private struct SourceApplication: Sendable {
  let bundleIdentifier: String?
  let localizedName: String?
}

private enum PasteboardPayload: Sendable {
  case file(bookmarkData: Data, displayName: String, identity: String)
  case image(Data)
  case text(String)
}

private struct PasteboardSnapshot: Sendable {
  enum Disposition: Sendable {
    case selfWrite
    case sensitive
    case ignored(bundleID: String)
    case unsupported
    case content(PasteboardPayload)
  }

  let changeCount: Int
  let source: SourceApplication
  let disposition: Disposition
}

@MainActor
private enum ClipboardPasteboardSnapshotter {
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Clp",
    category: "ClipboardSnapshot"
  )

  private static let preferredImageTypeIdentifiers = [
    UTType.png.identifier,
    UTType.jpeg.identifier,
    UTType.heic.identifier,
    UTType.tiff.identifier,
    UTType.gif.identifier,
  ]

  static func currentChangeCount() -> Int {
    NSPasteboard.general.changeCount
  }

  static func snapshot(ifChangedFrom previousChangeCount: Int) -> PasteboardSnapshot? {
    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount
    guard changeCount != previousChangeCount else { return nil }

    let runningApplication = NSWorkspace.shared.frontmostApplication
    let source = SourceApplication(
      bundleIdentifier: runningApplication?.bundleIdentifier,
      localizedName: runningApplication?.localizedName
    )
    let types = pasteboard.types ?? []
    let rawTypeIdentifiers = types.map(\.rawValue)

    if types.contains(ClpPasteboardTypes.selfWrite) {
      return PasteboardSnapshot(
        changeCount: changeCount,
        source: source,
        disposition: .selfWrite
      )
    }

    if ClipboardContentRules.containsSensitivePasteboardType(rawTypeIdentifiers) {
      return PasteboardSnapshot(
        changeCount: changeCount,
        source: source,
        disposition: .sensitive
      )
    }

    if let bundleID = source.bundleIdentifier,
      ClipboardContentRules.isIgnoredBundleID(
        bundleID,
        ignoredBundleIDs: AppSettings.shared.ignoredBundleIDs
      )
    {
      return PasteboardSnapshot(
        changeCount: changeCount,
        source: source,
        disposition: .ignored(bundleID: bundleID)
      )
    }

    if let fileURL = firstFileURL(on: pasteboard) {
      do {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
          if accessed {
            fileURL.stopAccessingSecurityScopedResource()
          }
        }

        let bookmarkData = try fileURL.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        let payload = PasteboardPayload.file(
          bookmarkData: bookmarkData,
          displayName: fileURL.lastPathComponent,
          identity: fileURL.standardizedFileURL.path
        )
        return PasteboardSnapshot(
          changeCount: changeCount,
          source: source,
          disposition: .content(payload)
        )
      } catch {
        logger.error(
          "Could not create security-scoped bookmark: \(String(describing: error), privacy: .public)"
        )
        return PasteboardSnapshot(
          changeCount: changeCount,
          source: source,
          disposition: .unsupported
        )
      }
    }

    if let imageData = firstImageData(on: pasteboard, availableTypes: types) {
      return PasteboardSnapshot(
        changeCount: changeCount,
        source: source,
        disposition: .content(.image(imageData))
      )
    }

    if let text = pasteboard.string(forType: .string)
      ?? pasteboard.string(forType: .URL)
    {
      return PasteboardSnapshot(
        changeCount: changeCount,
        source: source,
        disposition: .content(.text(text))
      )
    }

    return PasteboardSnapshot(
      changeCount: changeCount,
      source: source,
      disposition: .unsupported
    )
  }

  private static func firstFileURL(on pasteboard: NSPasteboard) -> URL? {
    guard
      let objects = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      ) as? [URL]
    else {
      return nil
    }
    return objects.first(where: \.isFileURL)
  }

  private static func firstImageData(
    on pasteboard: NSPasteboard,
    availableTypes: [NSPasteboard.PasteboardType]
  ) -> Data? {
    let availableIdentifiers = availableTypes.map(\.rawValue)
    let orderedIdentifiers =
      preferredImageTypeIdentifiers
      + availableIdentifiers.filter {
        !preferredImageTypeIdentifiers.contains($0)
      }

    for identifier in orderedIdentifiers {
      guard
        ImagePayloadSupport.isImageTypeIdentifier(identifier),
        availableIdentifiers.contains(identifier),
        let data = pasteboard.data(
          forType: NSPasteboard.PasteboardType(identifier)
        ),
        !data.isEmpty
      else {
        continue
      }
      return data
    }
    return nil
  }
}

@MainActor
private final class ClipboardLifecycleObserver {
  static let shared = ClipboardLifecycleObserver()

  private var observerTokens: [NSObjectProtocol] = []

  private init() {}

  func install(engine: ClipboardEngine) {
    guard observerTokens.isEmpty else { return }

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    observerTokens.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: .main
      ) { [weak engine] _ in
        Task { await engine?.suspend(for: .systemSleep) }
      }
    )
    observerTokens.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { [weak engine] _ in
        Task { await engine?.resume(from: .systemSleep) }
      }
    )

    let distributedCenter = DistributedNotificationCenter.default()
    observerTokens.append(
      distributedCenter.addObserver(
        forName: Notification.Name("com.apple.screenIsLocked"),
        object: nil,
        queue: .main
      ) { [weak engine] _ in
        Task { await engine?.suspend(for: .screenLock) }
      }
    )
    observerTokens.append(
      distributedCenter.addObserver(
        forName: Notification.Name("com.apple.screenIsUnlocked"),
        object: nil,
        queue: .main
      ) { [weak engine] _ in
        Task { await engine?.resume(from: .screenLock) }
      }
    )
  }
}
