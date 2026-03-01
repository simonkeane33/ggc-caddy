import SwiftUI
import GreystonesCaddyCore

struct HolePlanView: View {
  let holeNumber: Int

  @Environment(\.dismiss) private var dismiss

  @State private var saferTip: String = ""
  @State private var aggressiveTip: String = ""
  @State private var message: String? = nil

  var body: some View {
    Form {
      Section("Safer play") {
        TextField("One-line tip", text: $saferTip, axis: .vertical)
          .lineLimit(2...4)
      }

      Section("Aggressive play") {
        TextField("One-line tip", text: $aggressiveTip, axis: .vertical)
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
    .navigationTitle("Hole \(holeNumber) plan")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { load() }
  }

  private func load() {
    if let plan = try? GCDB.shared.fetchHolePlan(holeNumber: holeNumber) {
      saferTip = plan.saferTip
      aggressiveTip = plan.aggressiveTip
    }
  }

  private func save() {
    do {
      try GCDB.shared.upsertHolePlan(
        holeNumber: holeNumber,
        saferTip: saferTip.trimmingCharacters(in: .whitespacesAndNewlines),
        aggressiveTip: aggressiveTip.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      dismiss()
    } catch {
      message = "Save failed: \(error.localizedDescription)"
    }
  }
}
