import AppKit
import SwiftUI

/// Campo de busca AppKit para o shelf não-ativante.
///
/// `TextField` + `@FocusState` do SwiftUI não recebem teclado de forma
/// confiável dentro de `NSPanel` `.nonactivatingPanel`. O `NSTextField`
/// assume first responder no clique e funciona com o painel apenas key.
@MainActor
struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let focusRequestID: Int
    let onMoveToResults: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClpPanelSearchField {
        let field = ClpPanelSearchField()
        field.delegate = context.coordinator
        field.placeholderAttributedString = NSAttributedString(
            string: "Buscar",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.focusRingType = .none
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.textColor = .labelColor
        field.maximumNumberOfLines = 1
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.cell?.sendsActionOnEndEditing = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Buscar no clipboard")
        field.onBecomeFocused = { [weak coordinator = context.coordinator] in
            coordinator?.parent.isFocused = true
        }
        return field
    }

    func updateNSView(_ field: ClpPanelSearchField, context: Context) {
        context.coordinator.parent = self
        field.onBecomeFocused = { [weak coordinator = context.coordinator] in
            coordinator?.parent.isFocused = true
        }

        if field.stringValue != text {
            field.stringValue = text
        }

        let shouldClaimFocus =
            isFocused
            && (
                context.coordinator.lastFocusRequestID != focusRequestID
                    || field.window?.firstResponder !== field
                        && field.window?.firstResponder !== field.currentEditor()
            )

        guard shouldClaimFocus else { return }

        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak field, weak coordinator] in
            guard
                let field,
                let coordinator,
                coordinator.parent.isFocused,
                let window = field.window
            else { return }

            coordinator.lastFocusRequestID = focusRequestID
            window.makeKeyAndOrderFront(nil)
            if window.makeFirstResponder(field) {
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PanelSearchField
        var lastFocusRequestID: Int?

        init(parent: PanelSearchField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)),
                #selector(NSResponder.insertTab(_:)):
                parent.isFocused = false
                textView.window?.makeFirstResponder(nil)
                parent.onMoveToResults()
                return true

            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true

            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true

            default:
                return false
            }
        }
    }
}

/// `NSTextField` que reivindica o teclado no mouseDown do painel não-ativante.
final class ClpPanelSearchField: NSTextField {
    var onBecomeFocused: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Em `.nonactivatingPanel`, o clique precisa tornar o painel key e o
        // campo first responder; o TextField do SwiftUI não faz isso sozinho.
        window?.makeKey()
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        onBecomeFocused?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onBecomeFocused?()
        }
        return became
    }
}
