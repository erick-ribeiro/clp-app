import Foundation
import Testing

@testable import Clp

@Suite("Regras de conteúdo do clipboard")
struct ClipboardContentRulesTests {
  @Test("SHA-256 é determinístico")
  func sha256IsDeterministic() {
    #expect(
      ClipboardContentRules.sha256(Data("hello".utf8))
        == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    )
  }

  @Test("Deduplica apenas contra o item mais recente")
  func deduplicatesAgainstMostRecent() {
    #expect(
      ClipboardContentRules.isDuplicateOfMostRecent(
        capturedHash: "A",
        mostRecentHash: "A"
      )
    )
    #expect(
      !ClipboardContentRules.isDuplicateOfMostRecent(
        capturedHash: "A",
        mostRecentHash: "B"
      )
    )
    #expect(
      !ClipboardContentRules.isDuplicateOfMostRecent(
        capturedHash: "A",
        mostRecentHash: nil
      )
    )
  }

  @Test("Tipos diferentes não colidem com o mesmo payload")
  func contentTypeDomainsDoNotCollide() {
    let data = Data("mesmo conteúdo".utf8)
    let textHash = ClipboardContentRules.contentHash(domain: .text, data: data)
    let fileHash = ClipboardContentRules.contentHash(domain: .file, data: data)
    let imageHash = ClipboardContentRules.contentHash(domain: .image, data: data)

    #expect(textHash != fileHash)
    #expect(textHash != imageHash)
    #expect(fileHash != imageHash)
  }

  @Test("Detecta apenas URL que ocupa o texto inteiro")
  func wholeURLDetection() {
    #expect(
      ClipboardContentRules.wholeURL(in: "  https://apple.com/mac  ")
        == "https://apple.com/mac"
    )
    #expect(
      ClipboardContentRules.wholeURL(in: "Acesse https://apple.com/mac") == nil
    )
  }

  @Test("Reconhece marcadores sensíveis sem diferenciar caixa")
  func sensitivePasteboardTypes() {
    #expect(
      ClipboardContentRules.containsSensitivePasteboardType([
        "org.nspasteboard.ConcealedType"
      ])
    )
    #expect(
      ClipboardContentRules.containsSensitivePasteboardType([
        "ORG.NSPASTEBOARD.TRANSIENTTYPE"
      ])
    )
    #expect(
      !ClipboardContentRules.containsSensitivePasteboardType([
        "public.utf8-plain-text"
      ])
    )
  }

  @Test("Bundle IDs ignorados não diferenciam caixa")
  func ignoredBundleIDsAreCaseInsensitive() {
    #expect(
      ClipboardContentRules.isIgnoredBundleID(
        "com.apple.Safari",
        ignoredBundleIDs: ["COM.APPLE.SAFARI"]
      )
    )
    #expect(
      !ClipboardContentRules.isIgnoredBundleID(
        "com.apple.Notes",
        ignoredBundleIDs: ["com.apple.Safari"]
      )
    )
  }

  @Test("Hash de arquivo acompanha o conteúdo")
  func fileHashTracksContent() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }

    try Data("primeiro".utf8).write(to: fileURL)
    let firstHash = try ClipboardContentRules.sha256File(at: fileURL)

    try Data("segundo".utf8).write(to: fileURL)
    let secondHash = try ClipboardContentRules.sha256File(at: fileURL)

    #expect(firstHash != secondHash)
  }
}
