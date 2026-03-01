import SwiftUI
import GreystonesCaddyCore

struct HoleNotesView: View {
  let holeNumber: Int

  @State private var text: String = ""
  @State private var savedAt: String? = nil

  var body: some View {
    Form {
      Section("Caddy note") {
        TextEditor(text: $text)
          .frame(minHeight: 220)
      }

      Section {
        Button("Save") { save() }
          .frame(maxWidth: .infinity, alignment: .center)
      }

      if let savedAt {
        Section {
          Text(savedAt)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Hole \(holeNumber) note")
    .onAppear { load() }
  }

  private func load() {
    text = (try? GCDB.shared.fetchHoleNote(holeNumber: holeNumber)) ?? ""
  }

  private func save() {
    do {
      try GCDB.shared.upsertHoleNote(holeNumber: holeNumber, note: text.trimmingCharacters(in: .whitespacesAndNewlines))
      savedAt = "Saved"
    } catch {
      savedAt = "Save failed: \(error.localizedDescription)"
    }
  }
}
