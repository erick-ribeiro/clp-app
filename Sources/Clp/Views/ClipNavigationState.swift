import Foundation

/// Mantém navegação por teclado e realce por ponteiro independentes.
///
/// O hover não pode alterar `focusedIndex` nem `scrollTargetID`: fazer isso
/// cria um ciclo em que o card sob o ponteiro é centralizado, outro card passa
/// sob o ponteiro e uma nova rolagem começa.
struct ClipNavigationState: Equatable {
  var focusedIndex = 0
  var hoveredItemID: UUID?
  var scrollTargetID: UUID?

  mutating func resetForPresentation() {
    focusedIndex = 0
    hoveredItemID = nil
    scrollTargetID = nil
  }

  mutating func resetSelection(itemIDs: [UUID]) {
    focusedIndex = 0
    hoveredItemID = nil
    scrollTargetID = itemIDs.first
  }

  mutating func clampSelection(itemIDs: [UUID]) {
    guard !itemIDs.isEmpty else {
      resetForPresentation()
      return
    }

    focusedIndex = min(focusedIndex, itemIDs.count - 1)
    if let hoveredItemID, !itemIDs.contains(hoveredItemID) {
      self.hoveredItemID = nil
    }
    scrollTargetID = itemIDs[focusedIndex]
  }

  @discardableResult
  mutating func moveFocus(by delta: Int, itemIDs: [UUID]) -> Bool {
    guard !itemIDs.isEmpty else { return false }

    let nextIndex = max(
      0,
      min(itemIDs.count - 1, focusedIndex + delta)
    )
    guard nextIndex != focusedIndex else { return false }

    focusedIndex = nextIndex
    hoveredItemID = nil
    scrollTargetID = itemIDs[nextIndex]
    return true
  }

  @discardableResult
  mutating func updateHover(itemID: UUID, isHovering: Bool) -> Bool {
    if isHovering {
      guard hoveredItemID != itemID else { return false }
      hoveredItemID = itemID
      return true
    }

    guard hoveredItemID == itemID else { return false }
    hoveredItemID = nil
    return true
  }

  mutating func clearHover() {
    hoveredItemID = nil
  }

  func isHighlighted(index: Int, itemID: UUID) -> Bool {
    if let hoveredItemID {
      return hoveredItemID == itemID
    }
    return focusedIndex == index
  }
}
