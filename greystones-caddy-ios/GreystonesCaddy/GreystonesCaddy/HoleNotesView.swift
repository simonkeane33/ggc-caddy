import SwiftUI
import GreystonesCaddyCore

struct HoleNotesView: View {
  let holeNumber: Int

  @State private var text: String = ""
  @State private var status: String? = nil
  @FocusState private var isEditing: Bool

  var body: some View {
    Form {
      Section("Caddy note") {
        TextEditor(text: $text)
          .frame(minHeight: 220)
          .focused($isEditing)
      }

      if let status {
        Section {
          Text(status)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Hole \(holeNumber) note")
    .toolbar {
      // Save lives in the navigation bar rather than in a Form row. Inline, it
      // sat below the software keyboard while editing, and the first tap only
      // resigned the keyboard rather than activating the button — so a note
      // appeared not to save at all.
      ToolbarItem(placement: .topBarTrailing) {
        Button("Save") { save() }
          .fontWeight(.semibold)
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { isEditing = false }
      }
    }
    .onAppear { load() }
    // Belt and braces: leaving the screen commits whatever is in the editor, so
    // a note can't be lost by tapping back out of habit.
    .onDisappear { save() }
  }

  private func load() {
    text = (try? GCDB.shared.fetchHoleNote(holeNumber: holeNumber)) ?? ""
  }

  private func save() {
    do {
      try GCDB.shared.upsertHoleNote(
        holeNumber: holeNumber,
        note: text.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      isEditing = false
      status = "Saved"
    } catch {
      status = "Save failed: \(error.localizedDescription)"
    }
  }
}
