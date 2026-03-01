import SwiftUI
import GreystonesCaddyCore

struct HoleGuideView: View {
  let holeNumber: Int

  @Environment(\.dismiss) private var dismiss

  @State private var target: String = ""
  @State private var avoid: String = ""
  @State private var message: String? = nil

  var body: some View {
    Form {
      Section("Target") {
        TextField("e.g. Aim at left half / play to 150 marker", text: $target, axis: .vertical)
          .lineLimit(2...4)
      }

      Section("Avoid") {
        TextField("e.g. Don’t miss right (gorse) / don’t go long", text: $avoid, axis: .vertical)
          .lineLimit(2...4)
      }

      Section {
        Button("Save") { save() }
          .frame(maxWidth: .infinity, alignment: .center)
      }

      if let message {
        Section {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Hole \(holeNumber) guide")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { load() }
  }

  private func load() {
    if let g = try? GCDB.shared.fetchHoleGuide(holeNumber: holeNumber) {
      target = g.target
      avoid = g.avoid
    }
  }

  private func save() {
    do {
      try GCDB.shared.upsertHoleGuide(
        holeNumber: holeNumber,
        target: target.trimmingCharacters(in: .whitespacesAndNewlines),
        avoid: avoid.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      dismiss()
    } catch {
      message = "Save failed: \(error.localizedDescription)"
    }
  }
}
