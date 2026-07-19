import SwiftUI

@MainActor
struct EditTextView: View {
  @State private var text: String
  @FocusState private var editorIsFocused: Bool

  let onSave: (String) -> Void
  let onCancel: () -> Void

  init(
    initialText: String,
    onSave: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    _text = State(initialValue: initialText)
    self.onSave = onSave
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(spacing: 14) {
      TextEditor(text: $text)
        .font(.system(size: 13))
        .focused($editorIsFocused)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      HStack {
        Text("\(text.count) caracteres")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        Button("Cancelar", action: onCancel)
          .keyboardShortcut(.escape, modifiers: [])

        Button("Salvar") {
          onSave(text)
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(16)
    .frame(minWidth: 420, minHeight: 280)
    .task {
      editorIsFocused = true
    }
  }
}
