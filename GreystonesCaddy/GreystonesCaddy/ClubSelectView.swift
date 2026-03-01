import SwiftUI
import GreystonesCaddyCore

struct ClubSelectView: View {
  @EnvironmentObject var state: AppState
  @Environment(\.dismiss) private var dismiss

  @State private var query: String = ""

  var body: some View {
    NavigationStack {
      List {
        ForEach(filteredClubs) { c in
          Button {
            state.selectedClub = c
            dismiss()
          } label: {
            HStack {
              Text(c.rawValue)
              Spacer()
              if state.selectedClub == c { Image(systemName: "checkmark") }
            }
          }
        }
      }
      .navigationTitle("Select club")
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private var filteredClubs: [ClubID] {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return ClubID.allCases
    }
    let q = query.lowercased()
    return ClubID.allCases.filter { $0.rawValue.lowercased().contains(q) }
  }
}
