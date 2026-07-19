import AppKit
import ImageIO
import SwiftUI

@MainActor
struct ClipCard: View {
  static let width: CGFloat = 170
  static let regularHeight: CGFloat = 200
  static let compactHeight: CGFloat = 135

  let item: ClipItem
  let boards: [Board]
  let shortcutNumber: Int?
  let isFocused: Bool
  let isCompact: Bool
  let isRenaming: Bool

  @Binding var renameText: String
  var isRenameFieldFocused: FocusState<Bool>.Binding

  let onSelect: () -> Void
  let onPin: (Board) -> Void
  let onUnpin: () -> Void
  let onStartRename: () -> Void
  let onCommitRename: () -> Void
  let onCancelRename: () -> Void
  let onDelete: () -> Void
  let onEditFile: () -> Void
  let onEditText: () -> Void

  private static let imageCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 256
    cache.totalCostLimit = 64 * 1_024 * 1_024
    return cache
  }()
  private static let appIconCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 128
    return cache
  }()
  private static var missingAppBundleIDs: Set<String> = []
  private static let thumbnailMaxPixelSize: CGFloat = regularHeight * 2

  @State private var thumbnailImage: NSImage?

  private var height: CGFloat {
    isCompact ? Self.compactHeight : Self.regularHeight
  }

  var body: some View {
    Group {
      if isRenaming {
        cardContents
      } else {
        Button(action: onSelect) {
          cardContents
        }
        .buttonStyle(.plain)
      }
    }
    .frame(width: Self.width, height: height)
    .clipShape(cardShape)
    .overlay {
      if isFocused {
        cardShape
          .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
      }
    }
    .shadow(
      color: isFocused ? headerColor.opacity(0.65) : .clear,
      radius: 8,
      y: 2
    )
    .scaleEffect(isFocused ? 1.015 : 1)
    .animation(.easeOut(duration: 0.14), value: isFocused)
    .contentShape(cardShape)
    .onDrag {
      ClipItemDrag.itemProvider(for: item)
    }
    .contextMenu {
      pinActions

      Divider()

      Button("Renomear", action: onStartRename)

      if item.contentType == .file {
        Button("Editar arquivo", action: onEditFile)
      } else if item.contentType == .text || item.contentType == .rtf {
        Button("Editar texto", action: onEditText)
      }

      Button("Excluir", role: .destructive, action: onDelete)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityAddTraits(isFocused ? [.isSelected] : [])
    .task(id: item.id) {
      await loadThumbnailIfNeeded()
    }
  }

  private var cardContents: some View {
    VStack(alignment: .leading, spacing: 0) {
      header

      preview
        .frame(
          maxWidth: .infinity,
          maxHeight: .infinity,
          alignment: .topLeading
        )
        .padding(isCompact ? 6 : 9)
        .background(Color.black.opacity(0.84))

      footer
    }
  }

  private var cardShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 15, style: .continuous)
  }

  private var header: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        if isRenaming {
          TextField("Título", text: $renameText)
            .textFieldStyle(.plain)
            .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
            .focused(isRenameFieldFocused)
            .onSubmit(onCommitRename)
            .onExitCommand(perform: onCancelRename)
        } else {
          Text(item.title ?? typeLabel)
            .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
            .lineLimit(1)
        }

        TimelineView(.periodic(from: .now, by: 30)) { _ in
          Text(relativeTimeLabel)
            .font(.system(size: isCompact ? 8 : 9))
            .foregroundStyle(.white.opacity(0.72))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      appIconBadge
    }
    .padding(.horizontal, isCompact ? 6 : 8)
    .frame(height: isCompact ? 35 : 43)
    .foregroundStyle(.white)
    .background(headerColor.opacity(0.88))
  }

  @ViewBuilder
  private var preview: some View {
    switch item.contentType {
    case .image:
      if let image = thumbnailImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        placeholder(symbol: "photo")
      }

    case .file:
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: "doc.fill")
          .font(.system(size: isCompact ? 13 : 16))
        Text(item.textContent ?? "Arquivo")
          .font(.system(size: isCompact ? 10 : 12, weight: .medium))
          .lineLimit(isCompact ? 2 : 4)
      }
      .foregroundStyle(.white)

    case .url:
      VStack(alignment: .leading, spacing: 5) {
        Image(systemName: "link")
          .font(.system(size: isCompact ? 12 : 14))
        Text(urlDisplayText)
          .font(.system(size: isCompact ? 10 : 11, weight: .medium))
          .lineLimit(isCompact ? 3 : 6)
      }
      .foregroundStyle(.white)

    case .text, .rtf:
      Text(item.textContent ?? "")
        .font(.system(size: isCompact ? 10 : 11, weight: .medium))
        .foregroundStyle(.white)
        .lineLimit(isCompact ? 4 : 7)
    }
  }

  private var footer: some View {
    HStack(spacing: 5) {
      Text(footerLabel)
        .lineLimit(1)

      Spacer(minLength: 4)

      if let shortcutNumber {
        HStack(spacing: 2) {
          Image(systemName: "number")
          Text("\(shortcutNumber)")
        }
        .fontWeight(.semibold)
      }
    }
    .font(.system(size: isCompact ? 8 : 9))
    .foregroundStyle(.white.opacity(0.58))
    .padding(.horizontal, isCompact ? 6 : 8)
    .padding(.vertical, isCompact ? 3 : 5)
    .background(Color.black.opacity(0.84))
  }

  @ViewBuilder
  private var pinActions: some View {
    if item.isPinned {
      if boards.count > 1 {
        Menu("Mover para") {
          ForEach(boards) { board in
            Button {
              onPin(board)
            } label: {
              if item.board?.id == board.id {
                Label(board.name, systemImage: "checkmark")
              } else {
                Text(board.name)
              }
            }
          }
        }
      }

      Button("Desafixar", action: onUnpin)
    } else if boards.isEmpty {
      Text("Crie um board para fixar")
    } else {
      Menu("Fixar em") {
        ForEach(boards) { board in
          Button(board.name) {
            onPin(board)
          }
        }
      }
    }
  }

  private var appIconBadge: some View {
    Group {
      if let icon = sourceAppIcon {
        Image(nsImage: icon)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Image(systemName: fallbackIconName)
          .font(.system(size: 12, weight: .medium))
      }
    }
    .frame(width: isCompact ? 24 : 28, height: isCompact ? 24 : 28)
    .background(Color.black.opacity(0.2))
    .clipShape(Circle())
    .accessibilityHidden(true)
  }

  private func placeholder(symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.title2)
      .foregroundStyle(.white.opacity(0.55))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func loadThumbnailIfNeeded() async {
    guard item.contentType == .image else {
      thumbnailImage = nil
      return
    }

    let key = item.id.uuidString as NSString
    if let cached = Self.imageCache.object(forKey: key) {
      thumbnailImage = cached
      return
    }

    guard let data = item.imageData else { return }
    let maxPixelSize = Self.thumbnailMaxPixelSize
    let image = await Task.detached(priority: .utility) {
      Self.makeThumbnail(
        from: data,
        maxPixelSize: maxPixelSize
      )
    }.value

    guard !Task.isCancelled, let image else { return }

    let thumbnail = NSImage(
      cgImage: image,
      size: NSSize(width: image.width, height: image.height)
    )
    Self.imageCache.setObject(
      thumbnail,
      forKey: key,
      cost: image.bytesPerRow * image.height
    )
    thumbnailImage = thumbnail
  }

  nonisolated private static func makeThumbnail(
    from data: Data,
    maxPixelSize: CGFloat
  ) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]

    return CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      options as CFDictionary
    )
  }

  private var sourceAppIcon: NSImage? {
    guard let bundleID = item.sourceAppBundleID, !bundleID.isEmpty else { return nil }
    let key = bundleID as NSString

    if let cached = Self.appIconCache.object(forKey: key) {
      return cached
    }

    guard !Self.missingAppBundleIDs.contains(bundleID) else { return nil }

    guard
      let appURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleID
      )
    else {
      Self.missingAppBundleIDs.insert(bundleID)
      return nil
    }

    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
    Self.appIconCache.setObject(icon, forKey: key)
    return icon
  }

  private var relativeTimeLabel: String {
    let elapsed = max(0, -item.createdAt.timeIntervalSinceNow)
    let minutes = Int(elapsed / 60)

    if minutes < 1 {
      return "agora"
    }
    if minutes < 60 {
      return "há \(minutes) min"
    }

    let hours = Int(elapsed / 3_600)
    if hours < 24 {
      return "há \(hours) h"
    }

    let days = Int(elapsed / 86_400)
    return "há \(days) d"
  }

  private var headerColor: Color {
    if item.isPinned, let color = item.board?.colorHex {
      return Color(hex: color)
    }

    switch item.contentType {
    case .text: return Color(red: 0.18, green: 0.45, blue: 0.92)
    case .rtf: return Color(red: 0.47, green: 0.35, blue: 0.92)
    case .image: return Color(red: 0.86, green: 0.30, blue: 0.48)
    case .file: return Color(red: 0.22, green: 0.63, blue: 0.50)
    case .url: return Color(red: 0.10, green: 0.58, blue: 0.78)
    }
  }

  private var typeLabel: String {
    switch item.contentType {
    case .text: return "Texto"
    case .rtf: return "Texto formatado"
    case .image: return "Imagem"
    case .file: return "Arquivo"
    case .url: return "Link"
    }
  }

  private var footerLabel: String {
    switch item.contentType {
    case .image:
      return "Imagem"
    case .file:
      return "Arquivo"
    case .url:
      return URL(string: item.textContent ?? "")?.host() ?? "Link"
    case .text, .rtf:
      return "\(item.textContent?.count ?? 0) caracteres"
    }
  }

  private var urlDisplayText: String {
    guard let value = item.textContent, let url = URL(string: value) else {
      return item.textContent ?? ""
    }
    return url.host() ?? value
  }

  private var fallbackIconName: String {
    switch item.contentType {
    case .text: return "doc.plaintext"
    case .rtf: return "doc.richtext"
    case .image: return "photo"
    case .file: return "doc"
    case .url: return "link"
    }
  }

  private var accessibilityLabel: String {
    [
      item.title ?? typeLabel,
      item.textContent,
      item.sourceAppName,
      relativeTimeLabel,
    ]
    .compactMap { $0 }
    .joined(separator: ", ")
  }
}
