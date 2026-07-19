import Foundation
import Testing

@testable import Clp

@Suite("Navegação de clips")
struct ClipNavigationStateTests {
  @Test("Hover realça o card sem alterar foco ou scroll")
  func hoverDoesNotMoveFocusOrScroll() {
    let itemIDs = [UUID(), UUID(), UUID()]
    var state = ClipNavigationState()
    state.resetSelection(itemIDs: itemIDs)

    let initialTarget = state.scrollTargetID
    state.updateHover(itemID: itemIDs[2], isHovering: true)

    #expect(state.focusedIndex == 0)
    #expect(state.scrollTargetID == initialTarget)
    #expect(state.isHighlighted(index: 2, itemID: itemIDs[2]))
    #expect(!state.isHighlighted(index: 0, itemID: itemIDs[0]))
  }

  @Test("Saída atrasada de outro card não limpa o hover atual")
  func staleHoverExitDoesNotClearCurrentCard() {
    let firstID = UUID()
    let secondID = UUID()
    var state = ClipNavigationState()

    state.updateHover(itemID: firstID, isHovering: true)
    state.updateHover(itemID: secondID, isHovering: true)
    state.updateHover(itemID: firstID, isHovering: false)

    #expect(state.hoveredItemID == secondID)
  }

  @Test("Teclado limpa o hover e solicita scroll do novo foco")
  func keyboardNavigationOwnsFocusAndScroll() {
    let itemIDs = [UUID(), UUID(), UUID()]
    var state = ClipNavigationState()
    state.resetSelection(itemIDs: itemIDs)
    state.updateHover(itemID: itemIDs[2], isHovering: true)

    let didMove = state.moveFocus(by: 1, itemIDs: itemIDs)

    #expect(didMove)
    #expect(state.focusedIndex == 1)
    #expect(state.hoveredItemID == nil)
    #expect(state.scrollTargetID == itemIDs[1])
  }
}
