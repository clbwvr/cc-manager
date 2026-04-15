import SwiftUI

struct TextPromptSheet: View {
    let title: String
    let placeholder: String
    let confirmLabel: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(
        title: String,
        placeholder: String,
        initial: String,
        confirmLabel: String = "Save",
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.confirmLabel = confirmLabel
        self.onSave = onSave
        self.onCancel = onCancel
        self._text = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 360)
                .onSubmit { commit() }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button(confirmLabel) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}
